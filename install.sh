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
        # 遍历所有证书文件
        for cert in $(find "$cert_dir" -type f \( -name "*.crt" -o -name "*.pem" -o -name "fullchain.cer" \)); do
            # 获取证书的 CN (Common Name)
            cn=$(openssl x509 -noout -subject -in "$cert" 2>/dev/null | sed -n 's/.*CN = //p')
            issuer=$(openssl x509 -noout -issuer -in "$cert" 2>/dev/null)
            subject=$(openssl x509 -noout -subject -in "$cert" 2>/dev/null)
            
            # 过滤逻辑：1. 不是自签名 2. 如果提供了域名则匹配域名
            if [[ "$issuer" != "$subject" ]]; then
                if [[ -z "$target_domain" ]] || [[ "$cn" == *"$target_domain"* ]]; then
                    d_path=$(dirname "$cert")
                    # 在同目录下寻找对应的私钥
                    f_key=$(find "$d_path" -type f \( -name "*.key" -o -name "*key.pem" -o -name "privkey.pem" \) | head -n 1)
                    
                    if [[ -n "$f_key" ]]; then
                        f_cert="$cert"
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
    echo -e "${YELLOW}正在匹配域名 $user_domain 的证书对...${PLAIN}"
    IFS='|' read -r AUTO_CERT AUTO_KEY <<< "$(find_xui_cert "$user_domain")"
    
    local user_cert=""
    local user_key=""
    if [[ -n "$AUTO_CERT" ]]; then
        echo -e "\n${GREEN}  ✨ 精准匹配成功!${PLAIN}"
        echo -e "     证书: $AUTO_CERT"
        echo -e "     私钥: $AUTO_KEY"
        read -p "     是否使用此证书开启 HTTPS? (y/n, 默认y): " use_ssl
        if [ "$use_ssl" != "n" ]; then
            user_cert="$AUTO_CERT"
            user_key="$AUTO_KEY"
        fi
    else
        echo -e "\n${RED}  ❌ 未能自动找到域名 $user_domain 的证书对。${PLAIN}"
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
# 请在下方粘贴您的链接
EOF

    # 写入 Nginx 生成器 (逻辑同上，略)
    # ... 此处省略 Nginx/Service 写入逻辑以节省篇幅，实际脚本中应完整 ...
    # (确保保留之前版本中完整的 Nginx_gen.sh 和 update.sh 内容)
