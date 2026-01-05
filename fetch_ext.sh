#!/bin/bash

# --- 核心修改：从外部文件读取链接 ---
URL_FILE="/opt/subscribe/airport_url.txt"
EXT_FILE="/opt/subscribe/extend.ini"
KEYWORD="台湾" 
MAX_NODES=2

if [ ! -f "$URL_FILE" ]; then
    echo "--- 提示：未检测到 $URL_FILE，跳过抓取 ---"
    exit 0
fi
SUB_URL=$(cat "$URL_FILE" | tr -d '\n\r ')
# ----------------------------------

echo "--- 正在同步机场节点 (安全解码模式) ---"

# 1. 下载并解码 Base64
raw_content=$(curl -sL "$SUB_URL" | tr -d '\r' | base64 -d 2>/dev/null)

if [ -z "$raw_content" ]; then
    echo "❌ 抓取失败"
    exit 1
fi

# 2. 将 URL 编码还原为中文并筛选
selected_nodes=$(echo "$raw_content" | python3 -c "import sys, urllib.parse; [print(urllib.parse.unquote(line.strip())) for line in sys.stdin]" | grep "$KEYWORD" | head -n $MAX_NODES)

if [ -z "$selected_nodes" ]; then
    echo "⚠️ 匹配不到包含 [$KEYWORD] 的节点"
    exit 1
fi

# 3. 写入 extend.ini
echo "[nodes]" > "$EXT_FILE"

# 4. 追加节点并格式化
while read -r node; do
    [ -z "$node" ] && continue
    link="${node%%#*}"
    echo "${link}|机场-${KEYWORD}" >> "$EXT_FILE"
done <<< "$selected_nodes"

echo "✅ 成功抓取并更新至 $EXT_FILE"
