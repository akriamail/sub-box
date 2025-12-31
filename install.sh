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

show_info() {
    if [ ! -f "$CONF_FILE" ]; then echo -e "${RED}未检测到安装！${PLAIN}"; return; fi
    TK=$(grep -Po '(?<=^token = ).*' "$CONF_FILE" | tr -d '\r ' )
    PT=$(grep -Po '(?<=^port = ).*' "$CONF_FILE" | tr -d '\r ' )
    CT=$(grep -Po '(?<=^cert_path = ).*' "$CONF_FILE" | tr -d '\r ' )
    DOM=$(grep -Po '(?<=^domain = ).*' "$CONF_FILE" | tr -d '\r ' )
    [[ -z "$DOM" ]] && ADDR=$(curl -s ifconfig.me) || ADDR="$DOM"
    [[ -n "$CT" ]] && SCH="https" || SCH="http"
    
    echo -e "\n${BLUE}================================================================${PLAIN}"
    echo -e "              ${GREEN}🚀 X-UI 订阅管理系统 (稳定版) ${PLAIN}"
    echo -e "${BLUE}================================================================${PLAIN}"
    echo -e "  ${YELLOW}▶ 订阅链接:${PLAIN}  ${GREEN}${SCH}://${ADDR}:${PT}/${TK}${PLAIN}"
    echo -e "  ${YELLOW}▶ 节点配置:${PLAIN}  ${YELLOW}nano $CONF_FILE${PLAIN}"
    echo -e "  ${YELLOW}▶ 证书文件:${PLAIN}  ${CT:-'未启用HTTPS'}"
    echo -e "  ${YELLOW}▶ 服务状态:${PLAIN}  $(systemctl is-active subscribe)"
    echo -e "${BLUE}================================================================${PLAIN}\n"
}

install_sub() {
    echo -e "${GREEN}正在安装环境...${PLAIN}"
    apt update && apt install -y nginx inotify-tools grep sed openssl curl
    mkdir -p $CONF_DIR $WEB_ROOT

    echo -e "\n${BLUE}--- 配置向导 ---${PLAIN}"
    read -p " 1. 请输入解析域名 (例如 hk2.changuoo.com): " user_domain
    read -p " 2. 设置安全Token (留空随机): " user_token
    user_token=${user_token:-sub$(date +%s)}
    read -p " 3. 设置订阅端口 (默认 8080): " user_port
    user_port=${user_port:-8080}
    
    # 找回确认逻辑
    echo -e "${YELLOW}正在扫描域名 $user_domain 的证书...${PLAIN}"
    IFS='|' read -r AUTO_CERT AUTO_KEY <<< "$(find_xui_cert "$user_domain")"
    
    local final_cert=""
    local final_key=""
    if [[ -n "$AUTO_CERT" ]]; then
        echo -e "\n${GREEN}✨ 发现匹配证书对:${PLAIN}"
        echo -e "   证书: $AUTO_CERT"
        echo -e "   私钥: $AUTO_KEY"
        read -p " 是否确认使用并开启 HTTPS? (y/n, 默认y): " use_ssl
        if [[ "$use_ssl" != "n" ]]; then
            final_cert="$AUTO_CERT"
            final_key="$AUTO_KEY"
        fi
    else
        echo -e "${RED}❌ 未能找到 $user_domain 的有效证书，将使用 HTTP 模式。${PLAIN}"
    fi

    cat << EOF > $CONF_FILE
[settings]
domain = $user_domain
token = $user_token
port = $user_port
cert_path = $final_cert
key_path = $final_key

[nodes]
# 在下方粘贴节点链接
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

    # 写入同步监控脚本 (启动同步+持续监听)
    cat << 'EOF' > $CONF_DIR/update.sh
#!/bin/bash
INI="/opt/subscribe/config.ini"
ROOT="/var/www/subscribe"
sync_now() {
    bash /opt/subscribe/nginx_gen.sh
    TK=$(grep -Po '(?<=^token = ).*' "$INI" | tr -d '\r ')
    ND=$(sed -n '/\[nodes\]/,$p' "$INI" | grep -v '\[nodes\]' | grep -v '^#' | grep -v '^[[:space:]]*$')
    rm -rf "$ROOT"/*
    if [[ -n "$TK" ]]; then
        [[ -n "$ND" ]] && echo "$ND" | base64 -w 0 > "$ROOT/$TK"
        chmod 644 "$ROOT/$TK"
    fi
}
# 启动时立即执行一次
sync_now
# 监听文件变动
inotifywait -m -e modify "$INI" | while read line; do sync_now; done
EOF
    chmod +x $CONF_DIR/update.sh

    # 注册服务
    cat << 'EOF' > /etc/systemd/system/subscribe.service
[Unit]
Description=X-UI Subscribe Auto-Sync Service
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
    
    # 最终确保目录权限
    chown -R www-data:www-data $WEB_ROOT
    chmod -R 755 $WEB_ROOT

    echo -e "${GREEN}安装完成！${PLAIN}"
    show_info
}

uninstall_sub() {
    systemctl stop subscribe 2>/dev/null
    systemctl disable subscribe 2>/dev/null
    rm -rf /etc/systemd/system/subscribe.service $CONF_DIR $WEB_ROOT /etc/nginx/sites-enabled/subscribe
    systemctl restart nginx
    echo -e "${GREEN}卸载完成。${PLAIN}"
}

clear
echo -e " 1. 安装/修复\n 2. 查看信息\n 3. 卸载\n 0. 退出"
read -p " 请选择: " opt
case $opt in
    1) install_sub ;;
    2) show_info ;;
    3) uninstall_sub ;;
    *) exit 0 ;;
esac
