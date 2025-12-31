🚀 X-UI 极简订阅管理系统 (Full Manual)
为您量身定制的自动化、安全、系统级订阅分发方案

本项目专为使用 x-ui 面板的用户设计，通过监控配置文件实现订阅链接的自动转码与分发，支持 SSL 加密与路径隐藏。

🛠️ 安装部署
在您的 VPS 终端直接粘贴以下命令即可一键安装：

bash <(curl -Ls https://raw.githubusercontent.com/akriamail/sub-box/refs/heads/main/install.sh)

💡 安装引导说明
Token：您的“订阅密钥”，建议设置长乱码（如 v2sub_778899_xyz）。

Port：订阅服务器监听端口（默认 8080）。

智能检测：脚本会自动扫描 /root/cert。如果发现域名证书，会提示您一键开启 HTTPS 加密模式。

📝 维护指南
1. 节点管理
只需维护一个 ini 文件即可管理所有节点的增删，保存即生效：

命令：nano /opt/subscribe/config.ini

操作步骤：

将光标移动到 [nodes] 标签下方。

粘贴您从 x-ui 导出的链接（vless/vmess/trojan），一行一个。

按下 Ctrl+O 保存，Enter 确认，Ctrl+X 退出。

无需重启：后台服务实时感知修改并自动完成转码。

2. 常用管理命令
查看订阅地址：重新运行脚本选择 2 或查看 config.ini

查看实时日志：journalctl -u subscribe -f

重启监控服务：service subscribe restart

彻底卸载系统：重新运行脚本选择 3

3. 重要目录说明
配置目录：/opt/subscribe/ (包含监控脚本与 config.ini)

Web 发布目录：/var/www/subscribe/ (存放转码后的加密文件)

Nginx 配置：/etc/nginx/sites-available/subscribe

🔒 系统逻辑与安全
工作原理
实时监听：使用 inotify-tools 毫秒级监听 config.ini 的变动。

自动转码：一旦文件保存，脚本自动提取节点并进行 Base64 编码。

路径隐藏：订阅文件以您的 Token 命名，Nginx 仅允许匹配 Token 的路径访问，拒绝目录遍历。

❓ 常见问题 (FAQ)
Q: 为什么访问链接显示 403 Forbidden？ A: 系统为了安全禁止直接访问根目录。您必须访问完整的路径：http://IP:端口/您的Token

Q: 我修改了 nodes 里的节点，客户端需要重新导入吗？ A: 不需要。客户端只需要在“订阅设置”里点击“更新订阅”即可，链接地址永远不变。

Q: 开启 HTTPS 后无法连接？ A: 请确保您在 config.ini 中填写的证书路径正确，并且在云服务器后台防火墙（安全组）中放行了相应端口。

🤝 贡献与反馈
如果您觉得这个工具好用，请给一个 Star 🌟。如果您有更好的功能建议，欢迎提交 Issue 或 Pull Request！
