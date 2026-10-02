set shell := ["bash", "-euo", "pipefail", "-c"]

# list recipes
default:
    @just --list

# update sha512sums after editing a local source file
checksum app:
    docker run --rm -v "$PWD/{{app}}":/work -w /work alpine:edge sh -c "apk add -q abuild && abuild -F checksum"

# build with the throwaway key
build app:
    APP_NAME={{app}} TARGET_ARCH=x86_64 KEY_NAME=apk-test.rsa PRIVATE_KEY="$(cat ~/.cache/apk-test.rsa)" bash scripts/build.sh

# install-test what `just build` produced
test app:
    docker run --rm --network host -v "$PWD":/w -w /w alpine:edge sh -c "apk add -q jq && sh scripts/test-apk.sh {{app}}"

# list an APK's files
inspect apk:
    tar --warning=no-unknown-keyword -tzf {{apk}}

# same lint as CI
lint:
    docker run --rm -v "$PWD":/repo -w /repo koalaman/shellcheck:v0.11.0 --severity=warning scripts/*.sh
    docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:1.7.12
