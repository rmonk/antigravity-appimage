#!/usr/bin/env python3
"""
Checks for the latest version of Google Antigravity 2 (x64) for Linux
from https://antigravity.google/releases/ (with fallback to /download).
Determines whether an update is available compared to existing GitHub releases.
"""

import argparse
import gzip
import json
import os
import re
import sys
import urllib.error
import urllib.request
from html.parser import HTMLParser

RELEASES_URL = "https://antigravity.google/releases/"
DOWNLOAD_URL = "https://antigravity.google/download"
GCS_HUB_BASE = "https://storage.googleapis.com/antigravity-public/antigravity-hub"


class VersionTargetParser(HTMLParser):
    """HTML parser to extract data attributes from #versions-target."""

    def __init__(self):
        super().__init__()
        self.static_versions = None
        self.fallback_antigravity = None

    def handle_starttag(self, tag, attrs):
        attr_dict = dict(attrs)
        if attr_dict.get("id") == "versions-target":
            self.static_versions = attr_dict.get("data-static-versions")
            self.fallback_antigravity = attr_dict.get("data-fallback-antigravity")


def fetch_url(url: str) -> str:
    """Fetch URL with User-Agent header, handling gzip compression."""
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
        ),
        "Accept-Encoding": "gzip, deflate",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    }
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read()
        if raw[:2] == b"\x1f\x8b":
            return gzip.decompress(raw).decode("utf-8", errors="replace")
        return raw.decode("utf-8", errors="replace")


def parse_semver_key(v: str):
    """Parse version string into a tuple of integers for sorting."""
    # Strip any leading 'v'
    if v.startswith("v"):
        v = v[1:]
    parts = re.split(r"[.-]", v)
    nums = []
    for p in parts:
        if p.isdigit():
            nums.append(int(p))
        else:
            break
    return tuple(nums)


def find_versions_from_html(html: str):
    """Extract Antigravity 2.x versions and build/execution IDs from HTML content."""
    candidates = {}

    # Method 1: Parse #versions-target JSON attributes
    parser = VersionTargetParser()
    try:
        parser.feed(html)
        for raw_json in [parser.fallback_antigravity, parser.static_versions]:
            if raw_json:
                try:
                    entries = json.loads(raw_json)
                    for item in entries:
                        v = item.get("version", "").strip()
                        eid = str(item.get("execution_id", "")).strip()
                        key = parse_semver_key(v)
                        # Antigravity 2.x only (major version >= 2)
                        if key and key[0] >= 2 and eid:
                            candidates[v] = eid
                except Exception:
                    pass
    except Exception:
        pass

    # Method 2: Regex extraction for direct hub GCS links
    pattern = r"storage\.googleapis\.com/antigravity-public/antigravity-hub/([0-9.]+)-([0-9]+)/linux-x64/Antigravity\.tar\.gz"
    for match in re.finditer(pattern, html):
        v = match.group(1).strip()
        eid = match.group(2).strip()
        key = parse_semver_key(v)
        if key and key[0] >= 2 and eid:
            candidates[v] = eid

    return candidates


def get_latest_upstream_release():
    """Find the latest Antigravity 2 (x64) release from official sources."""
    # Attempt 1: https://antigravity.google/releases/
    try:
        html = fetch_url(RELEASES_URL)
        candidates = find_versions_from_html(html)
    except Exception as e:
        print(f"Warning: Failed to fetch {RELEASES_URL}: {e}", file=sys.stderr)
        candidates = {}

    # Attempt 2: Fallback to https://antigravity.google/download if needed
    if not candidates:
        try:
            html = fetch_url(DOWNLOAD_URL)
            candidates = find_versions_from_html(html)
        except Exception as e:
            print(f"Warning: Failed to fetch {DOWNLOAD_URL}: {e}", file=sys.stderr)

    if not candidates:
        raise RuntimeError("Unable to discover any Antigravity 2.x releases from upstream sources.")

    sorted_versions = sorted(candidates.keys(), key=parse_semver_key, reverse=True)
    latest_v = sorted_versions[0]
    execution_id = candidates[latest_v]
    download_url = f"{GCS_HUB_BASE}/{latest_v}-{execution_id}/linux-x64/Antigravity.tar.gz"

    return {
        "version": latest_v,
        "execution_id": execution_id,
        "download_url": download_url,
    }


def check_github_release_exists(repo: str, tag: str, token: str = None) -> bool:
    """Check whether a release with the given tag already exists on GitHub."""
    api_url = f"https://api.github.com/repos/{repo}/releases/tags/{tag}"
    headers = {
        "User-Agent": "Antigravity-AppImage-Updater",
        "Accept": "application/vnd.github+json",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"

    req = urllib.request.Request(api_url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            if resp.status == 200:
                return True
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return False
        # If rate-limited or other API error, report warning
        print(f"Warning: GitHub API returned HTTP {e.code}: {e.reason}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"Warning: Failed to check GitHub release existence: {e}", file=sys.stderr)
        return False

    return False


def set_github_output(key: str, value: str):
    """Write an output parameter to $GITHUB_OUTPUT if running in GitHub Actions."""
    gh_output = os.environ.get("GITHUB_OUTPUT")
    if gh_output:
        with open(gh_output, "a", encoding="utf-8") as f:
            f.write(f"{key}={value}\n")


def main():
    parser = argparse.ArgumentParser(description="Check latest Google Antigravity 2 release.")
    parser.add_argument("--check-only", action="store_true", help="Print latest version details and exit.")
    parser.add_argument("--repo", type=str, default=os.environ.get("GITHUB_REPOSITORY"), help="GitHub repository (e.g. owner/repo).")
    parser.add_argument("--token", type=str, default=os.environ.get("GITHUB_TOKEN"), help="GitHub token for API authentication.")
    parser.add_argument("--force", action="store_true", help="Force update_available=true.")
    parser.add_argument("--override-version", type=str, default=None, help="Manually override the detected version.")
    parser.add_argument("--override-execution-id", type=str, default=None, help="Manually override the execution ID.")
    parser.add_argument("--override-download-url", type=str, default=None, help="Manually override download URL.")

    args = parser.parse_args()

    if args.override_version:
        version = args.override_version
        eid = args.override_execution_id or "0"
        dl_url = args.override_download_url or f"{GCS_HUB_BASE}/{version}-{eid}/linux-x64/Antigravity.tar.gz"
        release_info = {
            "version": version,
            "execution_id": eid,
            "download_url": dl_url,
        }
    else:
        release_info = get_latest_upstream_release()

    version = release_info["version"]
    execution_id = release_info["execution_id"]
    download_url = release_info["download_url"]
    tag = f"v{version}"

    if args.check_only:
        print(json.dumps(release_info, indent=2))
        return 0

    print(f"Latest Antigravity 2.x release detected: {version} (build: {execution_id})")
    print(f"Download URL: {download_url}")

    update_available = False
    if args.force:
        print("Force mode enabled: update_available=true")
        update_available = True
    elif args.repo:
        exists = check_github_release_exists(args.repo, tag, args.token)
        if exists:
            print(f"Release {tag} already exists in GitHub repository {args.repo}. No update needed.")
            update_available = False
        else:
            print(f"Release {tag} does NOT exist in GitHub repository {args.repo}. Update required!")
            update_available = True
    else:
        print("No GitHub repository specified to compare against. Defaulting update_available=true.")
        update_available = True

    # Output parameters for GitHub Actions
    set_github_output("version", version)
    set_github_output("execution_id", execution_id)
    set_github_output("download_url", download_url)
    set_github_output("tag", tag)
    set_github_output("update_available", "true" if update_available else "false")

    return 0


if __name__ == "__main__":
    sys.exit(main())
