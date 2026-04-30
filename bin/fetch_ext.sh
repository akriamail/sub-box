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
if [ -z "$SUB_URL" ]; then
    echo "--- 提示：airport_url.txt 为空，跳过抓取 ---"
    exit 0
fi
# ----------------------------------

echo "--- 正在同步机场节点 (安全解码模式) ---"

# 1. 下载订阅内容
encoded_content=$(curl -fsSL --max-time 30 "$SUB_URL" 2>/tmp/sub_box_fetch_error)
curl_rc=$?
if [ $curl_rc -ne 0 ]; then
    echo "❌ 下载订阅失败，请检查链接或网络"
    cat /tmp/sub_box_fetch_error 2>/dev/null
    rm -f /tmp/sub_box_fetch_error
    exit 1
fi
rm -f /tmp/sub_box_fetch_error

# 2. 解码 Base64
decode_error=$(mktemp)
raw_content=$(printf '%s' "$encoded_content" | tr -d '\r' | base64 -d 2>"$decode_error")
decode_rc=$?
if [ $decode_rc -ne 0 ]; then
    echo "❌ 订阅内容不是有效 Base64，或供应商返回了非订阅页面"
    cat "$decode_error" 2>/dev/null
    rm -f "$decode_error"
    exit 1
fi
rm -f "$decode_error"

if [ -z "$raw_content" ]; then
    echo "❌ 解码后内容为空"
    exit 1
fi

# 3. 将 URL 编码还原为中文并筛选
selected_nodes=$(echo "$raw_content" | python3 -c "import sys, urllib.parse; [print(urllib.parse.unquote(line.strip())) for line in sys.stdin]" | grep "$KEYWORD" | head -n $MAX_NODES)

if [ -z "$selected_nodes" ]; then
    echo "⚠️ 匹配不到包含 [$KEYWORD] 的节点"
    exit 1
fi

# 4. 写入 extend.ini
echo "[nodes]" > "$EXT_FILE"

# 5. 追加节点并格式化
while read -r node; do
    [ -z "$node" ] && continue
    link="${node%%#*}"
    echo "${link}|机场-${KEYWORD}" >> "$EXT_FILE"
done <<< "$selected_nodes"

echo "✅ 成功抓取并更新至 $EXT_FILE"
