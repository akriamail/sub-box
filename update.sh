#!/bin/bash
# ==========================================
# X-UI Sub Manager - Core Engine (v1.01)
# 职责：解析 config.ini 并实时生成 Base64
# ==========================================

# 从配置文件获取 Token
TOKEN=$(grep 'token =' /opt/subscribe/config.ini | cut -d'=' -f2 | tr -d ' ')

while true; do
    # 阻塞式监听文件变化
    inotifywait -e close_write /opt/subscribe/config.ini
    
    tmp_list="/tmp/sub_list"
    > $tmp_list
    
    while read -r line; do
        # 过滤掉空行、注释、以及 [common] [nodes] 标签
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# || "$line" == "["* ]] && continue
        
        # 核心逻辑：处理 | 符号
        if [[ "$line" == *"|"* ]]; then
            link=$(echo "$line" | cut -d'|' -f1)
            name=$(echo "$line" | cut -d'|' -f2)
            # 拼接：原链接(去旧备注) + # + 新备注
            final_line="$(echo "$link" | cut -d'#' -f1)#$name"
        else
            final_line="$line"
        fi
        echo "$final_line" >> $tmp_list
    done < /opt/subscribe/config.ini

    # 生成最终文件
    base64 -w 0 $tmp_list > /var/www/subscribe/$TOKEN
    chown www-data:www-data /var/www/subscribe/$TOKEN
done
