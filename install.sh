#!/bin/bash

# ==========================================
# X-UI 订阅管理 v1.0.0 (Stable)
# ==========================================

echo "--------------------------------------------------"
echo "正在安装 X-UI 订阅管理 v1.0.0 (Stable)..."
echo "--------------------------------------------------"

# 1. 安装依赖
apt update
apt install -y inotify-tools curl nginx base64 cron

# 2. 创建必要目录
mkdir -p /opt/subscribe
mkdir -p /var/www/subscribe

# 3. 智能配置检测
CONF_FILE="/opt/subscribe/config.ini"

if [ -f "$CONF_FILE" ]; then
    echo "检测到现有配置，正在读取..."
    DOMAIN=$(grep 'domain =' "$CONF_FILE" | cut -d'=' -f2 | tr -d ' ')
    TOKEN=$(grep 'token =' "$CONF_FILE" | cut -d'=' -f2 | tr -d ' ')
    echo "✅ 沿用域名: $DOMAIN"
    echo "✅ 沿用 Token: $TOKEN"
else
    read -p "请输入你的订阅域名 (例如 hk2.changuoo.com): " DOMAIN
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

# 4. 从 GitHub 获取核心引擎 (使用 main 分支)
echo "正在从 GitHub 获取核心引擎..."
curl -Ls https://raw.githubusercontent.com/akriamail/sub-box/main/update.sh -o /opt/subscribe/update.sh
chmod +x /opt/subscribe/update.sh

# 5. 生成 Nginx 配置
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
(crontab -l 2>/dev/null | grep -q "update.sh") || (crontab -l 2>/dev/null; echo "@reboot nohup /opt/subscribe/update.sh > /dev/null 2>&1 &") | crontab -

echo "--------------------------------------------------"
echo "✅ X-UI Sub-Box v1.0.0 (Stable) 安装成功！"
echo "管理目录: /opt/subscribe"
echo "订阅链接: https://$DOMAIN:8080/$TOKEN"
echo "--------------------------------------------------"
