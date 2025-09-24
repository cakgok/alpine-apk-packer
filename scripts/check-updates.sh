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
    curl -sfSL -H "Accept: application/vnd.github+json" \
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
echo "Latest upstream version is: $latest_tag"
echo "Checking if our release tag '$expected_tag' already exists..."

if gh release view "$expected_tag" >/dev/null 2>&1; then
  echo "✔ Release '$expected_tag' already exists. No update needed."
  echo "has_updates=false" >> "$GITHUB_OUTPUT"
else
  echo "→ New version found! Release '$expected_tag' is missing and needs to be built."
  echo "has_updates=true" >> "$GITHUB_OUTPUT"
  echo "new_version=${latest_tag}" >> "$GITHUB_OUTPUT"
fi