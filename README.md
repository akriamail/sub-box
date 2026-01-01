# 🚀 X-UI Sub-Box v1.0.1 (Stable)

A lightweight, automated subscription management tool for X-UI. It transforms raw node links into customized, clean, and Shadowrocket-compatible subscription feeds.

## ✨ Key Features

- 🛠 **Deep Protocol Rewriting**: Automatically decodes VMess Base64 data to modify the internal `ps` field for precise node naming.
- ⚡ **Real-time Sync**: Leverages Linux `inotify` for millisecond-level synchronization when the configuration changes.
- 🔒 **Secure Access**: Supports SSL encryption and uses randomized Tokens to hide subscription paths from scanners.
- 🧹 **Pure Output**: Filters out non-protocol lines (domains, tokens, etc.) to provide a clean Base64 subscription stream.
- 🚀 **One-Click Deployment**: Automated installation of Nginx, dependencies, and systemd service setup.

## 📥 Quick Installation

Run the following command on your Linux server:

```bash

bash <(curl -Ls https://raw.githubusercontent.com/akriamail/sub-box/main/install.sh)

```

## 📥 快速安装

在你的 Linux 服务器上运行以下指令：

你需要先安装X-UI ，并设置好panel的证书

然后 在你的 Linux 服务器上运行以下指令:

```bash

bash <(curl -Ls https://raw.githubusercontent.com/akriamail/sub-box/main/install.sh)

```

## ⚙️ 使用说明

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

🔗 订阅链接格式```bash https://你的域名:8080/你的Token```

🛡 维护说明
-引擎状态检查：```bash ps -ef | grep update.sh ```

-查看输出结果：```bash cat /var/www/subscribe/你的Token | base64 -d ```

-日志查看：```bash /opt/subscribe/update.sh ```已配置为后台运行。
