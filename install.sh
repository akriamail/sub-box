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

# --- 功能：查询并显示当前订阅信息 ---
show_info() {
    if [ ! -f "$CONF_FILE" ]; then 
        echo -e "${RED}未检测到安装配置！请先运行安装选项。${PLAIN}"
        return
    fi
    
    TK=$(grep -Po '(?<=^token = ).*' "$CONF_FILE" | tr -d '\r ' )
    PT=$(grep -Po '(?<=^port = ).*' "$CONF_FILE" | tr -d '\r ' )
    CT=$(grep -Po '(?<=^cert_path = ).*' "$CONF_FILE" | tr -d '\r ' )
    DOM=$(grep -Po '(?<=^domain = ).*' "$CONF_FILE" | tr -d '\r ' )
    
    [[ -z "$DOM" ]] && ADDR=$(curl -s ifconfig.me) || ADDR="$DOM"
    [[ -n "$CT" ]] && SCH="https" || SCH="http"
    STATUS=$(systemctl is-active subscribe 2>/dev/null)
    
    echo -e "\n${BLUE}================================================================${PLAIN}"
    echo -e "              ${GREEN}🚀 X-UI 极简订阅管理系统 ${PLAIN}"
    echo -e "${BLUE}================================================================${PLAIN}"
    echo -e "  ${YELLOW}▶ 订阅链接:${PLAIN}  ${GREEN}${SCH}://${ADDR}:${PT}/${TK}${PLAIN}"
    echo -e "  ${YELLOW}▶ 安全密钥:${PLAIN}  ${RED}${TK}${PLAIN}"
    echo -e "  ${YELLOW}▶ 监听端口:${PLAIN}  ${PT}"
    echo -e "  ${YELLOW}▶ 后台服务:${PLAIN}  $([[ "$STATUS" == "active" ]] && echo -e "${GREEN}运行中${PLAIN}" || echo -e "${RED}未运行${PLAIN}")"
    echo -e "${BLUE}----------------------------------------------------------------${PLAIN}"
    echo -e "  ${BLUE}📂 节点编辑方法:${PLAIN}"
    echo -e "  执行命令: ${YELLOW}vi $CONF_FILE${PLAIN}"
    echo -e "  在 ${YELLOW}[nodes]${PLAIN} 下方粘贴链接，保存退出即可自动生效。"
    echo -e "${BLUE}================================================================${PLAIN}\n"
}

# --- 功能：安装 ---
install_sub() {
    echo -e "${GREEN}正在初始化环境...${PLAIN}"
    apt update && apt install -y nginx inotify-tools grep sed openssl curl
    mkdir -p $CONF_DIR $WEB_ROOT
    chown -R www-data:www-data $WEB_ROOT

    echo -e "\n${BLUE}┌────────────────────────────────────────────────────────┐${PLAIN}"
    echo -e "${BLUE}│${PLAIN}                ${YELLOW}订阅管理系统一键安装向导${PLAIN}                ${BLUE}│${PLAIN}"
    echo -e "${BLUE}└────────────────────────────────────────────────────────┘${PLAIN}"

    read -p " 1. 请输入解析域名: " user_domain
    read -p " 2. 设置安全Token (直接回车随机生成): " user_token
    user_token=${user_token:-sub$(date +%s)}
    read -p " 3. 设置订阅端口 (默认 8080): " user_port
    user_port=${user_port:-8080}
    
    IFS='|' read -r AUTO_CERT AUTO_KEY <<< "$(find_xui_cert "$user_domain")"
    local final_cert="" final_key=""
    if [[ -n "$AUTO_CERT" ]]; then
        echo -e "\n${GREEN}✨ 自动匹配到证书:${PLAIN} $AUTO_CERT"
        read -p " 是否使用该证书开启 HTTPS? (y/n, 默认y): " use_ssl
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
# 请在此下方粘贴 vmess/vless 链接，一行一个
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

    # 写入同步脚本 (监听文件夹，完美支持 vi/vim)
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
inotifywait -m -e close_write -e moved_to "$IDIR" | while read -r path action file; do
    [[ "$file" == "config.ini" ]] && do_sync
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
    
    # 安装完成后直接显示信息
    echo -e "\n${GREEN}🎉 安装修复完成！${PLAIN}"
    show_info
}

# --- 主菜单 ---
clear
echo -e " ${BLUE}X-UI 极简订阅管理脚本${PLAIN}"
echo -e " ----------------------"
echo -e "  ${GREEN}1.${PLAIN} 安装/修复系统"
echo -e "  ${GREEN}2.${PLAIN} 查看订阅信息"
echo -e "  ${GREEN}3.${PLAIN} 卸载系统"
echo -e "  ${GREEN}0.${PLAIN} 退出"
echo -e " ----------------------"
read -p " 请选择数字 [0-3]: " opt
case $opt in
    1) install_sub ;;
    2) show_info ;;
    3) 
        systemctl stop subscribe 2>/dev/null
        systemctl disable subscribe 2>/dev/null
        rm -rf /etc/systemd/system/subscribe.service $CONF_DIR $WEB_ROOT /etc/nginx/sites-enabled/subscribe /etc/nginx/sites-available/subscribe
        systemctl restart nginx
        echo -e "${GREEN}卸载完成。${PLAIN}"
        ;;
    *) exit 0 ;;
esac
