#!/bin/bash
set -e

APP_NAME="$1"
NEW_VERSION="$2"

if [[ -z "$NEW_VERSION" ]]; then
  echo "Error: A new version number must be provided as the first argument."
  exit 1
fi

apkbuild_path="${APP_NAME}/APKBUILD"
echo "Updating $apkbuild_path to version $NEW_VERSION"

sed -Ei \
  -e "s/^pkgver=.*/pkgver=${NEW_VERSION}/" \
  -e "s/^pkgrel=.*/pkgrel=0/" \
  "$apkbuild_path"

docker run --rm \
  -v "$PWD/${APP_NAME}":/work -w /work \
  alpine:edge sh -euo pipefail -c '
    apk add --no-cache alpine-sdk
    adduser -D builder
    addgroup builder abuild
    chown -R builder:abuild /work
    su -l builder -c "cd /work && abuild checksum"
  '

echo "APKBUILD for $APP_NAME updated successfully."
