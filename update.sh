#!/bin/bash

# 配置路径
CONFIG_DIR="/opt/subscribe"
WEB_DIR="/var/www/subscribe"
TOKEN_FILE=$(ls $WEB_DIR | head -n 1)

# 核心处理函数
process_nodes() {
    echo "检测到配置变更，正在重新聚合节点..."
    
    # 1. 聚合目录下所有 .ini 文件的 [nodes] 部分
    combined_content=""
    for ini_file in ${CONFIG_DIR}/*.ini; do
        if [ -f "$ini_file" ]; then
            # 提取 [nodes] 之后的内容，过滤掉协议头以外的杂质
            content=$(sed -n '/\[nodes\]/,$p' "$ini_file" | grep -E "^(vmess|vless|trojan|ss|ssr)://" | grep -v "^$")
            combined_content+="$content"$'\n'
        fi
    done

    # 2. 处理聚合后的节点（重命名逻辑）
    processed_nodes=""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        
        if [[ $line == vmess://* ]]; then
            # VMess 深度重写逻辑
            raw_base64=$(echo "$line" | sed 's/vmess:\/\///')
            json_data=$(echo "$raw_base64" | base64 -d 2>/dev/null)
            
            if [ -n "$json_data" ]; then
                link_part=$(echo "$line" | cut -d'|' -f1)
                new_name=$(echo "$line" | cut -d'|' -f2)
                
                if [[ "$line" == *"|"* ]]; then
                    new_json=$(echo "$json_data" | jq -r ".ps=\"$new_name\"" 2>/dev/null || echo "$json_data" | sed "s/\"ps\":\"[^\"]*\"/\"ps\":\"$new_name\"/")
                    new_link="vmess://$(echo -n "$new_json" | base64 -w 0)"
                    processed_nodes+="$new_link"$'\n'
                else
                    processed_nodes+="$link_part"$'\n'
                fi
            fi
        else
            # 其他协议（Trojan/VLESS 等）简单重写
            if [[ "$line" == *"|"* ]]; then
                link_part=$(echo "$line" | cut -d'|' -f1)
                new_name=$(echo "$line" | cut -d'|' -f2)
                clean_link=$(echo "$link_part" | cut -d'#' -f1)
                processed_nodes+="${clean_link}#${new_name}"$'\n'
            else
                processed_nodes+="$line"$'\n'
            fi
        fi
    done <<< "$combined_content"

    # 3. 最终 Base64 编码并写入订阅文件
    echo -n "$processed_nodes" | base64 -w 0 > "${WEB_DIR}/${TOKEN_FILE}"
    echo "✅ 聚合完成，订阅已更新。"
}

# 初始执行一次
process_nodes

# 使用 inotifywait 监控整个目录的增删改
echo "开始监控目录: ${CONFIG_DIR} ..."
while true; do
    inotifywait -e modify -e create -e delete -e move "$CONFIG_DIR"
    process_nodes
done
