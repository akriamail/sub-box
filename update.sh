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
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# || "$line" == "["* ]] && continue
        
        if [[ "$line" == *"|"* ]]; then
            # 1. 提取原始链接和新名字
            raw_link=$(echo "$line" | cut -d'|' -f1)
            custom_name=$(echo "$line" | cut -d'|' -f2)
            
            # 2. 【核心优化】彻底切除原链接中所有的 # 备注
            # 这里的 sed 逻辑是：删除第一个 # 及其后面的所有内容
            clean_link=$(echo "$raw_link" | sed 's/#.*//')
            
            # 3. 重新合成：干净链接 + 单个 # + 你的备注
            final_line="${clean_link}#${custom_name}"
        else
            final_line="$line"
        fi
        echo "$final_line" >> $tmp_list
    done < /opt/subscribe/config.ini

    base64 -w 0 $tmp_list > /var/www/subscribe/$TOKEN
    chown www-data:www-data /var/www/subscribe/$TOKEN
done
