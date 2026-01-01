#!/bin/bash
# ==========================================
# X-UI Sub Manager - Core Engine (v1.04)
# 职责：深度重写 VMess 内部备注 + 协议过滤
# ==========================================

TOKEN=$(grep 'token =' /opt/subscribe/config.ini | cut -d'=' -f2 | tr -d ' ')

while true; do
    inotifywait -e close_write /opt/subscribe/config.ini
    
    tmp_list="/tmp/sub_list"
    > $tmp_list
    
    while read -r line; do
        if [[ "$line" =~ ^vmess:// ]]; then
            # --- VMess 深度处理逻辑 ---
            raw_link=$(echo "$line" | cut -d'|' -f1 | sed 's/vmess:\/\///')
            custom_name=$(echo "$line" | cut -d'|' -f2)
            
            if [[ "$line" == *"|"* ]]; then
                # 解码 JSON -> 修改 ps 字段 -> 重新 Base64 编码
                decoded_json=$(echo "$raw_link" | base64 -d 2>/dev/null)
                if [[ -n "$decoded_json" ]]; then
                    # 使用 sed 替换 JSON 里的 ps 字段内容
                    new_json=$(echo "$decoded_json" | sed "s/\"ps\":\s*\"[^\"]*\"/\"ps\": \"$custom_name\"/")
                    final_line="vmess://$(echo -n "$new_json" | base64 -w 0)"
                else
                    final_line="vmess://$raw_link"
                fi
            else
                final_line="vmess://$raw_link"
            fi
            echo "$final_line" >> $tmp_list
            
        elif [[ "$line" =~ ^(vless|trojan|ss):// ]]; then
            # --- 其他协议（Trojan/VLESS）简单处理 ---
            if [[ "$line" == *"|"* ]]; then
                raw_link=$(echo "$line" | cut -d'|' -f1 | sed 's/#.*//')
                custom_name=$(echo "$line" | cut -d'|' -f2)
                final_line="${raw_link}#${custom_name}"
            else
                final_line="$line"
            fi
            echo "$final_line" >> $tmp_list
        fi
    done < /opt/subscribe/config.ini

    base64 -w 0 $tmp_list > /var/www/subscribe/$TOKEN
    chown www-data:www-data /var/www/subscribe/$TOKEN
done
