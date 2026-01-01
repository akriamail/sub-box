#!/bin/bash
# ==========================================
# X-UI Sub Manager - Core Engine (v1.0.0-Stable)
# 功能：实时监听配置、全协议过滤、VMess 内部重写
# ==========================================

CONF_PATH="/opt/subscribe/config.ini"
SUB_DIR="/var/www/subscribe"

while true; do
    # 1. 自动获取当前 Token (支持动态修改)
    TOKEN=$(grep 'token =' $CONF_PATH | cut -d'=' -f2 | tr -d ' ')
    
    # 2. 等待配置文件保存（close_write 事件）
    inotifywait -e close_write $CONF_PATH
    
    # 3. 开始处理节点列表
    tmp_list="/tmp/sub_list"
    > $tmp_list
    
    while read -r line; do
        # 仅处理包含协议头的行，过滤掉 domain/token 等配置行
        if [[ "$line" =~ ^vmess:// ]]; then
            # --- VMess 深度重写逻辑 ---
            raw_link=$(echo "$line" | cut -d'|' -f1 | sed 's/vmess:\/\///')
            custom_name=$(echo "$line" | cut -d'|' -f2)
            
            if [[ "$line" == *"|"* ]]; then
                decoded_json=$(echo "$raw_link" | base64 -d 2>/dev/null)
                if [[ -n "$decoded_json" ]]; then
                    # 关键手术：精准替换 JSON 内部的 ps 字段
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
            # --- 其他协议备注处理 (链接#备注) ---
            if [[ "$line" == *"|"* ]]; then
                raw_link=$(echo "$line" | cut -d'|' -f1 | sed 's/#.*//')
                custom_name=$(echo "$line" | cut -d'|' -f2)
                echo "${raw_link}#${custom_name}" >> $tmp_list
            else
                echo "$line" >> $tmp_list
            fi
        fi
    done < $CONF_PATH

    # 4. 生成订阅文件并加密
    base64 -w 0 $tmp_list > $SUB_DIR/$TOKEN
    chown www-data:www-data $SUB_DIR/$TOKEN
    
    # 清理临时文件
    rm -f $tmp_list
done
