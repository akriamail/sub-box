#!/bin/bash

# ==========================================
# sub-box 订阅管理 v1.0.4 (Enhanced)
# 核心特性：多源聚合、全协议支持、隐私隔离抓取
# ==========================================

echo "--------------------------------------------------"
echo "正在安装 sub-box 订阅管理 v1.0.4 (Enhanced)..."
echo "--------------------------------------------------"

# 1. 安装依赖 (增加了 python3 用于 URL 解码)
apt update
apt install -y inotify-tools curl nginx coreutils cron python3

# 2. 创建必要目录
mkdir -p /opt/subscribe
mkdir -p /var/www/subscribe

# 3. 智能配置检测
CONF_FILE="/opt/subscribe/config.ini"
URL_FILE="/opt/subscribe/airport_url.txt"

if [ -f "$CONF_FILE" ]; then
    echo "检测到现有配置，正在读取..."
    DOMAIN=$(grep 'domain =' "$CONF_FILE" | cut -d'=' -f2 | tr -d ' ')
    TOKEN=$(grep 'token =' "$CONF_FILE" | cut -d'=' -f2 | tr -d ' ')
    echo "✅ 沿用域名: $DOMAIN"
else
    read -p "请输入你的订阅域名 (例如 sub.example.com): " DOMAIN
    TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    
    cat > "$CONF_FILE" <<EOF
[common]
domain = $DOMAIN
token = $TOKEN
port = 8080
cert_path = /root/cert/$DOMAIN/fullchain.pem
key_path = /root/cert/$DOMAIN/privkey.pem

[nodes]
# 格式：链接|备注
EOF
    echo "✅ 已生成新配置文件"
fi

# 初始化机场链接文件 (方案 B)
[ ! -f "$URL_FILE" ] && touch "$URL_FILE" && echo "✅ 已初始化私密链接文件"

# 4. 从 GitHub 获取核心组件
echo "正在从 GitHub 获取 v1.0.4 核心组件..."
GITHUB_RAW="https://raw.githubusercontent.com/akriamail/sub-box/main"
curl -Ls $GITHUB_RAW/update.sh -o /opt/subscribe/update.sh
curl -Ls $GITHUB_RAW/fetch_ext.sh -o /opt/subscribe/fetch_ext.sh
chmod +x /opt/subscribe/*.sh

# 5. 生成 Nginx 配置 (保持你原有的逻辑)
cat > /etc/nginx/sites-available/subscribe <<EOF
server {
    listen 8080 ssl;
    server_name $DOMAIN;

    ssl_certificate /root/cert/$DOMAIN/fullchain.pem;
    ssl_certificate_key /root/cert/$DOMAIN/privkey.pem;

    location / {
        root /var/www/subscribe;
        autoindex on;
    }
}
EOF

ln -sf /etc/nginx/sites-available/subscribe /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

# 6. 启动后台引擎并设置开机自启
pkill -f update.sh
nohup /opt/subscribe/update.sh > /dev/null 2>&1 &

# 设置定时任务：开机自启 + 每天凌晨3点自动抓取机场节点
(crontab -l 2>/dev/null | grep -v "update.sh" | grep -v "fetch_ext.sh") > /tmp/cron_tmp
echo "@reboot nohup /opt/subscribe/update.sh > /dev/null 2>&1 &" >> /tmp/cron_tmp
echo "0 3 * * * /bin/bash /opt/subscribe/fetch_ext.sh > /dev/null 2>&1" >> /tmp/cron_tmp
crontab /tmp/cron_tmp
rm /tmp/cron_tmp

echo "--------------------------------------------------"
echo "✅ sub-box v1.0.4 (Enhanced) 安装成功！"
echo "管理目录: /opt/subscribe"
echo "1. 自建节点: 编辑 /opt/subscribe/config.ini"
echo "2. 机场节点: 在 /opt/subscribe/airport_url.txt 填入链接"
echo "             然后手动运行: bash /opt/subscribe/fetch_ext.sh"
echo "订阅链接: https://$DOMAIN:8080/$TOKEN"
echo "--------------------------------------------------"
