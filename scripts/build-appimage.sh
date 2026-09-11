#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION=""
DOWNLOAD_URL=""
REPO="${GITHUB_REPOSITORY:-}"
OUTPUT_DIR="${ROOT_DIR}/dist"

usage() {
    cat << USAGE
Usage: $0 --version <VERSION> --download-url <URL> [--repo <OWNER/REPO>] [--output-dir <DIR>]

Builds a Google Antigravity AppImage with AppImageUpdate configuration.

Options:
  --version       Version number (e.g. 2.12.2)
  --download-url  Direct URL to Antigravity.tar.gz
  --repo          GitHub repository in 'owner/repo' format (used for update info)
  --output-dir    Destination directory for AppImage artifacts (default: ./dist)
  -h, --help      Show this help message
USAGE
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --download-url)
            DOWNLOAD_URL="$2"
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
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            ;;
    esac
done

if [[ -z "${VERSION}" || -z "${DOWNLOAD_URL}" ]]; then
    echo "Error: --version and --download-url are required." >&2
    usage
fi

echo "=================================================="
echo " Building Antigravity AppImage"
echo " Version:      ${VERSION}"
echo " Download URL: ${DOWNLOAD_URL}"
echo " Repository:   ${REPO:-<none>}"
echo " Output Dir:   ${OUTPUT_DIR}"
echo "=================================================="

WORK_DIR="$(mktemp -d -t antigravity-build-XXXXXX)"
trap 'rm -rf "${WORK_DIR}"' EXIT

APPDIR="${WORK_DIR}/AppDir"
mkdir -p "${APPDIR}" "${OUTPUT_DIR}"

# ----------------------------------------------------
# 1. Download Antigravity tarball
# ----------------------------------------------------
echo "==> Downloading Antigravity tarball..."
TAR_FILE="${WORK_DIR}/Antigravity.tar.gz"
curl -sSL --fail --retry 3 --retry-delay 2 "${DOWNLOAD_URL}" -o "${TAR_FILE}"

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

# Create symlink in /usr/bin/antigravity and AppDir root
ln -sf "../opt/antigravity/antigravity" "${APPDIR}/usr/bin/antigravity"
ln -sf "opt/antigravity/antigravity" "${APPDIR}/antigravity"

# Fix chrome-sandbox permissions if present
if [[ -f "${APPDIR}/opt/antigravity/chrome-sandbox" ]]; then
    chmod 4755 "${APPDIR}/opt/antigravity/chrome-sandbox" || chmod +x "${APPDIR}/opt/antigravity/chrome-sandbox"
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

# ----------------------------------------------------
# 3. Setup appimagetool
# ----------------------------------------------------
echo "==> Preparing appimagetool..."
APPIMAGETOOL_BIN=""
if command -v appimagetool >/dev/null 2>&1; then
    APPIMAGETOOL_BIN="appimagetool"
else
    TOOL_PATH="${WORK_DIR}/appimagetool-x86_64.AppImage"
    echo "Downloading appimagetool..."
    curl -sSL --fail --retry 3 "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage" -o "${TOOL_PATH}"
    chmod +x "${TOOL_PATH}"

    # Extract appimagetool to avoid FUSE dependency issues in CI environments
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
sha256sum "Antigravity-${VERSION}-x86_64.AppImage" > SHA256SUMS.txt
if [[ -f "Antigravity-${VERSION}-x86_64.AppImage.zsync" ]]; then
    sha256sum "Antigravity-${VERSION}-x86_64.AppImage.zsync" >> SHA256SUMS.txt
fi

echo "=================================================="
echo " Build Complete!"
echo " Artifacts in: ${OUTPUT_DIR}"
ls -lh "${OUTPUT_DIR}"
echo "=================================================="
