#!/bin/bash
# ==========================================
# 项目：X-UI 订阅管理系统 (Modular Version)
# 版本：v1.01
# 仓库：akriamail/sub-box
# ==========================================

# --- 自动化配置参数 ---
GH_USER="akriamail"
GH_REPO="sub-box"
GH_BRANCH="v1.01-dev"

echo "--------------------------------------------------"
echo "正在安装 X-UI 订阅管理 v1.01 (模块化开发版)..."
echo "--------------------------------------------------"

# 1. 环境准备
apt update && apt install -y nginx inotify-tools curl

# 2. 目录初始化
mkdir -p /opt/subscribe
mkdir -p /var/www/subscribe

# 3. 配置交互
read -p "请输入你的订阅域名 (例如 hk2.changuoo.com): " DOMAIN
TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)

# 4. 生成初始 config.ini
if [ ! -f /opt/subscribe/config.ini ]; then
cat > /opt/subscribe/config.ini <<EOF
[common]
domain = $DOMAIN
token = $TOKEN
port = 8080
cert_path = /root/cert/$DOMAIN/fullchain.pem
key_path = /root/cert/$DOMAIN/privkey.pem

[nodes]
# 格式示例：vmess://...|香港01
# 你可以在下方粘贴你的节点链接
EOF
fi

# 5. 【核心逻辑】从 GitHub 下载独立的 update.sh 引擎
echo "正在从 GitHub 获取核心引擎..."
UPDATE_URL="https://raw.githubusercontent.com/$GH_USER/$GH_REPO/$GH_BRANCH/update.sh"
curl -Ls "$UPDATE_URL" -o /opt/subscribe/update.sh

if [ ! -f /opt/subscribe/update.sh ]; then
    echo "❌ 错误：无法从 GitHub 下载 update.sh"
    echo "请检查分支 $GH_BRANCH 中是否存在 update.sh 文件"
    exit 1
fi

chmod +x /opt/subscribe/update.sh

# 6. 自动化配置 Nginx
cat > /etc/nginx/sites-available/subscribe <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 8080 ssl;
    server_name $DOMAIN;

    ssl_certificate /root/cert/$DOMAIN/fullchain.pem;
    ssl_certificate_key /root/cert/$DOMAIN/privkey.pem;

    location / {
        root /var/www/subscribe;
        index index.html;
        try_files \$uri \$uri/ =404;
    }
}
EOF

ln -sf /etc/nginx/sites-available/subscribe /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

# 7. 启动后台监控进程
pkill -f update.sh
nohup /opt/subscribe/update.sh > /dev/null 2>&1 &

echo "--------------------------------------------------"
echo "✅ v1.01 安装成功！"
echo "管理目录: /opt/subscribe"
echo "订阅链接: https://$DOMAIN:8080/$TOKEN"
echo "提示: 编辑 /opt/subscribe/config.ini 即可自动更新订阅"
echo "--------------------------------------------------"
