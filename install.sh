#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
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
        for cert in $(find "$cert_dir" -name "*.crt" -o -name "*.pem" -o -name "fullchain.cer"); do
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

# --- 功能：信息查看 ---
show_info() {
    if [ ! -f "$CONF_FILE" ]; then 
        echo -e "${RED}未检测到安装配置！${PLAIN}"
        return
    fi
    
    # 解析配置，去除可能存在的空格和换行符
    TK=$(grep -Po '(?<=^token = ).*' "$CONF_FILE" | tr -d '\r ' || echo "")
    PT=$(grep -Po '(?<=^port = ).*' "$CONF_FILE" | tr -d '\r ' || echo "8080")
    CT=$(grep -Po '(?<=^cert_path = ).*' "$CONF_FILE" | tr -d '\r ' || echo "")
    DOM=$(grep -Po '(?<=^domain = ).*' "$CONF_FILE" | tr -d '\r ' || echo "")
    
    # 逻辑修正：如果域名为空，获取公网IP
    if [[ -z "$DOM" ]]; then
        ADDR=$(curl -s ifconfig.me || curl -s api.ipify.org || echo "您的IP")
    else
        ADDR=$DOM
    fi

    # 判断协议
    if [[ -n "$CT" ]]; then SCH="https"; else SCH="http"; fi
    
    echo -e "\n${GREEN}========================================${PLAIN}"
    echo -e "${GREEN}    订阅管理信息 (已生效) ${PLAIN}"
    echo -e "订阅地址: ${YELLOW}${SCH}://${ADDR}:${PT}/${TK}${PLAIN}"
    echo -e "配置文件: ${YELLOW}nano $CONF_FILE${PLAIN}"
    echo -e "服务状态: $(systemctl is-active subscribe 2>/dev/null || echo 'inactive')"
    echo -e "${GREEN}========================================${PLAIN}"
    echo -e "${YELLOW}提示：请编辑配置文件并在 [nodes] 下方添加节点链接后即可使用。${PLAIN}\n"
}

# --- 功能：安装 ---
install_sub() {
    echo -e "${GREEN}正在安装基础环境 (Nginx/inotify)...${PLAIN}"
    apt update && apt install -y nginx inotify-tools grep sed openssl curl
    
    mkdir -p $CONF_DIR $WEB_ROOT
    
    # 证书识别
    IFS='|' read -r AUTO_CERT AUTO_KEY <<< "$(find_xui_cert)"
    
    echo -e "\n${YELLOW}--- 配置向导 ---${PLAIN}"
    read -p "1. 输入您的解析域名 (直接回车则使用IP): " user_domain
    read -p "2. 设置订阅安全Token (建议长乱码): " user_token
    user_token=${user_token:-sub$(date +%s)}
    read -p "3. 设置订阅端口 (默认 8080): " user_port
    user_port=${user_port:-8080}
    
    local user_cert=""
    local user_key=""
    if [ ! -z "$AUTO_CERT" ]; then
        echo -e "${GREEN}检测到 x-ui 域名证书: $AUTO_CERT${PLAIN}"
        read -p "是否引用此证书启用 HTTPS? (y/n, 默认y): " use_ssl
        if [[ "$use_ssl" != "n" ]]; then
            user_cert=$AUTO_CERT
            user_key=$AUTO_KEY
        fi
    fi

    # 写入 config.ini
    cat << EOF > $CONF_FILE
[settings]
domain = $user_domain
token = $user_token
port = $user_port
cert_path = $user_cert
key_path = $user_key

[nodes]
# 粘贴链接到此处 (一行一个)
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
    if [ ! -z "$TK" ]; then
        rm -rf "$ROOT"/*
        if [ ! -z "$ND" ]; then
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
    
    # 最终生效
    bash $CONF_DIR/nginx_gen.sh
    
    echo -e "${GREEN}安装成功！${PLAIN}"
    show_info
}

# --- 功能：卸载 ---
uninstall_sub() {
    systemctl stop subscribe 2>/dev/null
    systemctl disable subscribe 2>/dev/null
    rm -rf /etc/systemd/system/subscribe.service $CONF_DIR $WEB_ROOT /etc/nginx/sites-enabled/subscribe
    systemctl restart nginx
    echo -e "${GREEN}系统已彻底卸载。${PLAIN}"
}

# --- 菜单 ---
clear
echo -e "${GREEN}########################################${PLAIN}"
echo -e "${GREEN}#       V2Ray/X-UI 订阅一键脚本        #${PLAIN}"
echo -e "${GREEN}########################################${PLAIN}"
echo -e "  1. 安装系统"
echo -e "  2. 查看订阅地址"
echo -e "  3. 卸载系统"
echo -e "  0. 退出"
read -p "选择 [0-3]: " opt
case $opt in
    1) install_sub ;;
    2) show_info ;;
    3) uninstall_sub ;;
    *) exit 0 ;;
esac
