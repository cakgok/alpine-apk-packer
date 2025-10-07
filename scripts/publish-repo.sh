#!/bin/bash
set -eo pipefail

APPS=("bazarr" "stashapp" "tautulli" "jellyseerr")
REPO_DIR="${1:-gh-pages}"
ARCH_DIR="$REPO_DIR/main/x86_64"
FORCE_REINDEX="${FORCE_REINDEX:-false}"
NEEDS_REINDEX="false"
KEEP_VERSIONS=3

export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
export API="https://api.github.com"
export OWNER="$(cut -d/ -f1 <<<"$GITHUB_REPOSITORY")"
export REPO="$(cut -d/ -f2- <<<"$GITHUB_REPOSITORY")"
HDR=("-H" "Accept: application/vnd.github+json")
[[ -n $GH_TOKEN ]] && HDR+=("-H" "Authorization: Bearer $GH_TOKEN")

mkdir -p "$ARCH_DIR"

get_recent_releases() {
    local app=$1
    curl -sfL --retry 3 --retry-delay 2 "${HDR[@]}" "$API/repos/$OWNER/$REPO/releases" \
        | jq -r --arg app "$app" --arg keep "$KEEP_VERSIONS" '
            [.[] | select(.tag_name | startswith($app + "-") and (endswith("-latest") | not))]
            | sort_by(.created_at | fromdateiso8601) | reverse
            | .[0:($keep | tonumber)]
            | .[].tag_name'
}

get_release() {
    local tag=$1
    curl -sfL --retry 3 --retry-delay 2 "${HDR[@]}" "$API/repos/$OWNER/$REPO/releases/tags/$tag"
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

    mapfile -t RELEASES < <(get_recent_releases "$APP")

    if [[ ${#RELEASES[@]} -eq 0 ]]; then
        echo "⚠️  no releases found for $APP"
        continue
    fi

    echo "  Found ${#RELEASES[@]} recent releases"
    for VERSION_TAG in "${RELEASES[@]}"; do
         echo "  Processing $VERSION_TAG"
        
        rel_json=$(get_release "$VERSION_TAG" || true)
        [[ -z $rel_json ]] && continue

                APK_FOUND=false
        while IFS='|' read -r APK_NAME APK_URL; do
            [[ -z $APK_NAME || -z $APK_URL ]] && continue
            
            APK_FOUND=true
            if [[ -f "$ARCH_DIR/$APK_NAME" ]]; then
                echo "    ✅  $APK_NAME (cached)"
            else
                echo "    ⬇️  downloading $APK_NAME"
                curl -sfL --retry 3 --retry-delay 2 -o "$ARCH_DIR/$APK_NAME" "$APK_URL"
                NEEDS_REINDEX=true
            fi
        done < <(get_apk_asset "$rel_json")
        
        if [[ "$APK_FOUND" = "false" ]]; then
            echo "    ⚠️  no *.apk assets found in $VERSION_TAG"
        fi
    done
done

echo ""
echo "🧹 Cleaning up old versions (keeping last $KEEP_VERSIONS per app)..."
for APP in "${APPS[@]}"; do
    declare -a ALL_APKS_WITH_TIME=()
    for apk in "$ARCH_DIR"/${APP}-*.apk; do
        [[ -f "$apk" ]] || continue
        mtime=$(stat -c '%Y' "$apk" 2>/dev/null || stat -f '%m' "$apk" 2>/dev/null)
        ALL_APKS_WITH_TIME+=("$mtime $(basename "$apk")")
    done
    
    mapfile -t ALL_APKS < <(printf '%s\n' "${ALL_APKS_WITH_TIME[@]}" | sort -rn | cut -d' ' -f2)
    
    if [[ ${#ALL_APKS[@]} -gt $KEEP_VERSIONS ]]; then
        echo "  $APP: found ${#ALL_APKS[@]} packages, removing oldest"
        for (( i=$KEEP_VERSIONS; i<${#ALL_APKS[@]}; i++ )); do
            echo "    🗑️  ${ALL_APKS[$i]}"
            rm -f "$ARCH_DIR/${ALL_APKS[$i]}"
            NEEDS_REINDEX=true
        done
    else
        echo "  $APP: ${#ALL_APKS[@]} packages (within limit)"
    fi
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