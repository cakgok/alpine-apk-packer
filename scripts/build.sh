#!/usr/bin/env bash
set -euo pipefail

#Check for required variables
for var in APP_NAME TARGET_ARCH KEY_NAME PRIVATE_KEY; do
  [[ -z "${!var:-}" ]] && { echo "::error::$var is not set"; exit 1; }
done

ALPINE_VERSION="${ALPINE_VERSION:-edge}"
SRC_DIR="${PWD}/${APP_NAME}"
OUT_DIR="${SRC_DIR}/out"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "${OUT_DIR}"

echo "🔧 Building ${APP_NAME} for ${TARGET_ARCH}"
echo "🐧 Alpine version: ${ALPINE_VERSION}"
echo "📦 Output directory: ${OUT_DIR}"

docker run --rm \
  -v "${SRC_DIR}":/work \
  -v "${OUT_DIR}":/out \
  -v "${SCRIPT_DIR}/build-in-container.sh":/build-in-container.sh:ro \
  -e PRIVATE_KEY -e KEY_NAME -e TARGET_ARCH \
  "alpine:${ALPINE_VERSION}" sh /build-in-container.sh

  echo "✅ Build complete. Artifacts now in ${OUT_DIR}"
