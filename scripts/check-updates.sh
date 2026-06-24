#!/usr/bin/env bash

set -euo pipefail

APP_NAME="${APP}"
UPSTREAM_REPO="${UPSTREAM}"

auth_header=()
if [[ -n "${GH_PAT:-}" ]]; then
  auth_header=(-H "Authorization: Bearer ${GH_PAT}")
fi

apkbuild_path="${APP_NAME}/APKBUILD"

echo "Fetching latest release from upstream: $UPSTREAM_REPO"

latest_tag=$(
  curl  --fail --show-error --location \
        --retry 5 --retry-delay 2 --retry-all-errors \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: single-app-update-checker" \
        "${auth_header[@]}" \
        "https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest" \
  | jq -r '.tag_name // empty' | sed 's/^v//'
)


if [[ -z "$latest_tag" ]]; then
    echo "Could not fetch a valid release tag from $UPSTREAM_REPO. Assuming no update."
    echo "has_updates=false" >> "$GITHUB_OUTPUT"
    exit 0
fi

expected_tag="${APP_NAME}-v${latest_tag}"
package_name=$(sed -n 's/^pkgname=//p' "$apkbuild_path")
package_version=$(sed -n 's/^pkgver=//p' "$apkbuild_path")
package_revision=$(sed -n 's/^pkgrel=//p' "$apkbuild_path")

if [[ "$package_version" == "$latest_tag" ]]; then
  expected_asset="${package_name}-${latest_tag}-r${package_revision}.apk"
else
  expected_asset="${package_name}-${latest_tag}-r0.apk"
fi

echo "Latest upstream version is: $latest_tag"
echo "Checking for package asset '$expected_asset' in release '$expected_tag'..."

if gh release view "$expected_tag" --json assets --jq '.assets[].name' 2>/dev/null |
    grep -Fxq "$expected_asset"; then
  echo "✔ Package asset '$expected_asset' already exists. No update needed."
  echo "has_updates=false" >> "$GITHUB_OUTPUT"
else
  echo "→ Package asset '$expected_asset' is missing and needs to be built."
  echo "has_updates=true" >> "$GITHUB_OUTPUT"
  echo "new_version=${latest_tag}" >> "$GITHUB_OUTPUT"
fi
