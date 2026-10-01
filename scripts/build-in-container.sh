#!/bin/sh
# Runs inside the Alpine build container (by build.sh).
# Expects:
# /work = the app folder,
# /out = output folder,
# env PRIVATE_KEY, KEY_NAME, TARGET_ARCH.

# no pipes here, so no pipefail
# No -x: the key handling below would be printed
set -eu

orig=$(stat -c %u:%g /work)
trap 'chown -R "$orig" /work /out' EXIT # give files back to whoever owned them
apk add --no-cache abuild

# as root: create the build user
adduser -D builder
addgroup builder abuild

# as root: install the signing key for builder
keydir=/home/builder/.abuild
mkdir -p "$keydir"
printf "%s\n" "$PRIVATE_KEY" > "$keydir/$KEY_NAME"

chmod 600 "$keydir/$KEY_NAME"
openssl rsa -in "$keydir/$KEY_NAME" -pubout -out "$keydir/$KEY_NAME.pub"

cp "$keydir/$KEY_NAME.pub" /etc/apk/keys/
echo "PACKAGER_PRIVKEY=$keydir/$KEY_NAME" > "$keydir/abuild.conf"

chown -R builder:builder "$keydir"
chown -R builder:abuild /work

# as builder: the only part that runs package code
set -x
su builder -c "cd /work && CARCH=$TARGET_ARCH abuild -r -P /home/builder/packages"

# as root again: collect the results
# Copy the built packages to the output directory
find /home/builder/packages -name '*.apk' -type f -exec cp {} /out/ \;

# List what we copied
ls /out/*.apk >/dev/null 2>&1 || { echo '::error::abuild produced no .apk files'; exit 1; }
