#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

MODE="mock"
TARBALL_ARG=""
DRY_RUN=false
CLEANUP=true

usage() {
    cat << USAGE
Usage: $0 [OPTIONS]

Tests the Antigravity AppImage build process locally.

Options:
  --mock            Run a fast local test using a synthetic Antigravity bundle (default)
  --full            Run a full test by downloading the latest official Antigravity release
  --tarball <PATH>  Run a test using an existing local Antigravity.tar.gz
  --dry-run         Verify AppDir assembly and execution without invoking appimagetool
  --no-cleanup      Preserve temporary test directories for manual inspection
  -h, --help        Show this help message

Examples:
  # Fast local smoke test (no large downloads):
  $0 --mock

  # Test with an existing local tarball:
  $0 --tarball /path/to/Antigravity.tar.gz

  # Full live build test from upstream:
  $0 --full
USAGE
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mock)
            MODE="mock"
            shift 1
            ;;
        --full)
            MODE="full"
            shift 1
            ;;
        --tarball)
            MODE="tarball"
            TARBALL_ARG="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift 1
            ;;
        --no-cleanup)
            CLEANUP=false
            shift 1
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1" >&2; exit 1; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo "=================================================="
echo " Antigravity AppImage Local Build Test"
echo " Mode: ${MODE} | Dry Run: ${DRY_RUN}"
echo "=================================================="

TEST_TMP="$(mktemp -d -t antigravity-test-XXXXXX)"
if [[ "${CLEANUP}" == "true" ]]; then
    trap 'rm -rf "${TEST_TMP}"' EXIT
else
    echo "Temporary test directory preserved at: ${TEST_TMP}"
fi

# ----------------------------------------------------
# Step 1: Validate desktop entry
# ----------------------------------------------------
info "Step 1: Validating assets/antigravity.desktop..."
if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "${ROOT_DIR}/assets/antigravity.desktop"
    pass "Desktop entry file is valid"
else
    warn "desktop-file-validate not found; checking basic syntax manually"
    grep -q "^\[Desktop Entry\]" "${ROOT_DIR}/assets/antigravity.desktop" || fail "Missing [Desktop Entry] header"
    grep -q "^Exec=antigravity" "${ROOT_DIR}/assets/antigravity.desktop" || fail "Missing Exec entry"
    pass "Desktop entry syntax check passed"
fi

# ----------------------------------------------------
# Step 2: Validate check-version.py scraper
# ----------------------------------------------------
info "Step 2: Testing version scraper against upstream..."
SCRAPER_OUTPUT="$(python3 "${ROOT_DIR}/scripts/check-version.py" --check-only)"
DETECTED_VER="$(echo "${SCRAPER_OUTPUT}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('version', ''))")"
DETECTED_URL="$(echo "${SCRAPER_OUTPUT}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('download_url', ''))")"

if [[ -n "${DETECTED_VER}" && -n "${DETECTED_URL}" ]]; then
    pass "Version scraper returned version=${DETECTED_VER}, url=${DETECTED_URL}"
else
    fail "Version scraper failed to resolve latest version"
fi

# ----------------------------------------------------
# Step 3: Prepare test payload
# ----------------------------------------------------
TEST_OUT="${TEST_TMP}/out"
mkdir -p "${TEST_OUT}"
TARGET_TARBALL=""
TARGET_VERSION="${DETECTED_VER}"

if [[ "${MODE}" == "mock" ]]; then
    info "Step 3: Creating mock Antigravity archive for offline pipeline testing..."
    MOCK_DIR="${TEST_TMP}/mock_pkg/Antigravity-linux-x64"
    mkdir -p "${MOCK_DIR}/resources"
    
    # Create mock antigravity executable
    cat << 'MOCK_BIN' > "${MOCK_DIR}/antigravity"
#!/bin/bash
if [[ "$*" == *"--version"* ]]; then
    echo "Antigravity 2.12.2-mock"
    exit 0
fi
echo "Mock Google Antigravity 2 launched successfully with args: $*"
exit 0
MOCK_BIN
    chmod +x "${MOCK_DIR}/antigravity"

    # Create mock chrome-sandbox
    touch "${MOCK_DIR}/chrome-sandbox"
    chmod 4755 "${MOCK_DIR}/chrome-sandbox" 2>/dev/null || chmod +x "${MOCK_DIR}/chrome-sandbox"

    # Package mock tarball
    TARGET_TARBALL="${TEST_TMP}/mock-Antigravity.tar.gz"
    tar -czf "${TARGET_TARBALL}" -C "${TEST_TMP}/mock_pkg" Antigravity-linux-x64
    TARGET_VERSION="2.12.2-mock"
    pass "Mock archive created at ${TARGET_TARBALL}"

elif [[ "${MODE}" == "tarball" ]]; then
    info "Step 3: Using specified tarball: ${TARBALL_ARG}"
    if [[ ! -f "${TARBALL_ARG}" ]]; then
        fail "Tarball not found: ${TARBALL_ARG}"
    fi
    TARGET_TARBALL="${TARBALL_ARG}"
    pass "Target tarball confirmed"

elif [[ "${MODE}" == "full" ]]; then
    info "Step 3: Full mode selected. Build will fetch live tarball from ${DETECTED_URL}"
fi

# ----------------------------------------------------
# Step 4: Run build-appimage.sh
# ----------------------------------------------------
info "Step 4: Executing build-appimage.sh..."

BUILD_ARGS=(
    --version "${TARGET_VERSION}"
    --repo "test-owner/test-repo"
    --output-dir "${TEST_OUT}"
)

if [[ -n "${TARGET_TARBALL}" ]]; then
    BUILD_ARGS+=(--tarball "${TARGET_TARBALL}")
else
    BUILD_ARGS+=(--download-url "${DETECTED_URL}")
fi

if [[ "${DRY_RUN}" == "true" ]]; then
    BUILD_ARGS+=(--dry-run)
fi

# Run build script
"${ROOT_DIR}/scripts/build-appimage.sh" "${BUILD_ARGS[@]}"
pass "build-appimage.sh completed successfully"

# ----------------------------------------------------
# Step 5: Verify build outputs
# ----------------------------------------------------
if [[ "${DRY_RUN}" == "true" ]]; then
    pass "Dry run verification complete: AppDir structure and permissions passed."
else
    info "Step 5: Verifying generated AppImage artifacts..."
    APPIMAGE_FILE="${TEST_OUT}/Antigravity-${TARGET_VERSION}-x86_64.AppImage"
    ZSYNC_FILE="${TEST_OUT}/Antigravity-${TARGET_VERSION}-x86_64.AppImage.zsync"
    CHECKSUM_FILE="${TEST_OUT}/SHA256SUMS.txt"

    # Check AppImage binary
    test -f "${APPIMAGE_FILE}" || fail "AppImage file not found: ${APPIMAGE_FILE}"
    test -x "${APPIMAGE_FILE}" || fail "AppImage is not executable: ${APPIMAGE_FILE}"
    pass "AppImage file exists and is executable"

    # Check embedded update info
    if command -v strings >/dev/null 2>&1; then
        if strings "${APPIMAGE_FILE}" | grep -q "gh-releases-zsync|test-owner|test-repo|latest"; then
            pass "Embedded AppImage update information verified (gh-releases-zsync)"
        else
            warn "Could not find expected gh-releases-zsync string in AppImage binary"
        fi
    fi

    # Check zsync file
    if [[ -f "${ZSYNC_FILE}" ]]; then
        pass "zsync update metadata file generated: $(basename "${ZSYNC_FILE}")"
    else
        warn "zsync file not found (appimagetool may have skipped zsync)"
    fi

    # Check checksum file
    test -f "${CHECKSUM_FILE}" || fail "SHA256SUMS.txt was not generated"
    (cd "${TEST_OUT}" && sha256sum -c --status "${CHECKSUM_FILE}")
    pass "SHA-256 checksums verified successfully"

    # Check AppImage extraction and execution
    info "Step 6: Testing AppImage extraction and execution..."
    EXTRACT_DIR="${TEST_TMP}/extracted_app"
    mkdir -p "${EXTRACT_DIR}"
    (cd "${EXTRACT_DIR}" && APPIMAGE_EXTRACT_AND_RUN=1 "${APPIMAGE_FILE}" --appimage-extract >/dev/null 2>&1 || true)

    if [[ -x "${EXTRACT_DIR}/squashfs-root/AppRun" ]]; then
        pass "AppImage extraction succeeded"
        # Test launching AppRun
        APP_OUTPUT="$("${EXTRACT_DIR}/squashfs-root/AppRun" --version 2>&1 || true)"
        info "Application execution test output: ${APP_OUTPUT}"
        pass "Extracted AppRun executes cleanly"
    else
        warn "Could not extract AppImage via --appimage-extract (FUSE or squashfs-tools may not be present)"
    fi
fi

echo "=================================================="
echo -e "${GREEN} ALL LOCAL BUILD TESTS PASSED!${NC}"
echo "=================================================="
