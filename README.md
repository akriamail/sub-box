# sub-box v1.0.4 🚀

基于 X-UI 的全协议订阅聚合管理工具，专为高性能与隐私安全设计。

## 🌟 核心特性
* **全协议支持**: 自动聚合 VLESS, VMESS, Hysteria2, Trojan 等主流协议。
* **隐私隔离 (Plan B)**: 机场订阅链接存储于本地私密文件 \`airport_url.txt\`，永不上传 GitHub，物理级防泄密。
* **自动化运维**: 
    * **实时更新**: 内置 \`inotify-tools\` 监控，编辑 \`config.ini\` 或 \`extend.ini\` 后订阅**秒级自动生效**。
    * **定时抓取**: 每天凌晨自动抓取、筛选并更新机场节点。
* **一键部署**: 集成 Nginx SSL 自动配置，实现安全的 HTTPS 订阅分发。

## 📦 安装方法 (推荐)

采用 Git 模式安装，方便后续一键升级：

```bash
# 1. 克隆代码到指定目录
git clone [https://github.com/akriamail/sub-box.git](https://github.com/akriamail/sub-box.git) /opt/subscribe

# 2. 进入目录并运行初始化脚本
cd /opt/subscribe
bash install.sh
```
## 🛠️ 文件结构说明
* **update.sh**: 聚合引擎核心，后台常驻进程，负责监控文件变动并生成订阅。
* **fetch_ext.sh**: 外部抓取工具，负责从机场获取并筛选节点。
* **airport_url.txt**: (需手动创建) 存放你的机场订阅原始链接，受 \`.gitignore\` 保护。
* **config.ini**: 存放你的自建节点信息。
* **extend.ini**: 存放自动抓取到的机场节点。


## ⚙️ 运维指南
### 1. 确认引擎状态
使用 \`ps -ef | grep update.sh\` 查看进程。若修改了脚本逻辑，请重启引擎：
\`\`\`bash
pkill -f update.sh && nohup /opt/subscribe/update.sh > /dev/null 2>&1 &
\`\`\`

### 2. 手动触发抓取
\`\`\`bash
bash /opt/subscribe/fetch_ext.sh
\`\`\`

## 🛡️ 安全提示
本项目默认通过 \`.gitignore\` 忽略所有 \`.ini\`、\`.txt\`、\`.bak\` 文件，确保您的订阅链接和节点隐私不外泄。
