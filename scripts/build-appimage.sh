#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION=""
DOWNLOAD_URL=""
TARBALL_PATH=""
USE_LATEST=false
DRY_RUN=false
APPIMAGETOOL_CUSTOM=""
REPO="${GITHUB_REPOSITORY:-}"
OUTPUT_DIR="${ROOT_DIR}/dist"

usage() {
    cat << USAGE
Usage: $0 [OPTIONS]

Builds a Google Antigravity AppImage with AppImageUpdate configuration.

Options:
  --latest                  Automatically detect and build the latest upstream release
  --version <VERSION>       Specify version number (e.g. 2.12.2)
  --download-url <URL>      Direct URL to Antigravity.tar.gz
  --tarball <PATH>          Path to an existing local Antigravity.tar.gz (skips download)
  --appimagetool <PATH>     Path to an existing appimagetool binary or AppImage
  --repo <OWNER/REPO>       GitHub repository in 'owner/repo' format (for update metadata)
  --output-dir <DIR>        Destination directory for AppImage artifacts (default: ./dist)
  --dry-run                 Assemble AppDir and validate structure, but skip final AppImage packaging
  -h, --help                Show this help message

Examples:
  # Build the latest upstream release:
  $0 --latest

  # Test build using a local tarball:
  $0 --version 2.12.2 --tarball /path/to/Antigravity.tar.gz

  # Build specific version with download URL:
  $0 --version 2.12.2 --download-url https://storage.googleapis.com/...
USAGE
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --latest)
            USE_LATEST=true
            shift 1
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --download-url)
            DOWNLOAD_URL="$2"
            shift 2
            ;;
        --tarball)
            TARBALL_PATH="$2"
            shift 2
            ;;
        --appimagetool)
            APPIMAGETOOL_CUSTOM="$2"
            shift 2
            ;;
        --repo)
            REPO="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift 1
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            ;;
    esac
done

# If --latest is specified, query scripts/check-version.py
if [[ "${USE_LATEST}" == "true" ]]; then
    echo "==> Querying latest upstream Antigravity 2.x release..."
    CHECK_INFO="$(python3 "${SCRIPT_DIR}/check-version.py" --check-only)"
    DETECTED_VERSION="$(echo "${CHECK_INFO}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('version', ''))")"
    DETECTED_URL="$(echo "${CHECK_INFO}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('download_url', ''))")"

    if [[ -z "${VERSION}" ]]; then
        VERSION="${DETECTED_VERSION}"
    fi
    if [[ -z "${DOWNLOAD_URL}" && -z "${TARBALL_PATH}" ]]; then
        DOWNLOAD_URL="${DETECTED_URL}"
    fi
fi

if [[ -z "${VERSION}" ]]; then
    echo "Error: Version not specified. Provide --version <VER> or use --latest." >&2
    usage
fi

if [[ -z "${DOWNLOAD_URL}" && -z "${TARBALL_PATH}" ]]; then
    echo "Error: No download source specified. Provide --download-url <URL>, --tarball <PATH>, or use --latest." >&2
    usage
fi

# Detect repository if not provided
if [[ -z "${REPO}" ]]; then
    REMOTE_URL="$(git -C "${ROOT_DIR}" config --get remote.origin.url 2>/dev/null || true)"
    if [[ "${REMOTE_URL}" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
        REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    else
        REPO="rmonk/antigravity-appimage"
    fi
fi

echo "=================================================="
echo " Building Antigravity AppImage"
echo " Version:       ${VERSION}"
echo " Source:        ${TARBALL_PATH:-${DOWNLOAD_URL}}"
echo " Repository:    ${REPO}"
echo " Output Dir:    ${OUTPUT_DIR}"
echo " Dry Run:       ${DRY_RUN}"
echo "=================================================="

WORK_DIR="$(mktemp -d -t antigravity-build-XXXXXX)"
trap 'rm -rf "${WORK_DIR}"' EXIT

APPDIR="${WORK_DIR}/AppDir"
mkdir -p "${APPDIR}" "${OUTPUT_DIR}"

# ----------------------------------------------------
# 1. Obtain Antigravity tarball
# ----------------------------------------------------
TAR_FILE="${WORK_DIR}/Antigravity.tar.gz"
if [[ -n "${TARBALL_PATH}" ]]; then
    if [[ ! -f "${TARBALL_PATH}" ]]; then
        echo "Error: Local tarball not found: ${TARBALL_PATH}" >&2
        exit 1
    fi
    echo "==> Using local tarball: ${TARBALL_PATH}"
    cp "${TARBALL_PATH}" "${TAR_FILE}"
else
    echo "==> Downloading Antigravity tarball from: ${DOWNLOAD_URL}..."
    curl -sSL --fail --retry 3 --retry-delay 2 "${DOWNLOAD_URL}" -o "${TAR_FILE}"
fi

echo "==> Extracting Antigravity tarball..."
EXTRACT_DIR="${WORK_DIR}/extracted"
mkdir -p "${EXTRACT_DIR}"
tar -xzf "${TAR_FILE}" -C "${EXTRACT_DIR}"

# Find directory containing the antigravity binary
BINARY_LOC="$(find "${EXTRACT_DIR}" -type f -name "antigravity" -perm -111 | head -n 1)"
if [[ -z "${BINARY_LOC}" ]]; then
    BINARY_LOC="$(find "${EXTRACT_DIR}" -type f -iname "antigravity" | head -n 1)"
fi

if [[ -z "${BINARY_LOC}" ]]; then
    echo "Error: Failed to find 'antigravity' executable in extracted archive." >&2
    ls -laR "${EXTRACT_DIR}" >&2
    exit 1
fi

APP_SOURCE_DIR="$(dirname "${BINARY_LOC}")"
echo "==> Application files located at: ${APP_SOURCE_DIR}"

# ----------------------------------------------------
# 2. Assemble AppDir
# ----------------------------------------------------
echo "==> Assembling AppDir structure..."
mkdir -p "${APPDIR}/opt/antigravity"
mkdir -p "${APPDIR}/usr/bin"
mkdir -p "${APPDIR}/usr/share/applications"
mkdir -p "${APPDIR}/usr/share/icons/hicolor/256x256/apps"

# Copy entire application package into /opt/antigravity
cp -a "${APP_SOURCE_DIR}/." "${APPDIR}/opt/antigravity/"
chmod +x "${APPDIR}/opt/antigravity/antigravity"

# Create symlinks in /usr/bin/antigravity and AppDir root
ln -sf "../opt/antigravity/antigravity" "${APPDIR}/usr/bin/antigravity"
ln -sf "opt/antigravity/antigravity" "${APPDIR}/antigravity"

# Fix chrome-sandbox permissions if present
if [[ -f "${APPDIR}/opt/antigravity/chrome-sandbox" ]]; then
    chmod 4755 "${APPDIR}/opt/antigravity/chrome-sandbox" 2>/dev/null || chmod +x "${APPDIR}/opt/antigravity/chrome-sandbox"
fi

# Install Desktop Entry
cp "${ROOT_DIR}/assets/antigravity.desktop" "${APPDIR}/antigravity.desktop"
cp "${ROOT_DIR}/assets/antigravity.desktop" "${APPDIR}/usr/share/applications/antigravity.desktop"

# Install Icon (Prefer bundled icon if available, else fallback to assets/antigravity.png)
BUNDLED_ICON=""
for icon_candidate in \
    "${APPDIR}/opt/antigravity/resources/app/icon.png" \
    "${APPDIR}/opt/antigravity/resources/icon.png" \
    "${APPDIR}/opt/antigravity/antigravity.png"; do
    if [[ -f "${icon_candidate}" ]]; then
        BUNDLED_ICON="${icon_candidate}"
        break
    fi
done

if [[ -n "${BUNDLED_ICON}" ]]; then
    echo "==> Using bundled icon from ${BUNDLED_ICON}"
    cp "${BUNDLED_ICON}" "${APPDIR}/antigravity.png"
    cp "${BUNDLED_ICON}" "${APPDIR}/usr/share/icons/hicolor/256x256/apps/antigravity.png"
else
    echo "==> Using repository icon from assets/antigravity.png"
    cp "${ROOT_DIR}/assets/antigravity.png" "${APPDIR}/antigravity.png"
    cp "${ROOT_DIR}/assets/antigravity.png" "${APPDIR}/usr/share/icons/hicolor/256x256/apps/antigravity.png"
fi

# Install AppRun script
cp "${ROOT_DIR}/scripts/AppRun" "${APPDIR}/AppRun"
chmod +x "${APPDIR}/AppRun"

echo "==> AppDir assembly completed successfully."

# If dry-run requested, validate AppDir and exit early
if [[ "${DRY_RUN}" == "true" ]]; then
    echo "==> Dry run mode enabled. Validating AppDir..."
    test -x "${APPDIR}/AppRun" || { echo "Error: AppRun is not executable"; exit 1; }
    test -f "${APPDIR}/antigravity.desktop" || { echo "Error: Missing antigravity.desktop"; exit 1; }
    test -f "${APPDIR}/antigravity.png" || { echo "Error: Missing antigravity.png"; exit 1; }
    test -x "${APPDIR}/opt/antigravity/antigravity" || { echo "Error: antigravity binary not executable"; exit 1; }
    echo "==> AppDir validation passed. (Skipping appimagetool due to --dry-run)"
    exit 0
fi

# ----------------------------------------------------
# 3. Setup appimagetool
# ----------------------------------------------------
echo "==> Preparing appimagetool..."
APPIMAGETOOL_BIN=""
if [[ -n "${APPIMAGETOOL_CUSTOM}" ]]; then
    if [[ ! -x "${APPIMAGETOOL_CUSTOM}" ]]; then
        echo "Error: Specified appimagetool is not executable: ${APPIMAGETOOL_CUSTOM}" >&2
        exit 1
    fi
    APPIMAGETOOL_BIN="${APPIMAGETOOL_CUSTOM}"
elif command -v appimagetool >/dev/null 2>&1; then
    APPIMAGETOOL_BIN="appimagetool"
else
    TOOL_PATH="${WORK_DIR}/appimagetool-x86_64.AppImage"
    echo "Downloading appimagetool..."
    curl -sSL --fail --retry 3 "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage" -o "${TOOL_PATH}"
    chmod +x "${TOOL_PATH}"

    # Extract appimagetool to avoid FUSE dependency issues
    echo "Extracting appimagetool..."
    (cd "${WORK_DIR}" && "${TOOL_PATH}" --appimage-extract >/dev/null 2>&1)
    APPIMAGETOOL_BIN="${WORK_DIR}/squashfs-root/AppRun"
fi

# ----------------------------------------------------
# 4. Formulate AppImageUpdate Configuration
# ----------------------------------------------------
APPIMAGE_NAME="Antigravity-${VERSION}-x86_64.AppImage"
UPDATE_ARGS=()

if [[ -n "${REPO}" && "${REPO}" =~ ^([^/]+)/([^/]+)$ ]]; then
    REPO_OWNER="${BASH_REMATCH[1]}"
    REPO_NAME="${BASH_REMATCH[2]}"
    UPDATE_STRING="gh-releases-zsync|${REPO_OWNER}|${REPO_NAME}|latest|Antigravity*-x86_64.AppImage.zsync"
    echo "==> Configuring AppImage update information: ${UPDATE_STRING}"
    UPDATE_ARGS+=("-u" "${UPDATE_STRING}")
else
    echo "==> Warning: No valid GitHub repository provided. Building without embedded update information."
fi

# ----------------------------------------------------
# 5. Build AppImage
# ----------------------------------------------------
echo "==> Running appimagetool..."
export ARCH="x86_64"
export APPIMAGE_EXTRACT_AND_RUN=1

"${APPIMAGETOOL_BIN}" "${UPDATE_ARGS[@]}" "${APPDIR}" "${OUTPUT_DIR}/${APPIMAGE_NAME}"

# ----------------------------------------------------
# 6. Generate Checksums
# ----------------------------------------------------
echo "==> Generating SHA256 checksums..."
cd "${OUTPUT_DIR}"
sha256sum "${APPIMAGE_NAME}" > SHA256SUMS.txt
if [[ -f "${APPIMAGE_NAME}.zsync" ]]; then
    sha256sum "${APPIMAGE_NAME}.zsync" >> SHA256SUMS.txt
fi

echo "=================================================="
echo " Build Complete!"
echo " Artifacts in: ${OUTPUT_DIR}"
ls -lh "${OUTPUT_DIR}"
echo "=================================================="
