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

# --- 核心逻辑：精准匹配域名证书 ---
find_xui_cert() {
    local target_domain=$1
    local cert_dir="/root/cert"
    local f_cert="" f_key=""
    if [ -d "$cert_dir" ]; then
        for cert in $(find "$cert_dir" -type f \( -name "*.crt" -o -name "*.pem" -o -name "fullchain.cer" \) | grep -v "selfsigned"); do
            cert_info=$(openssl x509 -noout -subject -in "$cert" 2>/dev/null)
            issuer=$(openssl x509 -noout -issuer -in "$cert" 2>/dev/null)
            subject=$(openssl x509 -noout -subject -in "$cert" 2>/dev/null)
            if [[ "$issuer" == "$subject" ]]; then continue; fi
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

# --- 功能：信息查看 ---
show_info() {
    if [ ! -f "$CONF_FILE" ]; then echo -e "${RED}未检测到安装！${PLAIN}"; return; fi
    TK=$(grep -Po '(?<=^token = ).*' "$CONF_FILE" | tr -d '\r ' )
    PT=$(grep -Po '(?<=^port = ).*' "$CONF_FILE" | tr -d '\r ' )
    CT=$(grep -Po '(?<=^cert_path = ).*' "$CONF_FILE" | tr -d '\r ' )
    DOM=$(grep -Po '(?<=^domain = ).*' "$CONF_FILE" | tr -d '\r ' )
    [[ -z "$DOM" ]] && ADDR=$(curl -s ifconfig.me) || ADDR="$DOM"
    [[ -n "$CT" ]] && SCH="https" || SCH="http"
    
    echo -e "\n${BLUE}================================================================${PLAIN}"
    echo -e "              ${GREEN}🚀 X-UI 订阅管理系统 (已修复版) ${PLAIN}"
    echo -e "${BLUE}================================================================${PLAIN}"
    echo -e "  ${YELLOW}▶ 订阅链接:${PLAIN}  ${GREEN}${SCH}://${ADDR}:${PT}/${TK}${PLAIN}"
    echo -e "  ${YELLOW}▶ 节点配置:${PLAIN}  ${YELLOW}nano $CONF_FILE${PLAIN}"
    echo -e "  ${YELLOW}▶ 服务状态:${PLAIN}  $(systemctl is-active subscribe)"
    echo -e "${BLUE}================================================================${PLAIN}\n"
}

# --- 功能：安装 ---
install_sub() {
    apt update && apt install -y nginx inotify-tools grep sed openssl curl
    mkdir -p $CONF_DIR $WEB_ROOT
    chown -R www-data:www-data $WEB_ROOT

    read -p " 1. 输入解析域名: " user_domain
    read -p " 2. 设置安全Token: " user_token
    user_token=${user_token:-sub$(date +%s)}
    read -p " 3. 设置订阅端口 (默认 8080): " user_port
    user_port=${user_port:-8080}
    
    IFS='|' read -r AUTO_CERT AUTO_KEY <<< "$(find_xui_cert "$user_domain")"
    
    cat << EOF > $CONF_FILE
[settings]
domain = $user_domain
token = $user_token
port = $user_port
cert_path = $AUTO_CERT
key_path = $AUTO_KEY

[nodes]
# 在下方粘贴节点链接
EOF

    # 写入 Nginx 生成器 (修正变量转义)
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

    # 写入监控脚本 (修正：先更新，后监听)
    cat << 'EOF' > $CONF_DIR/update.sh
#!/bin/bash
INI="/opt/subscribe/config.ini"
ROOT="/var/www/subscribe"
update_logic() {
    bash /opt/subscribe/nginx_gen.sh
    TK=$(grep -Po '(?<=^token = ).*' "$INI" | tr -d '\r ')
    ND=$(sed -n '/\[nodes\]/,$p' "$INI" | grep -v '\[nodes\]' | grep -v '^#' | grep -v '^[[:space:]]*$')
    rm -rf "$ROOT"/*
    [[ -n "$TK" && -n "$ND" ]] && echo "$ND" | base64 -w 0 > "$ROOT/$TK"
    chown -R www-data:www-data "$ROOT"
}
# 核心修复：启动时立即执行一次
update_logic
# 进入循环监听
inotifywait -m -e modify "$INI" | while read line; do update_logic; done
EOF
    chmod +x $CONF_DIR/update.sh

    # 注册服务
    cat << 'EOF' > /etc/systemd/system/subscribe.service
[Unit]
Description=Subscribe Service
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
    
    echo -e "${GREEN}修复版安装成功!${PLAIN}"
    show_info
}

uninstall_sub() {
    systemctl stop subscribe 2>/dev/null
    rm -rf /etc/systemd/system/subscribe.service $CONF_DIR $WEB_ROOT /etc/nginx/sites-enabled/subscribe
    systemctl restart nginx
    echo -e "${GREEN}卸载完成。${PLAIN}"
}

clear
echo -e " 1. 安装/修复\n 2. 信息\n 3. 卸载\n 0. 退出"
read -p " 选择: " opt
case $opt in
    1) install_sub ;;
    2) show_info ;;
    3) uninstall_sub ;;
    *) exit 0 ;;
esac
