# sub-box
这份 README.md 采用了 GitHub 上最流行的排版方式，包含了从安装、使用到原理的完整说明。你可以直接复制下面的 Markdown 内容，粘贴到你 GitHub 仓库的 README.md 文件中。🚀 X-UI 极简订阅管理系统一个为 x-ui 用户量身定制的订阅下发系统。支持智能识别证书、HTTPS 自动配置、安全 Token 隐藏路径以及保存即生效的自动化运维。✨ 系统特性一键安装：支持通过 curl 远程静默或交互式安装，自动配置 Nginx 环境。智能证书识别：自动嗅探 x-ui 在 /root/cert 目录下生成的域名证书，支持 SSL 自动加密。安全 Token：支持自定义订阅路径，防止被爬虫扫描或他人恶意抓取节点。实时生效：后台服务实时监控配置文件，修改节点后无需重启，客户端刷新即可获取最新配置。系统级管理：集成 Systemd 服务，支持开机自启和标准 service 命令管理。🛠️ 快速开始在你的 VPS 终端执行以下命令进行安装：Bashbash <(curl -Ls https://raw.githubusercontent.com/akriamail/sub-box/refs/heads/main/install.sh)
安装过程说明：设置 Token：这将是你的订阅路径（如设置 myvless，则路径为 /myvless）。设置端口：订阅服务器监听的端口（默认 8080）。证书确认：脚本会自动扫描 x-ui 证书，若发现域名证书会提示你是否开启 HTTPS。📝 维护指南1. 如何更新节点系统安装完成后，你只需维护一个简单的配置文件即可：Bashnano /opt/subscribe/config.ini
在 [nodes] 下方粘贴你从 x-ui 导出的 vless://、vmess:// 或 trojan:// 链接（一行一个）。提示：保存并退出后，系统会自动完成 Base64 转码，无需手动重启。2. 常用管理命令命令说明service subscribe start启动订阅监控服务service subscribe stop停止订阅监控服务service subscribe restart重启订阅监控服务service subscribe status查看服务运行状态journalctl -u subscribe -f查看实时更新日志3. 如何修改配置（换端口或Token）直接修改配置文件中的 [settings] 部分：Ini, TOML[settings]
token = 新的Token
port = 新的端口
cert_path = /路径/to/cert
key_path = /路径/to/key
修改完成后，建议执行 service subscribe restart 以确保 Nginx 配置同步更新。🔒 安全性建议定期更换 Token：在 config.ini 中修改 Token 可以即时失效旧链接。开启 HTTPS：强烈建议配合域名和证书使用，防止订阅内容在传输过程中被干扰。防火墙策略：请确保在云服务商的安全组中放行了你设置的端口（TCP）。📂 文件结构说明/opt/subscribe/：系统核心目录（包含脚本与配置）。/var/www/subscribe/：订阅文件分发目录（由 Nginx 托管）。/etc/systemd/system/subscribe.service：系统服务定义文件。
