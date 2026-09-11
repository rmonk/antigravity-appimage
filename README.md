# Google Antigravity AppImage

Automated GitHub Actions build pipeline that packages [Google Antigravity 2](https://antigravity.google) for Linux (x64) into a portable, self-updating **AppImage**.

[![Build and Release Antigravity AppImage](https://github.com/rmonk/antigravity-appimage/actions/workflows/build-appimage.yml/badge.svg)](https://github.com/rmonk/antigravity-appimage/actions/workflows/build-appimage.yml)

---

## Features

- **Automated Upstream Polling**: Runs every 12 hours via GitHub Actions (`cron: '0 */12 * * *'`), monitoring [https://antigravity.google/releases/](https://antigravity.google/releases/) for new Antigravity 2.x releases.
- **Smart Change Detection**: Automatically compares newly detected upstream versions against existing GitHub releases to avoid redundant rebuilds.
- **Delta Updates via `zsync`**: Embeds standard `gh-releases-zsync` update metadata into every built AppImage, enabling users to update to new releases by downloading only changed byte blocks.
- **Clean Runtime Sandbox Handling**: The custom `AppRun` handles Electron runtime requirements and unprivileged user namespace profiles on modern Linux systems (e.g. Ubuntu 24.04+).
- **Local Testing & Verification**: Includes a local test runner and Makefile (`make test`, `make build`, `make check`) to test and build locally.
- **Manual Trigger Support**: Easily trigger builds on-demand or specify custom versions via GitHub's `workflow_dispatch` interface.

---

## How to Install and Run

### 1. Download

Download the latest `Antigravity-*-x86_64.AppImage` from the [Releases](https://github.com/rmonk/antigravity-appimage/releases/latest) page.

### 2. Make Executable and Run

```bash
chmod +x Antigravity-*-x86_64.AppImage
./Antigravity-*-x86_64.AppImage
```

---

## AppImage Delta Updates

This AppImage is built with embedded update configuration pointing directly to this repository's GitHub Releases:

```text
gh-releases-zsync|rmonk|antigravity-appimage|latest|Antigravity*-x86_64.AppImage.zsync
```

### Updating with `appimageupdatetool`

You can check for updates and update your AppImage in place without downloading the entire package:

```bash
# Update in-place
appimageupdatetool Antigravity-*-x86_64.AppImage
```

Or use graphical desktop managers such as **AppImageLauncher** or **AppImageUpdate GUI**, which detect the embedded update information automatically.

---

## Local Development & Testing

A `Makefile` and test script are provided to make local building and testing straightforward.

### Quick Commands

```bash
# Show all available Makefile commands
make help

# Check upstream for the latest release
make check

# Run local build pipeline test (dry run / mock)
make test

# Validate desktop file, scripts, and workflow YAML
make validate

# Build the latest upstream release locally
make build
```

### Advanced Local Testing via `test-local-build.sh`

The test runner [`scripts/test-local-build.sh`](scripts/test-local-build.sh) supports multiple testing modes:

```bash
# 1. Fast offline smoke test with synthetic mock package (no network download):
./scripts/test-local-build.sh --mock

# 2. Dry-run verification (validates AppDir assembly and permissions without appimagetool):
./scripts/test-local-build.sh --dry-run

# 3. Test using an existing local Antigravity.tar.gz file:
./scripts/test-local-build.sh --tarball /path/to/Antigravity.tar.gz

# 4. Full end-to-end test with live upstream download:
./scripts/test-local-build.sh --full
```

### Manual Local Build via `build-appimage.sh`

```bash
# Automatically fetch and build the latest version:
./scripts/build-appimage.sh --latest

# Or build from an existing local tarball:
./scripts/build-appimage.sh \
  --version "2.12.2" \
  --tarball "/path/to/Antigravity.tar.gz" \
  --repo "rmonk/antigravity-appimage" \
  --output-dir "./dist"
```

Artifacts are produced in `./dist/`:
- `Antigravity-<version>-x86_64.AppImage`
- `Antigravity-<version>-x86_64.AppImage.zsync`
- `SHA256SUMS.txt`

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       └── build-appimage.yml    # GitHub Actions workflow (runs every 12h + manual dispatch)
├── assets/
│   ├── antigravity.desktop       # Freedesktop application entry
│   └── antigravity.png           # High-resolution application logo
├── scripts/
│   ├── AppRun                    # AppImage entrypoint script (Electron sandbox & path setup)
│   ├── build-appimage.sh         # AppDir assembly and appimagetool packager
│   ├── check-version.py          # Upstream version scraper and GitHub release comparator
│   └── test-local-build.sh       # Local build and pipeline verification runner
├── .gitignore
├── LICENSE
├── Makefile                      # Developer shortcut targets
└── README.md
```

---

## Triggering via GitHub Actions

1. Go to the **Actions** tab in your repository.
2. Select the **Build and Release Antigravity AppImage** workflow.
3. Click **Run workflow**.
4. (Optional) Toggle **Force build even if release already exists** or enter a specific version override.

---

## License & Attribution

- Packaging scripts in this repository are released under the [MIT License](LICENSE).
- Google Antigravity is developed and maintained by Google.
