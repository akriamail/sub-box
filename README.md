# sub-box v1.0.4

基于 X-UI 的全协议订阅聚合管理工具。

## 🚀 特色功能
* **全协议支持**: 自动聚合 VLESS, VMESS, Hysteria2, Trojan 等节点。
* **隐私隔离**: 机场订阅链接存放在本地 `.txt`，永不上传，保护隐私。
* **自动化**: 每天凌晨自动同步机场节点，自动更新订阅文件。
* **一键部署**: 支持 Nginx 反向代理与 SSL 自动配置。

## 📦 安装方法
\`\`\`bash
bash <(curl -Ls https://raw.githubusercontent.com/akriamail/sub-box/main/install.sh)
\`\`\`

## 🛠️ 目录说明
* \`config.ini\`: 自建节点配置
* \`airport_url.txt\`: 机场订阅链接（需手动创建）
* \`extend.ini\`: 自动抓取的机场节点
