#!/bin/bash
set -euo pipefail

APP_NAME="$1"
VERSION="$2"

git config --global user.name "Auto-APK CI"
git config --global user.email "41898282+github-actions[bot]@users.noreply.github.com"

git add "${APP_NAME}/APKBUILD"

# Commit only if there are changes
if ! git diff --cached --quiet; then
    echo "APKBUILD updated. Committing changes..."
    git commit -m "${APP_NAME}: bump to v${VERSION}"

    # optimistic concurrency, if errors, just try again
    # the rebase will never fail since the only relevant APKBUILD is changed in every commit
    for attempt in 1 2 3 4 5; do
        if git pull --rebase origin main && git push origin HEAD:main; then
            break
        fi

        if [[ $attempt == 5 ]]; then echo "::error::push failed after 5 attempts"; exit 1; fi
        sleep $((attempt * 5))
    done
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
