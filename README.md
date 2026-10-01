# alpine-apk-packer

[![Build All](https://github.com/cakgok/alpine-apk-packer/actions/workflows/build-all.yml/badge.svg)](https://github.com/cakgok/alpine-apk-packer/actions/workflows/build-all.yml)
[![Lint](https://github.com/cakgok/alpine-apk-packer/actions/workflows/lint.yml/badge.svg)](https://github.com/cakgok/alpine-apk-packer/actions/workflows/lint.yml)
[![Publish Repository](https://github.com/cakgok/alpine-apk-packer/actions/workflows/pages.yml/badge.svg)](https://github.com/cakgok/alpine-apk-packer/actions/workflows/pages.yml)

An automated Alpine package repository for self-hosted apps that aren't in
[aports](https://gitlab.alpinelinux.org/alpine/aports).
(Mostly due to dependency bundling reasons.)

📦 **Repository browser:** <https://cakgok.github.io/alpine-apk-packer/>

| Package | App | Upstream |
|---|---|---|
| `bazarr`, `bazarr-openrc` | Subtitle manager for Sonarr/Radarr | [morpheus65535/bazarr](https://github.com/morpheus65535/bazarr) |
| `seerr`, `seerr-openrc` | Media request manager for Plex/Jellyfin/Emby | [seerr-team/seerr](https://github.com/seerr-team/seerr) |
| `stash`, `stash-openrc`, `stash-python` | Media organizer | [stashapp/stash](https://github.com/stashapp/stash) |
| `tautulli`, `tautulli-openrc` | Plex monitoring | [Tautulli/Tautulli](https://github.com/Tautulli/Tautulli) |

Targets **Alpine `edge`, `x86_64`**. Packages with Python extensions are built against edge's
current Python and won't work on stable branches.

## Usage

```sh
# trust the signing key
wget -O /etc/apk/keys/cakgok@alpine-repo-68d45397.rsa.pub \
  https://cakgok.github.io/alpine-apk-packer/cakgok@alpine-repo-68d45397.rsa.pub

# add the repository
echo "https://cakgok.github.io/alpine-apk-packer/main" >> /etc/apk/repositories

# install and start a service
apk update
apk add bazarr bazarr-openrc
rc-update add bazarr
rc-service bazarr start
```

Each service runs as its own system user, keeps its data in `/var/lib/<app>`, and sends its
console output to syslog.

## Adding a package

1. Create `<app>/APKBUILD` and its OpenRC/install files. Run `abuild checksum`.
2. Add `{"app": "<app>", "upstream": "<owner>/<repo>"}` to `apps.json`.
3. Add the app to the `options:` list in `build-single.yml`.
4. Run **Build Single** for the app, or wait for the nightly run.

## notes to self

- builds trigger when <pkg>-<ver>-r<pkgrel>.apk is missing from the release: bump pkgrel to ship a fix
- update checksums after editing a local file (initd/confd..) or abuild will refuse to build
- publish skips the deploy if manifest.txt matches the release digests
- local test build: scripts/build.sh with a throwaway key

## Useful commands so I don't forget

### Update checksums after an edit

```sh
app=tautulli
docker run --rm -v "$PWD/$app":/work -w /work alpine:edge \
  sh -c "apk add -q abuild && abuild -F checksum"
```

### Building locally

```sh
openssl genrsa -out ~/.cache/apk-test.rsa 2048
APP_NAME=bazarr TARGET_ARCH=x86_64 KEY_NAME=apk-test.rsa \
  PRIVATE_KEY="$(cat ~/.cache/apk-test.rsa)" bash scripts/build.sh
ls bazarr/out/
```

### Take a Look Inside APK

```sh
tar -tzf bazarr/out/bazarr-1.6.2-r0.apk | head -20     # control files (.PKGINFO, .pre-install) come first
tar -xzOf bazarr/out/bazarr-1.6.2-r0.apk .PKGINFO      # depends, provides, size
```

### drive CI from the terminal
```sh
gh workflow run build-single.yml -f app_to_build=bazarr
gh run watch
gh run view <run-id> --log-failed
gh run download <run-id> -n bazarr-x86_64-apk -D /tmp/bazarr-apk   # grab the built APKs
```

### Check what's live
```sh
curl -s https://cakgok.github.io/alpine-apk-packer/structure.json | jq '.main.x86_64 | keys'
gh release view bazarr-latest
```

## To-Do

- [ ] Signing key is present in the builder.
A compromised package might steal it, altough it's useless by itself.
For more robust packaging, build in one CI job that has no access to the secret, and sign in a second job that runs no third-party code.
