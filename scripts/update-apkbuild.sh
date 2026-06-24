#!/bin/bash
set -e

APP_NAME="$1"
NEW_VERSION="$2"
ALPINE_VERSION="${ALPINE_VERSION:-edge}"

if [[ -z "$NEW_VERSION" ]]; then
  echo "Error: A new version number must be provided as the first argument."
  exit 1
fi

apkbuild_path="${APP_NAME}/APKBUILD"
echo "Updating $apkbuild_path to version $NEW_VERSION"

CURRENT_VERSION=$(sed -n 's/^pkgver=//p' "$apkbuild_path")

sed -Ei -e "s/^pkgver=.*/pkgver=${NEW_VERSION}/" "$apkbuild_path"
if [[ "$CURRENT_VERSION" != "$NEW_VERSION" ]]; then
  sed -Ei -e "s/^pkgrel=.*/pkgrel=0/" "$apkbuild_path"
else
  echo "Package version is unchanged; preserving pkgrel."
fi

docker run --rm \
  -v "$PWD/${APP_NAME}":/work -w /work \
  "alpine:${ALPINE_VERSION}" sh -euo pipefail -c '
    apk add --no-cache alpine-sdk
    adduser -D builder
    addgroup builder abuild
    chown -R builder:abuild /work
    su -l builder -c "cd /work && abuild checksum"
  '

echo "APKBUILD for $APP_NAME updated successfully."
