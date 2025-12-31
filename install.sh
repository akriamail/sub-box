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

# --- 核心逻辑：智能证书识别 ---
find_xui_cert() {
    local cert_dir="/root/cert"
    local f_cert="" f_key=""
    if [ -d "$cert_dir" ]; then
        for cert in $(find "$cert_dir" -name "*.crt" -o -name "*.pem" -o -name "fullchain.cer" | head -n 5); do
            issuer=$(openssl x509 -noout -issuer -in "$cert" 2>/dev/null)
            subject=$(openssl x509 -noout -subject -in "$cert" 2>/dev/null)
            if [[ "$issuer" != "$subject" ]]; then
                cn=$(openssl x509 -noout -subject -in "$cert" | sed -n 's/.*CN = //p')
                if [[ "$cn" =~ [a-zA-Z] ]]; then
                    f_cert="$cert"
                    base=$(echo "$cert" | sed 's/\.[^.]*$//')
                    [[ -f "${base}.key" ]] && f_key="${base}.key"
                    [[ -f "/root/cert/private.key" && -z "$f_key" ]] && f_key="/root/cert/private.key"
                    break
                fi
            fi
        done
    fi
    echo "$f_cert|$f_key"
}

# --- 功能：信息查看 (豪华版) ---
show_info() {
    if [ ! -f "$CONF_FILE" ]; then 
        echo -e "${RED}未检测到安装配置！请先运行安装选项。${PLAIN}"
        return
    fi
    
    # 提取配置
    TK=$(grep -Po '(?<=^token = ).*' "$CONF_FILE" | tr -d '\r ' )
    PT=$(grep -Po '(?<=^port = ).*' "$CONF_FILE" | tr -d '\r ' )
    CT=$(grep -Po '(?<=^cert_path = ).*' "$CONF_FILE" | tr -d '\r ' )
    DOM=$(grep -Po '(?<=^domain = ).*' "$CONF_FILE" | tr -d '\r ' )
    
    if [ -z "$DOM" ]; then
        ADDR=$(curl -s ifconfig.me || echo "您的IP")
    else
        ADDR="$DOM"
    fi

    [ -n "$CT" ] && SCH="https" || SCH="http"
    STATUS=$(systemctl is-active subscribe 2>/dev/null)
    [ "$STATUS" == "active" ] && S_STR="${GREEN}运行中 (Running)${PLAIN}" || S_STR="${RED}停止 (Stopped)${PLAIN}"
    
    echo -e "\n${BLUE}================================================================${PLAIN}"
    echo -e "              ${GREEN}🚀 X-UI 极简订阅管理系统 (订阅信息) ${PLAIN}"
    echo -e "${BLUE}================================================================${PLAIN}"
    echo -e "  ${YELLOW}▶ 订阅链接:${PLAIN}  ${GREEN}${SCH}://${ADDR}:${PT}/${TK}${PLAIN}"
    echo -e "  ${YELLOW}▶ 后台状态:${PLAIN}  $S_STR"
    echo -e "  ${YELLOW}▶ 监听端口:${PLAIN}  ${PT}"
    echo -e "  ${YELLOW}▶ 安全密钥:${PLAIN}  ${TK}"
    echo -e "${BLUE}----------------------------------------------------------------${PLAIN}"
    echo -e "  ${BLUE}📂 关键位置:${PLAIN}"
    echo -e "  - 节点配置文件: ${YELLOW}nano $CONF_FILE${PLAIN}"
    echo -e "  - 订阅文件目录: /var/www/subscribe"
    echo -e "  - Nginx 配置文件: /etc/nginx/sites-available/subscribe"
    echo -e "${BLUE}----------------------------------------------------------------${PLAIN}"
    echo -e "  ${BLUE}💡 使用提示:${PLAIN}"
    echo -e "  1. 请编辑上述 ${YELLOW}config.ini${PLAIN}，在 ${YELLOW}[nodes]${PLAIN} 下方粘贴链接。"
    echo -e "  2. 粘贴并保存后，系统会毫秒级自动更新订阅内容。"
    echo -e "  3. 若无法访问，请检查云服务商安全组是否放行了 ${RED}${PT}${PLAIN} 端口。"
    echo -e "${BLUE}================================================================${PLAIN}\n"
}

# --- 功能：安装 ---
install_sub() {
    echo -e "${GREEN}正在初始化环境...${PLAIN}"
    apt update && apt install -y nginx inotify-tools grep sed openssl curl
    
    mkdir -p $CONF_DIR $WEB_ROOT
    IFS='|' read -r AUTO_CERT AUTO_KEY <<< "$(find_xui_cert)"
    
    echo -e "\n${BLUE}┌────────────────────────────────────────────────────────┐${PLAIN}"
    echo -e "${BLUE}│${PLAIN}                ${YELLOW}欢迎使用订阅一键安装向导${PLAIN}                ${BLUE}│${PLAIN}"
    echo -e "${BLUE}└────────────────────────────────────────────────────────┘${PLAIN}"

    read -p "  1. 请输入解析域名 (留空则默认使用IP): " user_domain
    read -p "  2. 请设置安全Token (直接回车随机生成): " user_token
    user_token=${user_token:-sub$(date +%s)}
    read -p "  3. 请设置订阅端口 (默认 8080): " user_port
    user_port=${user_port:-8080}
    
    local user_cert=""
    local user_key=""
    if [ -n "$AUTO_CERT" ]; then
        echo -e "\n${GREEN}  ✨ 发现 x-ui 证书:${PLAIN} $AUTO_CERT"
        read -p "     是否引用此证书启用 HTTPS 加密? (y/n, 默认y): " use_ssl
        if [ "$use_ssl" != "n" ]; then
            user_cert="$AUTO_CERT"
            user_key="$AUTO_KEY"
        fi
    fi

    # 写入配置
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
[ -z "$DOM" ] && DOM="_"
if [ -f "$CERT" ] && [ -f "$KEY" ]; then
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
    
    echo -e "\n${GREEN}🎉 系统安装成功! 后台服务已启动。${PLAIN}"
    show_info
}

uninstall_sub() {
    echo -e "${YELLOW}正在清理系统资源...${PLAIN}"
    systemctl stop subscribe 2>/dev/null
    systemctl disable subscribe 2>/dev/null
    rm -rf /etc/systemd/system/subscribe.service $CONF_DIR $WEB_ROOT /etc/nginx/sites-enabled/subscribe /etc/nginx/sites-available/subscribe
    systemctl restart nginx
    echo -e "${GREEN}卸载完成。${PLAIN}"
}

# --- 菜单界面 ---
clear
echo -e "${BLUE}################################################${PLAIN}"
echo -e "${BLUE}#${PLAIN}          ${GREEN}V2Ray/X-UI 订阅一键管理脚本${PLAIN}         ${BLUE}#${PLAIN}"
echo -e "${BLUE}################################################${PLAIN}"
echo -e "  ${YELLOW}1.${PLAIN}  安装/更新系统"
echo -e "  ${YELLOW}2.${PLAIN}  ${BLUE}查看当前订阅信息${PLAIN}"
echo -e "  ${YELLOW}3.${PLAIN}  卸载系统"
echo -e "  ${YELLOW}0.${PLAIN}  退出"
echo -e "${BLUE}------------------------------------------------${PLAIN}"
read -p " 请输入数字 [0-3]: " opt
case $opt in
    1) install_sub ;;
    2) show_info ;;
    3) uninstall_sub ;;
    *) exit 0 ;;
esac
