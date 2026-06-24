#!/bin/bash
set -eo pipefail

if [[ -n ${APPS_OVERRIDE:-} ]]; then
  read -r -a APPS <<<"$APPS_OVERRIDE"
else
  APPS=("bazarr" "stashapp" "tautulli" "jellyseerr")
fi
REPO_DIR="${1:-gh-pages}"
ARCH_DIR="$REPO_DIR/main/x86_64"
FORCE_REINDEX="${FORCE_REINDEX:-false}"
NEEDS_REINDEX="false"

export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
export API="https://api.github.com"
export OWNER="$(cut -d/ -f1 <<<"$GITHUB_REPOSITORY")"
export REPO="$(cut -d/ -f2- <<<"$GITHUB_REPOSITORY")"
HDR=("-H" "Accept: application/vnd.github+json")
[[ -n $GH_TOKEN ]] && HDR+=("-H" "Authorization: Bearer $GH_TOKEN")

mkdir -p "$ARCH_DIR"

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
 
for APP in "${APPS[@]}"; do
    echo "--- $APP ---"
    TAG="${APP}-latest"
    
    rel_json=$(get_release "$TAG" || true)
    if [[ -z $rel_json ]]; then
        echo "⚠️  release $TAG not found"
        continue
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

        if [[ -f "$ARCH_DIR/$APK_NAME" ]]; then
            echo "✅  $APK_NAME (cached)"
        else
            NEEDS_REINDEX=true
            echo "⬇️  downloading $APK_NAME"
            curl -sfL --retry 3 --retry-delay 2 -o "$ARCH_DIR/$APK_NAME" "$APK_URL"
        fi

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
            echo "❌ release $TAG is missing main package $APK_ORIGIN"
            exit 1
        fi
    done

    # Clean once after every current asset is present. Cleaning inside the
    # download loop removes sibling subpackages such as bazarr-openrc.
    for old in "$ARCH_DIR"/*.apk; do
        [[ -e $old ]] || continue
        OLD_ORIGIN=$(get_apk_field "$old" origin)
        contains_item "$OLD_ORIGIN" "${CURRENT_ORIGINS[@]}" || continue
        contains_item "$(basename "$old")" "${CURRENT_APKS[@]}" && continue

        NEEDS_REINDEX=true
        echo "🗑️  removing $(basename "$old")"
        rm -f -- "$old"
    done
done

# Exit early if no changes detected and not forced
if [[ "$NEEDS_REINDEX" = "false" && "$FORCE_REINDEX" = "false" ]]; then
    echo "✅ Repository is up-to-date. No changes detected."
    echo "reindex=false" >> "$GITHUB_OUTPUT"
    exit 0
fi

echo "🔥 Changes detected or force reindex requested. Regenerating repository..."

mkdir -p ~/.abuild
echo "$PACKAGER_PRIVKEY" > ~/.abuild/"$KEY_NAME"
chmod 600 ~/.abuild/"$KEY_NAME"

# Derive public key and place it in the repo root
openssl rsa -in ~/.abuild/"$KEY_NAME" -pubout -out "$REPO_DIR/${KEY_NAME}.pub"
echo "Public key created at '$REPO_DIR/${KEY_NAME}.pub'."

mkdir -p /etc/apk/keys/
cp "$REPO_DIR/${KEY_NAME}.pub" /etc/apk/keys/

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
