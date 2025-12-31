#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# 路径定义
CONF_DIR="/opt/subscribe"
CONF_FILE="/opt/subscribe/config.ini"
WEB_ROOT="/var/www/subscribe"

# 检查 root
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：${PLAIN}必须使用 root 用户运行！" && exit 1

# --- 核心逻辑：精准匹配域名证书与私钥 ---
find_xui_cert() {
    local target_domain=$1
    local cert_dir="/root/cert"
    local f_cert="" f_key=""
    
    if [ -d "$cert_dir" ]; then
        # 获取所有可能的证书文件，排除掉 selfsigned 目录以防万一
        for cert in $(find "$cert_dir" -type f \( -name "*.crt" -o -name "*.pem" -o -name "fullchain.cer" \) | grep -v "selfsigned"); do
            
            # 提取证书 CN 和 备用名称 (SAN)
            cert_info=$(openssl x509 -noout -subject -in "$cert" 2>/dev/null)
            issuer=$(openssl x509 -noout -issuer -in "$cert" 2>/dev/null)
            subject=$(openssl x509 -noout -subject -in "$cert" 2>/dev/null)
            
            # 1. 严格排除自签名证书
            if [[ "$issuer" == "$subject" ]]; then continue; fi

            # 2. 匹配域名逻辑
            # 如果没填域名，抓第一个合法的；如果填了域名，检查 CN 或证书内容是否包含该域名
            if [[ -z "$target_domain" ]] || [[ "$cert_info" == *"$target_domain"* ]]; then
                d_path=$(dirname "$cert")
                # 在同目录下寻找对应的私钥
                f_key=$(find "$d_path" -type f \( -name "*.key" -o -name "*key.pem" -o -name "privkey.pem" \) | head -n 1)
                
                if [[ -n "$f_key" ]]; then
                    f_cert="$cert"
                    # 如果 CN 完全匹配目标域名，直接锁定跳出
                    if [[ "$cert_info" == *"CN = $target_domain"* ]]; then
                        break
                    fi
                fi
            fi
        done
    fi
    echo "$f_cert|$f_key"
}

# --- 功能：信息查看 ---
show_info() {
    if [ ! -f "$CONF_FILE" ]; then 
        echo -e "${RED}未检测到安装配置！${PLAIN}"
        return
    fi
    TK=$(grep -Po '(?<=^token = ).*' "$CONF_FILE" | tr -d '\r ' )
    PT=$(grep -Po '(?<=^port = ).*' "$CONF_FILE" | tr -d '\r ' )
    CT=$(grep -Po '(?<=^cert_path = ).*' "$CONF_FILE" | tr -d '\r ' )
    DOM=$(grep -Po '(?<=^domain = ).*' "$CONF_FILE" | tr -d '\r ' )
    [[ -z "$DOM" ]] && ADDR=$(curl -s ifconfig.me) || ADDR="$DOM"
    [[ -n "$CT" ]] && SCH="https" || SCH="http"
    
    echo -e "\n${BLUE}================================================================${PLAIN}"
    echo -e "              ${GREEN}🚀 X-UI 极简订阅管理系统 ${PLAIN}"
    echo -e "${BLUE}================================================================${PLAIN}"
    echo -e "  ${YELLOW}▶ 订阅链接:${PLAIN}  ${GREEN}${SCH}://${ADDR}:${PT}/${TK}${PLAIN}"
    echo -e "  ${YELLOW}▶ 节点配置:${PLAIN}  ${YELLOW}nano $CONF_FILE${PLAIN}"
    echo -e "  ${YELLOW}▶ 证书路径:${PLAIN}  ${CT:-'未开启HTTPS'}"
    echo -e "  ${YELLOW}▶ 域名绑定:${PLAIN}  ${DOM:-'仅IP访问'}"
    echo -e "${BLUE}================================================================${PLAIN}\n"
}

# --- 功能：安装 ---
install_sub() {
    echo -e "${GREEN}正在初始化环境...${PLAIN}"
    apt update && apt install -y nginx inotify-tools grep sed openssl curl
    
    mkdir -p $CONF_DIR $WEB_ROOT
    
    echo -e "\n${BLUE}┌────────────────────────────────────────────────────────┐${PLAIN}"
    echo -e "${BLUE}│${PLAIN}                ${YELLOW}欢迎使用订阅一键安装向导${PLAIN}                ${BLUE}│${PLAIN}"
    echo -e "${BLUE}└────────────────────────────────────────────────────────┘${PLAIN}"

    read -p "  1. 请输入解析域名 (例如 hk2.changuoo.com): " user_domain
    read -p "  2. 请设置安全Token (直接回车随机生成): " user_token
    user_token=${user_token:-sub$(date +%s)}
    read -p "  3. 请设置订阅端口 (默认 8080): " user_port
    user_port=${user_port:-8080}
    
    # 拿着域名去搜精准的证书
    echo -e "${YELLOW}正在匹配域名 $user_domain 的合法证书对...${PLAIN}"
    IFS='|' read -r AUTO_CERT AUTO_KEY <<< "$(find_xui_cert "$user_domain")"
    
    local user_cert=""
    local user_key=""
    if [[ -n "$AUTO_CERT" ]]; then
        echo -e "\n${GREEN}  ✨ 匹配成功!${PLAIN}"
        echo -e "     证书: $AUTO_CERT"
        echo -e "     私钥: $AUTO_KEY"
        read -p "     是否使用此证书开启 HTTPS? (y/n, 默认y): " use_ssl
        if [[ "$use_ssl" != "n" ]]; then
            user_cert="$AUTO_CERT"
            user_key="$AUTO_KEY"
        fi
    else
        echo -e "\n${RED}  ❌ 未能找到 $user_domain 的有效证书对(已自动排除自签名)。${PLAIN}"
        echo -e "     系统将使用 HTTP 模式。若需手动指定，请安装后修改 config.ini。"
    fi

    cat << EOF > $CONF_FILE
[settings]
domain = $user_domain
token = $user_token
port = $user_port
cert_path = $user_cert
key_path = $user_key

[nodes]
# 在下方粘贴节点链接，一行一个
EOF

    # 写入 Nginx 生成器
    cat << 'EOF' > $CONF_DIR/nginx_gen.sh
#!/bin/bash
INI="/opt/subscribe/config.ini"
PORT=$(grep -Po '(?<=^port = ).*' "$INI" | tr -d '\r ')
CERT=$(grep -Po '(?<=^cert_path = ).*' "$INI" | tr -d '\r ')
KEY=$(grep -Po '(?<=^key_path = ).*' "$INI" | tr -d '\r ')
DOM=$(grep -Po '(?<=^domain = ).*' "$INI" | tr -d '\r ')
[[ -z "$DOM" ]] && DOM="_"
if [[ -f "$CERT" && -f "$KEY" ]]; then
    SSL="listen $PORT ssl; ssl_certificate $CERT; ssl_certificate_key $KEY; ssl_protocols TLSv1.2 TLSv1.3;"
else
    SSL="listen $PORT;"
fi
cat << N_EOF > /etc/nginx/sites-available/subscribe
server {
    $SSL
    server_name $DOM;
    root /var/www/subscribe;
    location = / { return 403; }
    location ~ ^/([a-zA-Z0-9_-]+)$ { 
        default_type text/plain; 
        try_files /\$1 =404; 
        add_header Access-Control-Allow-Origin *; 
    }
}
N_EOF
systemctl restart nginx
EOF
    chmod +x $CONF_DIR/nginx_gen.sh

    # 写入监控脚本
    cat << 'EOF' > $CONF_DIR/update.sh
#!/bin/bash
INI="/opt/subscribe/config.ini"
ROOT="/var/www/subscribe"
update() {
    bash /opt/subscribe/nginx_gen.sh
    TK=$(grep -Po '(?<=^token = ).*' "$INI" | tr -d '\r ')
    ND=$(sed -n '/\[nodes\]/,$p' "$INI" | grep -v '\[nodes\]' | grep -v '^#' | grep -v '^[[:space:]]*$')
    if [ -n "$TK" ]; then
        rm -rf "$ROOT"/*
        if [ -n "$ND" ]; then
            echo "$ND" | base64 -w 0 > "$ROOT/$TK"
        fi
    fi
}
update
inotifywait -m -e modify "$INI" | while read line; do update; done
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
    bash $CONF_DIR/nginx_gen.sh
    
    echo -e "\n${GREEN}🎉 安装成功!${PLAIN}"
    show_info
}

uninstall_sub() {
    systemctl stop subscribe 2>/dev/null
    systemctl disable subscribe 2>/dev/null
    rm -rf /etc/systemd/system/subscribe.service $CONF_DIR $WEB_ROOT /etc/nginx/sites-enabled/subscribe /etc/nginx/sites-available/subscribe
    systemctl restart nginx
    echo -e "${GREEN}卸载完成。${PLAIN}"
}

clear
echo -e "  1. 安装/更新系统\n  2. 查看订阅信息\n  3. 卸载系统\n  0. 退出"
read -p " 请输入数字 [0-3]: " opt
case $opt in
    1) install_sub ;;
    2) show_info ;;
    3) uninstall_sub ;;
    *) exit 0 ;;
esac
