# Google Antigravity AppImage

Automated GitHub Actions build pipeline that packages [Google Antigravity 2](https://antigravity.google) for Linux (x64) into a portable, self-updating **AppImage**.

[![Build and Release Antigravity AppImage](https://github.com/OWNER/REPOSITORY/actions/workflows/build-appimage.yml/badge.svg)](https://github.com/OWNER/REPOSITORY/actions/workflows/build-appimage.yml)

---

## Features

- **Automated Upstream Polling**: Runs every 12 hours via GitHub Actions (`cron: '0 */12 * * *'`), monitoring [https://antigravity.google/releases/](https://antigravity.google/releases/) for new Antigravity 2.x releases.
- **Smart Change Detection**: Automatically compares newly detected upstream versions against existing GitHub releases to avoid redundant rebuilds.
- **Delta Updates via `zsync`**: Embeds standard `gh-releases-zsync` update metadata into every built AppImage, enabling users to update to new releases by downloading only changed byte blocks.
- **Clean Runtime Sandbox Handling**: The custom `AppRun` handles Electron runtime requirements and unprivileged user namespace profiles on modern Linux systems (e.g. Ubuntu 24.04+).
- **Manual Trigger Support**: Easily trigger builds on-demand or specify custom versions via GitHub's `workflow_dispatch` interface.

---

## How to Install and Run

### 1. Download

Download the latest `Antigravity-*-x86_64.AppImage` from the [Releases](https://github.com/OWNER/REPOSITORY/releases/latest) page.

### 2. Make Executable and Run

```bash
chmod +x Antigravity-*-x86_64.AppImage
./Antigravity-*-x86_64.AppImage
```

---

## AppImage Delta Updates

This AppImage is built with embedded update configuration pointing directly to this repository's GitHub Releases:

```text
gh-releases-zsync|<owner>|<repo>|latest|Antigravity*-x86_64.AppImage.zsync
```

### Updating with `appimageupdatetool`

You can check for updates and update your AppImage in place without downloading the entire package:

```bash
# Update in-place
appimageupdatetool Antigravity-*-x86_64.AppImage
```

Or use graphical desktop managers such as **AppImageLauncher** or **AppImageUpdate GUI**, which detect the embedded update information automatically.

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
│   └── check-version.py          # Upstream version scraper and GitHub release comparator
├── .gitignore
└── README.md
```

---

## Local Development & Manual Builds

### 1. Check for the Latest Upstream Version

```bash
python3 scripts/check-version.py --check-only
```

Sample output:
```json
{
  "version": "2.12.2",
  "execution_id": "6298742303883264",
  "download_url": "https://storage.googleapis.com/antigravity-public/antigravity-hub/2.12.2-6298742303883264/linux-x64/Antigravity.tar.gz"
}
```

### 2. Build the AppImage Locally

You can run the build script locally on Linux:

```bash
./scripts/build-appimage.sh \
  --version "2.12.2" \
  --download-url "https://storage.googleapis.com/antigravity-public/antigravity-hub/2.12.2-6298742303883264/linux-x64/Antigravity.tar.gz" \
  --repo "your-username/antigravity-appimage" \
  --output-dir "./dist"
```

The output AppImage and `.zsync` files will be placed into `./dist/`:
- `dist/Antigravity-2.12.2-x86_64.AppImage`
- `dist/Antigravity-2.12.2-x86_64.AppImage.zsync`
- `dist/SHA256SUMS.txt`

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
