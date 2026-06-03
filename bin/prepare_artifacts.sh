#!/bin/bash
# Prepare server-hosted artifacts for agent one-line installs.

set -euo pipefail

SUB_BOX_DIR="${SUB_BOX_DIR:-/opt/subscribe}"
ARTIFACT_DIR="$SUB_BOX_DIR/artifacts"
SING_BOX_VERSION="${SING_BOX_VERSION:-1.13.12}"
ARCHES=("amd64" "arm64")

mkdir -p "$ARTIFACT_DIR"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

for arch in "${ARCHES[@]}"; do
    name="sing-box-${SING_BOX_VERSION}-linux-${arch}"
    url="https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/${name}.tar.gz"
    echo "[INFO] downloading $url"
    curl -fsSL "$url" -o "$tmp_dir/${name}.tar.gz"
    tar xzf "$tmp_dir/${name}.tar.gz" -C "$tmp_dir"
    install -m 755 "$tmp_dir/$name/sing-box" "$ARTIFACT_DIR/sing-box-linux-${arch}"
done

(
    cd "$ARTIFACT_DIR"
    sha256sum sing-box-linux-* > sha256sums.txt
)

echo "[OK] artifacts ready in $ARTIFACT_DIR"
