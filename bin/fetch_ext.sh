#!/bin/bash
# ==========================================
# sub-box v2.0 — 机场节点抓取（按地区测速选最快）
# ==========================================

URL_FILE="/opt/subscribe/airport_url.txt"
EXT_FILE="/opt/subscribe/extend.ini"

# 地区配置: "关键词:最大节点数"（按 TCP 延迟升序，取最快的 N 个）
REGIONS=("台湾:1" "日本:1")

# ---- 下载 & 解码 ----
if [ ! -f "$URL_FILE" ]; then
    echo "--- 提示：未检测到 $URL_FILE，跳过抓取 ---"
    exit 0
fi
SUB_URL=$(cat "$URL_FILE" | tr -d '\n\r ')
if [ -z "$SUB_URL" ]; then
    echo "--- 提示：airport_url.txt 为空，跳过抓取 ---"
    exit 0
fi

echo "--- 正在同步机场节点 ($(date)) ---"

encoded_content=$(curl -fsSL --max-time 30 "$SUB_URL" 2>/tmp/sub_box_fetch_error)
if [ $? -ne 0 ]; then
    echo "❌ 下载订阅失败，请检查链接或网络"
    cat /tmp/sub_box_fetch_error 2>/dev/null
    rm -f /tmp/sub_box_fetch_error
    exit 1
fi
rm -f /tmp/sub_box_fetch_error

decode_tmp=$(mktemp)
raw_content=$(printf '%s' "$encoded_content" | tr -d '\r' | base64 -d 2>"$decode_tmp")
if [ $? -ne 0 ]; then
    echo "❌ 订阅内容不是有效 Base64，或供应商返回了非订阅页面"
    cat "$decode_tmp" 2>/dev/null; rm -f "$decode_tmp"
    exit 1
fi
rm -f "$decode_tmp"

if [ -z "$raw_content" ]; then
    echo "❌ 解码后内容为空"
    exit 1
fi

# ---- TCP 测速 ----
tcp_latency() {
    local start end
    start=$(date +%s%N)
    if timeout 3 bash -c "echo >/dev/tcp/$1/$2" 2>/dev/null; then
        end=$(date +%s%N)
        echo $(( (end - start) / 1000000 ))
    else
        echo ""
    fi
}

# ---- 主逻辑 ----
echo "[nodes]" > "$EXT_FILE"
node_tmp=$(mktemp)
total_selected=0

for region_config in "${REGIONS[@]}"; do
    keyword="${region_config%%:*}"
    max_nodes="${region_config##*:}"

    echo "--- 地区: $keyword (最多 $max_nodes 个) ---"

    # 解析该地区所有节点，去重 host:port（同 endpoint 只测一次）
    printf '%s' "$raw_content" | python3 -c "
import sys, urllib.parse, re
kw = sys.argv[1]
skip_kw = ['剩余流量', '下次重置', '套餐到期', '距离下次']
for line in sys.stdin:
    line = line.strip()
    if not line or '#' not in line:
        continue
    decoded = urllib.parse.unquote(line)
    # 跳过非节点的信息行
    if any(k in decoded for k in skip_kw):
        continue
    if kw not in decoded:
        continue
    link, remark = decoded.split('#', 1)
    m = re.search(r'@([^:]+):(\d+)', link)
    if m and m.group(1) != '127.0.0.1':
        print(f'{m.group(1)}\t{m.group(2)}\t{link}\t{remark}')
" "$keyword" | sort -t$'\t' -u -k1,2 > "$node_tmp"

    if [ ! -s "$node_tmp" ]; then
        echo "  ⚠️ 无匹配节点"
        continue
    fi

    # 逐个测速
    speed_tmp=$(mktemp)
    while IFS=$'\t' read -r host port link remark; do
        [ -z "$host" ] && continue
        lat=$(tcp_latency "$host" "$port")
        if [ -n "$lat" ]; then
            echo "${lat}"$'\t'"${host}:${port}"$'\t'"${link}"$'\t'"${remark}" >> "$speed_tmp"
            echo "  ${host}:${port}  ${lat}ms"
        else
            echo "  ${host}:${port}  TIMEOUT"
        fi
    done < "$node_tmp"

    if [ ! -s "$speed_tmp" ]; then
        echo "  ⚠️ 所有节点超时"
        rm -f "$speed_tmp"
        continue
    fi

    # 取最快的 N 个，每个 host:port 选一条代表链接写入
    sort -t$'\t' -k1 -n "$speed_tmp" | head -n "$max_nodes" | while IFS=$'\t' read -r lat hostport link remark; do
        echo "${link}|机场-${keyword}" >> "$EXT_FILE"
        echo "  ✅ 选中 ${hostport} (${lat}ms)"
    done

    # 计数（write 在 subshell 里，从文件统计）
    count=$(sort -t$'\t' -k1 -n "$speed_tmp" | head -n "$max_nodes" | wc -l | tr -d ' ')
    total_selected=$((total_selected + count))
    rm -f "$speed_tmp"
done

rm -f "$node_tmp"

if [ "$total_selected" -gt 0 ]; then
    echo "✅ 抓取完成，共 $total_selected 个节点，已写入 $EXT_FILE"
    exit 0
else
    echo "⚠️ 未选出任何可用节点，$EXT_FILE 未更新"
    exit 1
fi
