# 🚀 X-UI Sub-Box v1.0.1 (Stable)

这是一个为 X-UI 打造的轻量级、自动化订阅管理工具。它能将你杂乱的节点链接转换成带自定义备注的、符合 Shadowrocket (小火箭) 规范的订阅源。

## ✨ 核心特性

- 🛠 **深度协议重写**：自动解包 VMess 的 Base64 数据，修改内部 `ps` 字段，确保小火箭显示精准备注。
- ⚡ **毫秒级同步**：采用 Linux `inotify` 异步监听技术，修改配置后订阅即刻生效。
- 🔒 **安全加固**：支持 SSL 加密访问，通过随机 Token 隐藏订阅路径，防探测。
- 🧹 **纯净输出**：自动过滤配置文件中的非协议行（如域名、Token 等），输出纯净的 Base64 订阅流。
- 🚀 **一键部署**：全自动安装 Nginx、依赖包并配置开机自启。

## 📥 快速安装

在你的 Linux 服务器上运行以下指令：

你需要先安装X-UI ，并设置好panel的证书，通常证书

### 🚀 快速安装


在你的 Linux 服务器上运行以下指令：

```bash

bash <(curl -Ls https://raw.githubusercontent.com/akriamail/sub-box/main/install.sh)

```

⚙️ 使用说明

安装完成后，编辑配置文件：
```bash
vi /opt/subscribe/config.ini
```
在 [nodes] 区域下方添加你的节点链接，使用 | 分隔备注：

```bash

vmess://xxxx...|香港-01机房
trojan://xxxx...|日本-原生IP
```

保存退出，你的订阅链接已自动更新！

🔗 订阅链接格式
https://你的域名:8080/你的Token

🛡 维护说明
引擎状态检查：ps -ef | grep update.sh

查看输出结果：cat /var/www/subscribe/你的Token | base64 -d

日志查看：/opt/subscribe/update.sh 已配置为后台运行。
