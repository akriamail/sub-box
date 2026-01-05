#!/bin/bash

CONFIG_DIR="/opt/subscribe"
WEB_DIR="/var/www/subscribe"
TOKEN_FILE=$(ls -1 $WEB_DIR | grep -v "index.html" | head -n 1)

process_nodes() {
    echo "--- 正在深度处理节点 ($(date)) ---"
    
    combined_content=""
    for ini_file in "$CONFIG_DIR"/*.ini; do
        if [ -f "$ini_file" ]; then
# 修改前：
# content=$(sed -n '/\[nodes\]/,$p' "$ini_file" | grep -E "^(vmess|vless|trojan|ss|ssr)://")

# 修改后（增加了 hysteria2 和 hy2 的支持）：
content=$(sed -n '/\[nodes\]/,$p' "$ini_file" | grep -E "^(vmess|vless|trojan|ss|ssr|hysteria2|hy2)://")           

            combined_content+="$content"$'\n'
        fi
    done

    processed_nodes=""
    while read -r line; do
        [ -z "$line" ] && continue
        
        # 拆分链接和备注
        if [[ "$line" == *"|"* ]]; then
            link_part="${line%%|*}"
            new_name="${line#*|}"
        else
            link_part="$line"
            new_name=""
        fi

        if [[ "$link_part" == vmess://* ]]; then
            # 1. 提取 Base64 部分并清理换行/空格
            raw_b64="${link_part#vmess://}"
            # 2. 解码并强制压缩成一行，去除 JSON 内部换行
            json_data=$(echo "$raw_b64" | tr -d '\n\r ' | base64 -d 2>/dev/null | tr -d '\n\r')
            
            if [[ -n "$json_data" && -n "$new_name" ]]; then
                # 3. 兼容性更强的正则：匹配 ps 字段，不管前后有没有空格
                new_json=$(echo "$json_data" | sed "s/\"ps\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"ps\":\"$new_name\"/g")
                # 4. 重新 Base64 编码，确保没有换行符 (-w 0)
                new_link="vmess://$(echo -n "$new_json" | base64 -w 0)"
                processed_nodes+="$new_link"$'\n'
            else
                processed_nodes+="$link_part"$'\n'
            fi
        else
            # Trojan/VLESS 处理
            if [[ -n "$new_name" ]]; then
                clean_link="${link_part%%#*}"
                processed_nodes+="${clean_link}#${new_name}"$'\n'
            else
                processed_nodes+="$link_part"$'\n'
            fi
        fi
    done <<< "$combined_content"


# --- 请更新 update.sh 的最后写入逻辑 ---
    
    # 核心：在 Base64 编码前，确保节点之间是用换行符连接，但最后一个节点后不留空行
    # 使用 tr 删除可能产生的多余空行，确保客户端能解析全部节点
    echo -e -n "$processed_nodes" | sed '/^$/d' | base64 -w 0 > "${WEB_DIR}/${TOKEN_FILE}"
    
    echo "✅ 聚合成功！当前节点总数: $(echo "$processed_nodes" | grep -c "://")"
}

process_nodes

inotifywait -m -e modify,create,delete,move "$CONFIG_DIR" | while read path action file; do
    if [[ "$file" == *.ini ]]; then
        process_nodes
    fi
done
