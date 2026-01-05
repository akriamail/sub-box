#!/bin/bash

# ==========================================
# sub-box v1.0.4 (Git Deployment Mode)
# ==========================================

echo "--------------------------------------------------"
echo "正在初始化 sub-box 环境 (Git 模式)..."
echo "--------------------------------------------------"

# 1. 安装系统依赖
apt update
apt install -y inotify-tools curl nginx coreutils cron python3 git

# 2. 确保脚本有执行权限 (假设用户已经 git clone 到了 /opt/subscribe)
chmod +x /opt/subscribe/*.sh

# 3. 初始化私密配置文件 (如果不存在)
CONF_FILE="/opt/subscribe/config.ini"
URL_FILE="/opt/subscribe/airport_url.txt"

if [ ! -f "$CONF_FILE" ]; then
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
    echo "✅ 已生成 config.ini"
else
    DOMAIN=$(grep 'domain =' "$CONF_FILE" | cut -d'=' -f2 | tr -d ' ')
    echo "✅ 检测到现有配置，域名: $DOMAIN"
fi

[ ! -f "$URL_FILE" ] && touch "$URL_FILE" && echo "✅ 已初始化 airport_url.txt"

# 4. 配置 Nginx SSL (保持原有逻辑)
# ... (中间 Nginx 配置代码省略，建议保持你原来的逻辑) ...

# 5. 设置定时任务 (使用绝对路径)
(crontab -l 2>/dev/null | grep -v "update.sh" | grep -v "fetch_ext.sh") > /tmp/cron_tmp
echo "@reboot nohup /opt/subscribe/update.sh > /dev/null 2>&1 &" >> /tmp/cron_tmp
echo "0 3 * * * /bin/bash /opt/subscribe/fetch_ext.sh > /dev/null 2>&1" >> /tmp/cron_tmp
crontab /tmp/cron_tmp
rm /tmp/cron_tmp

# 6. 启动引擎
pkill -f update.sh
nohup /opt/subscribe/update.sh > /dev/null 2>&1 &

echo "✅ 环境配置完成！请在 airport_url.txt 填入机场链接后运行 fetch_ext.sh"
