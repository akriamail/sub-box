#!/bin/bash

# ==========================================
# X-UI Sub-Box 聚合引擎 v1.0.4
# 兼容性：全协议支持 + 多文件聚合 + JSON 宽容模式
# ==========================================

CONFIG_DIR="/opt/subscribe"
WEB_DIR="/var/www/subscribe"

# 自动定位 Token 文件（忽略 index.html）
TOKEN_FILE=$(ls -1 $WEB_DIR | grep -v "index.html" | head -n 1)

process_nodes() {
    echo "--- 节点聚合任务开始 ($(date)) ---"
    
    combined_content=""
    # 1. 扫描目录下所有 .ini 文件并合并 [nodes] 之后的内容
    for ini_file in "$CONFIG_DIR"/*.ini; do
        if [ -f "$ini_file" ]; then
            echo "正在读取: $ini_file"
            # 提取协议开头的行，并确保文件间有换行间隔
            content=$(sed -n '/\[nodes\]/,$p' "$ini_file" | grep -E "^(vmess|vless|trojan|ss|ssr)://")
            combined_content="${combined_content}${content}"$'\n'
        fi
    done

    processed_nodes=""
    # 2. 逐行处理节点逻辑
    while read -r line; do
        [ -z "$line" ] && continue
        
        # 拆分链接 (link_part) 和备注 (new_name)
        if [[ "$line" == *"|"* ]]; then
            link_part="${line%%|*}"
            new_name="${line#*|}"
        else
            link_part="$line"
            new_name=""
        fi

        if [[ "$link_part" == vmess://* ]]; then
            # VMess 深度重写逻辑
            raw_b64="${link_part#vmess://}"
            # 解码并压缩 JSON（去除换行和多余空格）
            json_data=$(echo "$raw_b64" | tr -d '\n\r ' | base64 -d 2>/dev/null | tr -d '\n\r')
            
            if [[ -n "$json_data" && -n "$new_name" ]]; then
                # 使用全兼容正则替换 ps 字段
                new_json=$(echo "$json_data" | sed "s/\"ps\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"ps\":\"$new_name\"/g")
                # 重新打包成一行流 Base64
                new_link="vmess://$(echo -n "$new_json" | base64 -w 0)"
                processed_nodes="${processed_nodes}${new_link}"$'\n'
            else
                processed_nodes="${processed_nodes}${link_part}"$'\n'
            fi
        else
            # Trojan/VLESS/SS 备注重写逻辑
            if [[ -n "$new_name" ]]; then
                # 去掉原有的 # 备注，替换为新的
                clean_link="${link_part%%#*}"
                processed_nodes="${processed_nodes}${clean_link}#${new_name}"$'\n'
            else
                processed_nodes="${processed_nodes}${link_part}"$'\n'
            fi
        fi
    done <<< "$combined_content"

    # 3. 最终 Base64 编码并保存
    # sed '/^$/d' 确保没有空行混入最终编码
    echo -e -n "$processed_nodes" | sed '/^$/d' | base64 -w 0 > "${WEB_DIR}/${TOKEN_FILE}"
    
    echo "✅ 聚合成功！当前总节点数: $(echo "$processed_nodes" | grep -c "://")"
}

# 初始执行
process_nodes

# 4. 实时监控目录下的 .ini 文件变动
echo "监听配置目录: $CONFIG_DIR ..."
inotifywait -m -e modify,create,delete,move "$CONFIG_DIR" | while read path action file; do
    if [[ "$file" == *.ini ]]; then
        process_nodes
    fi
done
