#!/bin/bash
set -euo pipefail

APP_NAME="$1"
VERSION="$2"

if [[ -z "$VERSION" ]]; then
  echo "Error: A version number must be provided as the first argument."
  exit 1
fi

git config --global user.name "Auto-APK CI"
git config --global user.email "41898282+github-actions[bot]@users.noreply.github.com"

git add "${APP_NAME}/APKBUILD"

# Commit only if there are changes
if ! git diff --cached --quiet; then
  echo "APKBUILD updated. Committing changes..."
  git commit -m "${APP_NAME}: bump to v${VERSION}"
  git pull --rebase --autostash origin main
  git push origin HEAD:main
else
  echo "APKBUILD already up-to-date."
fi

# Create and push the corresponding tag for the release
TAG_NAME="${APP_NAME}-v${VERSION}"
if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
  echo "Tag $TAG_NAME already exists."
else
  echo "Creating tag $TAG_NAME"
  git tag -a "$TAG_NAME" -m "Release ${APP_NAME} v${VERSION}"
  git push origin "$TAG_NAME"
fi
