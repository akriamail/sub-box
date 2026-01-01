#!/bin/bash
# ==========================================
# X-UI Sub Manager - Core Engine (v1.02)
# 职责：全协议备注名强制覆盖逻辑
# ==========================================

TOKEN=$(grep 'token =' /opt/subscribe/config.ini | cut -d'=' -f2 | tr -d ' ')

while true; do
    inotifywait -e close_write /opt/subscribe/config.ini
    
    tmp_list="/tmp/sub_list"
    > $tmp_list
    
    while read -r line; do
        # 核心改动：只处理包含 vmess://, vless://, trojan://, ss:// 等前缀的行
        if [[ "$line" =~ ^(vmess|vless|trojan|ss):// ]]; then
            if [[ "$line" == *"|"* ]]; then
                raw_link=$(echo "$line" | cut -d'|' -f1)
                custom_name=$(echo "$line" | cut -d'|' -f2)
                clean_link=$(echo "$raw_link" | sed 's/#.*//')
                final_line="${clean_link}#${custom_name}"
            else
                final_line="$line"
            fi
            echo "$final_line" >> $tmp_list
        fi
    done < /opt/subscribe/config.ini

    base64 -w 0 $tmp_list > /var/www/subscribe/$TOKEN
    chown www-data:www-data /var/www/subscribe/$TOKEN
done
