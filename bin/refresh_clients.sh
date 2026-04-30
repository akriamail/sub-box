#!/bin/bash
# ==========================================
# sub-box v2.0 — 客户端版本刷新
# ==========================================

set -euo pipefail

WEB_DIR="${WEB_DIR:-/var/www/subscribe}"
CLIENTS_DIR="${CLIENTS_DIR:-$WEB_DIR/clients}"
CLIENTS_META="${CLIENTS_META:-$CLIENTS_DIR/clients.env}"

mkdir -p "$CLIENTS_DIR"

github_latest() {
    local repo="$1"
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest"
}

json_value() {
    local key="$1"
    python3 -c 'import json, sys; data=json.load(sys.stdin); print(data.get(sys.argv[1], ""))' "$key"
}

asset_url() {
    local pattern="$1"
    python3 -c '
import json, re, sys
data=json.load(sys.stdin)
pat=re.compile(sys.argv[1], re.I)
for asset in data.get("assets", []):
    name=asset.get("name", "")
    if pat.search(name):
        print(name)
        print(asset.get("browser_download_url", ""))
        break
' "$pattern"
}

download_asset() {
    local label="$1"
    local repo="$2"
    local pattern="$3"
    local prefix="$4"
    local latest tag asset name url ext target

    echo "[INFO] 检查 ${label}..."
    latest="$(github_latest "$repo")"
    tag="$(printf '%s' "$latest" | json_value tag_name)"
    asset="$(printf '%s' "$latest" | asset_url "$pattern")"
    name="$(printf '%s' "$asset" | sed -n '1p')"
    url="$(printf '%s' "$asset" | sed -n '2p')"

    if [[ -z "$tag" || -z "$url" || -z "$name" ]]; then
        echo "[WARN] 未找到 ${label} 匹配资源: ${pattern}"
        return 1
    fi

    ext="${name##*.}"
    target="$CLIENTS_DIR/${prefix}-${tag}.${ext}"

    if [[ ! -f "$target" ]]; then
        echo "[INFO] 下载 ${name}"
        curl -fL "$url" -o "$target"
    else
        echo "[OK] 已存在 ${target}"
    fi

    find "$CLIENTS_DIR" -maxdepth 1 -type f -name "${prefix}-*" ! -name "$(basename "$target")" -delete 2>/dev/null || true

    {
        echo "${prefix}_VERSION=${tag}"
        echo "${prefix}_FILE=$(basename "$target")"
        echo "${prefix}_SOURCE=${url}"
    } >> "$CLIENTS_META.tmp"
}

: > "$CLIENTS_META.tmp"
download_asset "Android v2rayNG" "2dust/v2rayNG" 'v2rayNG_.*(arm64-v8a|universal).*\.apk$|app-universal-release\.apk$|\.apk$' "V2RAYNG" || true
download_asset "Windows v2rayN" "2dust/v2rayN" 'windows.*64.*with.*core.*\.zip$|v2rayN.*with.*core.*\.zip$|\.zip$' "V2RAYN" || true
mv "$CLIENTS_META.tmp" "$CLIENTS_META"

echo "[OK] 客户端刷新完成: $CLIENTS_DIR"
