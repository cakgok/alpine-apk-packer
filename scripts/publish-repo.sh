#!/bin/bash
set -eo pipefail

APPS=("bazarr" "stashapp" "tautulli" "jellyseerr")
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
 
for APP in "${APPS[@]}"; do
    echo "--- $APP ---"
    TAG="${APP}-latest"
    
    rel_json=$(get_release "$TAG" || true)
    if [[ -z $rel_json ]]; then
        echo "⚠️  release $TAG not found"
        continue
    fi

    APK_FOUND=false

    while IFS='|' read -r APK_NAME APK_URL; do
        [[ -z $APK_NAME || -z $APK_URL ]] && continue

        APK_FOUND=true

        if [[ -f "$ARCH_DIR/$APK_NAME" ]]; then
            echo "✅  $APK_NAME (cached)"
            continue
        fi

        NEEDS_REINDEX=true        
        echo "⬇️  downloading $APK_NAME"
        curl -sfL --retry 3 --retry-delay 2 -o "$ARCH_DIR/$APK_NAME" "$APK_URL"
    
        # Clean up old APKs, only a single one should exist but just in case
        for old in "$ARCH_DIR"/${APP}-*.apk; do
            [[ $old == "$ARCH_DIR/$APK_NAME" ]] && continue
            echo "🗑️  removing $(basename "$old")"
            rm -f -- "$old"
        done

    done < <(get_apk_assets <<<"$rel_json")
  [[ $APK_FOUND == false ]] && echo "⚠️  no .apk assets in release $TAG"
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