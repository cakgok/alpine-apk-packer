#!/bin/bash
set -eo pipefail

APPS=("bazarr" "stashapp" "tautulli")
EXISTING_REPO_DIR="gh-pages"
REPO_DIR="gh-pages"
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
    ' <<<"$1" | head -n1
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

  IFS='|' read -r APK_NAME APK_URL <<<"$(get_apk_asset "$rel_json")"
  if [[ -z $APK_NAME ]]; then
    echo "⚠️  no *.apk asset"
    continue
  fi

  if [[ -f "$ARCH_DIR/$APK_NAME" ]]; then
    echo "✅  up-to-date"
  else
    echo "⬇️  downloading $APK_NAME"
    curl -sfL -o "$ARCH_DIR/$APK_NAME" "$APK_URL"
    NEEDS_REINDEX=true
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

    # Generate and sign the index
    cd "$ARCH_DIR"
    apk index -o APKINDEX.tar.gz *.apk    
    abuild-sign -k ~/.abuild/"$KEY_NAME" APKINDEX.tar.gz
    cd - > /dev/null

    echo "Repository index has been regenerated and signed."
fi

echo "Generating index.html..."
cat > "$REPO_DIR/index.html" <<- EOM
<!DOCTYPE html>
<html>
<head>
    <title>Alpine Repository</title>
    <style>body { font-family: sans-serif; padding: 2em; } code { background: #eee; padding: 3px; }</style>
</head>
<body>
    <h1>Alpine Package Repository</h1>
    <p>To use this repository, add the public key and then add the repository URL to your system.</p>
    <pre><code># Download and install the public key
wget -O /etc/apk/keys/${KEY_NAME}.pub ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/releases/download/keys/${KEY_NAME}.pub

# Add the repository
echo "${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}" >> /etc/apk/repositories

# Update the index
apk update</code></pre>
    <h2>Available Packages</h2>
    <ul>
$(cd "$ARCH_DIR" && ls -1 *.apk | sed 's/^/<li>/g' | sed 's/$/<\/li>/g')
    </ul>
</body>
</html>
EOM

echo "✅ Process complete. Repository is ready for deployment in '$REPO_DIR'."