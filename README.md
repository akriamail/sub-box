# sub-box
# 🚀 X-UI 极简订阅管理系统

一个为 `x-ui` 用户量身定制的订阅下发系统。支持智能识别证书、HTTPS 自动配置、安全 Token 隐藏路径以及保存即生效的自动化运维。

---

## ✨ 系统特性

* **一键安装**：支持通过 `curl` 远程一键安装，自动配置 Nginx 环境。
* **智能证书识别**：自动嗅探 `x-ui` 在 `/root/cert` 目录下的域名证书，支持 SSL 自动加密。
* **安全 Token**：支持自定义长路径订阅，防止被爬虫扫描或他人抓取节点。
* **实时生效**：后台服务监控配置文件，修改节点后无需重启，客户端刷新即得。
* **系统级管理**：集成 `Systemd` 服务，支持开机自启和标准 `service` 命令。

---

## 🛠️ 快速开始

在你的 VPS 终端执行以下命令进行安装：

```bash
bash <(curl -Ls [https://raw.githubusercontent.com/akriamail/sub-box/refs/heads/main/install.sh](https://raw.githubusercontent.com/akriamail/sub-box/refs/heads/main/install.sh))
