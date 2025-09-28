#!/bin/bash
set -eo pipefail

APPS=("bazarr" "stashapp" "tautulli")
EXISTING_REPO_DIR="gh-pages"
REPO_DIR="gh-pages"
ARCH_DIR="$REPO_DIR/main/x86_64"

mkdir -p "$ARCH_DIR"
NEEDS_REINDEX=false

for APP in "${APPS[@]}"; do
    echo "--- Processing app: $APP ---"
    LATEST_TAG="${APP}-latest"
    VERSION_TAG=$(gh release view "$LATEST_TAG" --json tagName --jq '.tagName')
    if [ -z "$VERSION_TAG" ]; then
        echo "⚠️ Could not find release for tag '$LATEST_TAG'. Skipping."
        continue
    fi

    echo "Resolved '$LATEST_TAG' to '$VERSION_TAG'"

    APK_ASSET_NAME=$(gh release view "$VERSION_TAG" --json 'assets.[].name' --jq '.assets[] | select(endswith(".apk"))')
    if [ -z "$APK_ASSET_NAME" ]; then
        echo "⚠️ Could not find .apk asset in release '$VERSION_TAG'. Skipping."
        continue
    fi

    if [ -f "$ARCH_DIR/$APK_ASSET_NAME" ]; then
        echo "✅ '$APK_ASSET_NAME' is already up-to-date in the repository. Skipping download."
    else
        echo "🔄 New version detected: '$APK_ASSET_NAME'. Downloading..."
        gh release download "$VERSION_TAG" --pattern "*.apk" --output "$ARCH_DIR/$APK_ASSET_NAME"
        echo "Download complete."
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