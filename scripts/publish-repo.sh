#!/bin/bash
set -eo pipefail

## Helpers
wanted_manifest() {
    for app in "${APPS[@]}"; do
        if ! release=$(get_release "$app-latest"); then
            die "cannot read release $app-latest"
        fi

        version=$(get_release_version <<<"$release")
        if [[ -z $version ]]; then
            die "no version in $app-latest"
        fi

        apk_lines_for_version "$version" <<<"$release"
    done | sort
}

# Print "name size digest" for one file, in the same format GitHub's API uses.
manifest_line() {
    local file=$1
    local size hash
    size=$(stat -c %s "$file")
    hash=$(sha256sum "$file" | cut -d' ' -f1)
    echo "$(basename "$file") $size sha256:$hash"
}

# Print the manifest of every APK in a folder, sorted.
manifest_of_dir() {
    for file in "$1"/*.apk; do
        manifest_line "$file"
    done | sort
}

# Since we release as app-latest as a moving tag
get_release() {
  curl -sfL --retry 3 --retry-delay 2 "${HDR[@]}" \
       "$API/repos/$OWNER/$REPO/releases/tags/$1"
}

get_apk_assets() {
  jq -r '.assets[]
        | select(.name | endswith(".apk"))
        | "\(.name)|\(.browser_download_url)"'
}

get_release_version() {
  jq -r 'try ((.body // "")
        | capture("Current version: v(?<version>[^[:space:]]+)").version)
        // empty'
}

get_apk_field() {
  local apk_path="$1"
  local field="$2"

  tar -xOf "$apk_path" .PKGINFO 2>/dev/null |
    sed -n "s/^${field} = //p" |
    head -n 1
}

contains_item() {
  local expected="$1"
  shift

  local item
  for item in "$@"; do
    [[ $item == "$expected" ]] && return 0
  done
  return 1
}

die() {
    echo "::error::$*" >&2
    exit 1
}

# From one release's JSON (on stdin), print "name size digest" for each APK of version $1.
apk_lines_for_version() {
  jq -r --arg v "$1" '
    .assets[]
    | select(.name | endswith(".apk"))
    | select(.name | contains("-\($v)-r"))
    | "\(.name) \(.size) \(.digest)"
  '
}

# <(command) is process substitution
# << would be heredoc
# why not pipe? because it would be filled in subshell and the main APPS would stay empty
mapfile -t APPS < <(jq -r '.[].app' main/apps.json)

(( ${#APPS[@]} > 0 )) || { echo "::error::no apps read from main/apps.json"; exit 1; }

REPO_DIR="${1:-gh-pages}"
ARCH_DIR="$REPO_DIR/main/x86_64"

GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
API="https://api.github.com"
OWNER="${GITHUB_REPOSITORY%%/*}"
REPO="${GITHUB_REPOSITORY#*/}"

HDR=("-H" "Accept: application/vnd.github+json")
[[ -n $GH_TOKEN ]] && HDR+=("-H" "Authorization: Bearer $GH_TOKEN")

mkdir -p "$ARCH_DIR"

# check the current manifest, only update if they are changes
want=$(wanted_manifest)
live=$(curl -sfL "https://${OWNER,,}.github.io/${REPO}/manifest.txt" || true)

if [[ $want == "$live" && $FORCE_REINDEX == false ]]; then
    echo "✅ Repository is up-to-date. No changes detected."
    echo "reindex=false" >> "$GITHUB_OUTPUT"
    exit 0
fi

for APP in "${APPS[@]}"; do
    echo "--- $APP ---"
    TAG="${APP}-latest"

    rel_json=$(get_release "$TAG" || true)
    if [[ -z $rel_json ]]; then
        echo "⚠️  release $TAG not found"
        exit 1
    fi

    RELEASE_VERSION=$(get_release_version <<<"$rel_json")
    if [[ -z $RELEASE_VERSION ]]; then
        echo "❌ unable to determine current version from release $TAG"
        exit 1
    fi

    APK_FOUND=false
    CURRENT_APKS=()
    CURRENT_ORIGINS=()

    while IFS='|' read -r APK_NAME APK_URL; do
        [[ -z $APK_NAME || -z $APK_URL ]] && continue

        # Moving releases retain historical assets unless they are cleaned up.
        # Publish only APKs belonging to the version declared in the release body.
        case "$APK_NAME" in
          *-"$RELEASE_VERSION"-r*.apk) ;;
          *) continue ;;
        esac

        APK_FOUND=true
        CURRENT_APKS+=("$APK_NAME")

        echo "⬇️  downloading $APK_NAME"
        curl -sfL --retry 3 --retry-delay 2 -o "$ARCH_DIR/$APK_NAME" "$APK_URL"

        APK_ORIGIN=$(get_apk_field "$ARCH_DIR/$APK_NAME" origin)
        APK_VERSION=$(get_apk_field "$ARCH_DIR/$APK_NAME" pkgver)
        if [[ -z $APK_ORIGIN || ${APK_VERSION%-r*} != "$RELEASE_VERSION" ]]; then
            echo "❌ invalid package metadata in $APK_NAME"
            exit 1
        fi
        contains_item "$APK_ORIGIN" "${CURRENT_ORIGINS[@]}" ||
          CURRENT_ORIGINS+=("$APK_ORIGIN")

    done < <(get_apk_assets <<<"$rel_json")
    if [[ $APK_FOUND == false ]]; then
        echo "❌ no APK assets for version $RELEASE_VERSION in release $TAG"
        exit 1
    fi

    # Every subpackage uses the main package name as its origin. Requiring the
    # main APK prevents publishing an OpenRC-only repository again.
    for APK_ORIGIN in "${CURRENT_ORIGINS[@]}"; do
        MAIN_FOUND=false
        for APK_NAME in "${CURRENT_APKS[@]}"; do
            if [[ $(get_apk_field "$ARCH_DIR/$APK_NAME" pkgname) == "$APK_ORIGIN" ]]; then
                MAIN_FOUND=true
                break
            fi
        done
        if [[ $MAIN_FOUND == false ]]; then
            die "release $TAG is missing main package '$APK_ORIGIN'"
        fi
    done
done

echo "🔥 Changes detected or force reindex requested. Regenerating repository..."

mkdir -p ~/.abuild
echo "$PACKAGER_PRIVKEY" > ~/.abuild/"$KEY_NAME"
chmod 600 ~/.abuild/"$KEY_NAME"

# Derive public key and place it in the repo root
openssl rsa -in ~/.abuild/"$KEY_NAME" -pubout -out "$REPO_DIR/${KEY_NAME}.pub"
echo "Public key created at '$REPO_DIR/${KEY_NAME}.pub'."

mkdir -p /etc/apk/keys/
cp "$REPO_DIR/${KEY_NAME}.pub" /etc/apk/keys/

have=$(manifest_of_dir "$ARCH_DIR")

if [[ $have != "$want" ]]; then
    echo "::error::downloaded files don't match the releases"
    diff <(echo "$want") <(echo "$have") || true
    exit 1
fi

echo "$have" > "$REPO_DIR/manifest.txt"

# Generate and sign the index
cd "$ARCH_DIR"
apk index -o APKINDEX.tar.gz *.apk
abuild-sign -k ~/.abuild/"$KEY_NAME" APKINDEX.tar.gz
cd - > /dev/null

echo "Repository index has been regenerated and signed."

echo "📄 Generating repository browser..."
touch "$REPO_DIR/.nojekyll"

# Generate the structure JSON
python3 main/scripts/repo-browser/generate_structure.py "$REPO_DIR" > "$REPO_DIR/structure.json"

# Copy static HTML and JS from your repo
cp main/scripts/repo-browser/index.html "$REPO_DIR/"
cp main/scripts/repo-browser/browser.js "$REPO_DIR/"

# Substitute variables in index.html
sed -i "s|{{KEY_NAME}}|$KEY_NAME|g" "$REPO_DIR/index.html"
sed -i "s|{{OWNER}}|$OWNER|g" "$REPO_DIR/index.html"
sed -i "s|{{REPO}}|$REPO|g" "$REPO_DIR/index.html"

echo "✅ Process complete. Repository is ready for deployment in '$REPO_DIR'."
echo "reindex=true" >> "$GITHUB_OUTPUT"
