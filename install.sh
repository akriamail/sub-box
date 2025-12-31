#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

CONF_DIR="/opt/subscribe"
CONF_FILE="/opt/subscribe/config.ini"
WEB_ROOT="/var/www/subscribe"

[[ $EUID -ne 0 ]] && echo -e "${RED}错误：${PLAIN}必须使用 root 用户运行！" && exit 1

# --- 核心逻辑：深度匹配域名证书 ---
find_xui_cert() {
    local target_domain=$1
    local cert_dir="/root/cert"
    local f_cert="" f_key=""
    if [ -d "$cert_dir" ]; then
        for cert in $(find "$cert_dir" -type f \( -name "*.crt" -o -name "*.pem" -o -name "fullchain.cer" \) | grep -v "selfsigned"); do
            cert_info=$(openssl x509 -noout -subject -in "$cert" 2>/dev/null)
            issuer=$(openssl x509 -noout -issuer -in "$cert" 2>/dev/null)
            subject=$(openssl x509 -noout -subject -in "$cert" 2>/dev/null)
            [[ "$issuer" == "$subject" ]] && continue
            if [[ -z "$target_domain" ]] || [[ "$cert_info" == *"$target_domain"* ]]; then
                d_path=$(dirname "$cert")
                f_key=$(find "$d_path" -type f \( -name "*.key" -o -name "*key.pem" -o -name "privkey.pem" \) | head -n 1)
                if [[ -n "$f_key" ]]; then
                    f_cert="$cert"; break
                fi
            fi
        done
    fi
    echo "$f_cert|$f_key"
}

# --- 功能：安装 ---
install_sub() {
    echo -e "${GREEN}正在初始化环境...${PLAIN}"
    apt update && apt install -y nginx inotify-tools grep sed openssl curl
    mkdir -p $CONF_DIR $WEB_ROOT
    chown -R www-data:www-data $WEB_ROOT

    echo -e "\n${BLUE}--- 订阅系统配置 (兼容vi/vim版) ---${PLAIN}"
    read -p " 1. 输入解析域名: " user_domain
    read -p " 2. 设置 Token (回车随机): " user_token
    user_token=${user_token:-sub$(date +%s)}
    read -p " 3. 设置端口 (默认 8080): " user_port
    user_port=${user_port:-8080}
    
    IFS='|' read -r AUTO_CERT AUTO_KEY <<< "$(find_xui_cert "$user_domain")"
    local final_cert="" final_key=""
    if [[ -n "$AUTO_CERT" ]]; then
        echo -e "\n${GREEN}✨ 自动匹配到证书:${PLAIN} $AUTO_CERT"
        read -p " 是否使用该证书开启 HTTPS? (y/n): " use_ssl
        [[ "$use_ssl" != "n" ]] && final_cert="$AUTO_CERT" && final_key="$AUTO_KEY"
    fi

    cat << EOF > $CONF_FILE
[settings]
domain = $user_domain
token = $user_token
port = $user_port
cert_path = $final_cert
key_path = $final_key

[nodes]
# 请在此下方粘贴 vmess/vless 链接
EOF

    # 写入 Nginx 生成器
    cat << 'EOF' > $CONF_DIR/nginx_gen.sh
#!/bin/bash
INI="/opt/subscribe/config.ini"
PT=$(grep -Po '(?<=^port = ).*' "$INI" | tr -d '\r ')
CRT=$(grep -Po '(?<=^cert_path = ).*' "$INI" | tr -d '\r ')
KEY=$(grep -Po '(?<=^key_path = ).*' "$INI" | tr -d '\r ')
DOM=$(grep -Po '(?<=^domain = ).*' "$INI" | tr -d '\r ')
[[ -z "$DOM" ]] && DOM="_"
[[ -f "$CRT" && -f "$KEY" ]] && SSL="listen $PT ssl; ssl_certificate $CRT; ssl_certificate_key $KEY;" || SSL="listen $PT;"

cat << N_EOF > /etc/nginx/sites-available/subscribe
server {
    $SSL
    server_name $DOM;
    root /var/www/subscribe;
    location / {
        default_type text/plain;
        try_files \$uri =404;
        add_header Access-Control-Allow-Origin *;
    }
}
N_EOF
systemctl restart nginx
EOF
    chmod +x $CONF_DIR/nginx_gen.sh

    # 写入同步脚本 (核心改进：适配 vi 的 temp-move 模式)
    cat << 'EOF' > $CONF_DIR/update.sh
#!/bin/bash
INI="/opt/subscribe/config.ini"
IDIR="/opt/subscribe"
ROOT="/var/www/subscribe"
do_sync() {
    bash /opt/subscribe/nginx_gen.sh
    TK=$(grep -Po '(?<=^token = ).*' "$INI" | tr -d '\r ')
    ND=$(sed -n '/\[nodes\]/,$p' "$INI" | grep -v '\[nodes\]' | grep -v '^#' | grep -v '^[[:space:]]*$')
    rm -rf "$ROOT"/*
    if [[ -n "$TK" && -n "$ND" ]]; then
        echo "$ND" | base64 -w 0 > "$ROOT/$TK"
        chmod 644 "$ROOT/$TK"
        chown www-data:www-data "$ROOT/$TK"
    fi
}
do_sync
# 改进点：监听目录的移动和写入关闭事件，完美兼容 vi/vim
inotifywait -m -e close_write -e moved_to "$IDIR" | while read -r path action file; do
    if [[ "$file" == "config.ini" ]]; then
        do_sync
    fi
done
EOF
    chmod +x $CONF_DIR/update.sh

    # 注册服务
    cat << 'EOF' > /etc/systemd/system/subscribe.service
[Unit]
Description=Subscribe Auto Update Service
After=network.target nginx.service
[Service]
ExecStart=/bin/bash /opt/subscribe/update.sh
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now subscribe
    ln -sf /etc/nginx/sites-available/subscribe /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    echo -e "${GREEN}安装完成！现在你可以放心使用 vi 编辑 $CONF_FILE 了。${PLAIN}"
}

# --- 菜单 ---
clear
echo -e " 1. 安装/修复系统\n 2. 卸载系统\n 0. 退出"
read -p " 选择: " opt
case $opt in
    1) install_sub ;;
    2) 
        systemctl stop subscribe 2>/dev/null
        rm -rf /etc/systemd/system/subscribe.service $CONF_DIR $WEB_ROOT /etc/nginx/sites-enabled/subscribe
        systemctl restart nginx
        echo -e "${GREEN}已卸载。${PLAIN}"
        ;;
    *) exit 0 ;;
esac
