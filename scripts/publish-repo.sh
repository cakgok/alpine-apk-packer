#!/bin/bash
set -eo pipefail

APPS=("bazarr" "stashapp" "tautulli")
EXISTING_REPO_DIR="gh-pages"
REPO_DIR="${1:-gh-pages}"
ARCH_DIR="$REPO_DIR/main/x86_64"

export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
export API="https://api.github.com"
export OWNER="$(cut -d/ -f1 <<<"$GITHUB_REPOSITORY")"
export REPO="$(cut -d/ -f2- <<<"$GITHUB_REPOSITORY")"
HDR=("-H" "Accept: application/vnd.github+json")
[[ -n $GH_TOKEN ]] && HDR+=("-H" "Authorization: Bearer $GH_TOKEN")

mkdir -p "$ARCH_DIR"
NEEDS_REINDEX=false

get_release() {
    local tag=$1
    curl -sfL "${HDR[@]}" "$API/repos/$OWNER/$REPO/releases/tags/$tag"
}

get_apk_asset() {
jq -r '
    .assets[]
    | select(.name | endswith(".apk"))
    | "\(.name)|\(.browser_download_url)"
    ' <<<"$1"
}

for APP in "${APPS[@]}"; do
    echo "--- $APP ---"
    LATEST="${APP}-latest"

    rel_json=$(get_release "$LATEST" || true)
    if [[ -z $rel_json ]]; then
        echo "⚠️  no release $LATEST"
        continue
    fi

    VERSION_TAG=$(jq -r '.tag_name' <<<"$rel_json")
    echo "  ↳ resolved to $VERSION_TAG"

    while IFS='|' read -r APK_NAME APK_URL; do
        [[ -z $APK_NAME || -z $APK_URL ]] && continue
        
        APK_FOUND=true
        if [[ -f "$ARCH_DIR/$APK_NAME" ]]; then
            echo "  ✅  $APK_NAME up-to-date"
        else
            echo "  ⬇️  downloading $APK_NAME"
            curl -sfL -o "$ARCH_DIR/$APK_NAME" "$APK_URL"
            NEEDS_REINDEX=true
        fi
    done < <(get_apk_asset "$rel_json")

    if [[ "$APK_FOUND" = "false" ]]; then
        echo "⚠️  no *.apk assets found"
    fi
done

# Regenerate index if needed
if [ "$NEEDS_REINDEX" = "false" ]; then
    echo "✅ No new packages were added. Repository is up-to-date. No re-indexing needed."
else
    echo "🔥 New packages added. Regenerating and signing the repository index..."
    
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
fi

echo "Generating repository browser..."
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