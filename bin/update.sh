#!/bin/bash

CONFIG_DIR="/opt/subscribe"
WEB_DIR="/var/www/subscribe"

url_escape() {
    python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

get_config_value() {
    local key="$1"
    grep "^${key} =" "$CONFIG_DIR/config.ini" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/^ *//;s/ *$//'
}

node_to_uri() {
    local line="$1"
    local domain="$2"
    local proto host port secret name

    if [[ "$line" == *"://"* ]]; then
        if [[ "$line" == *"|"* ]]; then
            local link_part="${line%%|*}"
            local new_name="${line#*|}"
            if [[ -n "$new_name" ]]; then
                echo "${link_part%%#*}#$(url_escape "$new_name")"
            else
                echo "$link_part"
            fi
        else
            echo "$line"
        fi
        return 0
    fi

    IFS='|' read -r proto host port secret name _ <<< "$line"
    if [[ "$host" =~ ^[0-9]+$ ]]; then
        name="$secret"
        secret="$port"
        port="$host"
        host="$domain"
    fi
    [[ -z "$host" ]] && host="$domain"
    [[ -z "$name" ]] && name="${proto}-${host}-${port}"

    case "$proto" in
        trojan)
            echo "trojan://${secret}@${host}:${port}#$(url_escape "$name")"
            ;;
        vmess)
            local json
            json=$(printf '{"v":"2","ps":"%s","add":"%s","port":"%s","id":"%s","aid":"0","net":"tcp","type":"none","host":"","path":"","tls":"tls"}' "$name" "$host" "$port" "$secret")
            echo "vmess://$(printf '%s' "$json" | base64 -w 0)"
            ;;
        vless)
            echo "vless://${secret}@${host}:${port}?encryption=none&security=reality&type=tcp&flow=xtls-rprx-vision#$(url_escape "$name")"
            ;;
        hysteria2|hy2)
            echo "hysteria2://${secret}@${host}:${port}?sni=${host}#$(url_escape "$name")"
            ;;
        ss)
            echo "ss://${secret}@${host}:${port}#$(url_escape "$name")"
            ;;
    esac
}

process_nodes() {
    echo "--- 正在深度处理节点 ($(date)) ---"

    local domain token token_file
    domain=$(get_config_value "domain")
    token=$(get_config_value "token")
    token_file="$WEB_DIR/$token"
    mkdir -p "$WEB_DIR"

    if [[ -z "$token" ]]; then
        echo "❌ config.ini 缺少 token，无法生成订阅文件"
        return 1
    fi

    combined_content=""
    for ini_file in "$CONFIG_DIR"/*.ini; do
        if [ -f "$ini_file" ]; then
            content=$(sed -n '/^\[nodes\]/,$p' "$ini_file" | grep -Ev '^\[|^#|^$')
            combined_content+="$content"$'\n'
        fi
    done

    processed_nodes=""
    while read -r line; do
        [ -z "$line" ] && continue
        processed_nodes+="$(node_to_uri "$line" "$domain")"$'\n'
    done <<< "$combined_content"

    find "$WEB_DIR" -maxdepth 1 -type f ! -name index.html ! -name "$token" -delete 2>/dev/null
    echo -e -n "$processed_nodes" | sed '/^$/d' | base64 -w 0 > "$token_file"

    echo "✅ 聚合成功！当前节点总数: $(echo "$processed_nodes" | grep -c "://")"
}

process_nodes

inotifywait -m -e modify,create,delete,move "$CONFIG_DIR" | while read path action file; do
    if [[ "$file" == *.ini ]]; then
        process_nodes
    fi
done
