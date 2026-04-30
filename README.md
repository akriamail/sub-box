# sub-box v2.0

一键部署、交互式管理的全协议订阅聚合工具。基于 **sing-box** + **acme.sh**，自带 Manager 面板。

## 为什么是 v2.0？

| | v1.x | v2.0 |
|--|------|------|
| 底层 | X-UI（带 Web 面板，重） | **sing-box**（单二进制 ~20MB，无依赖） |
| 证书 | 手动申请、手动续期 | **acme.sh** 自动申请 + 自动续期 |
| 管理 | 手写 .ini、手敲命令 | **交互菜单**：安装/修改/状态/卸载 |
| 密码 | 手动设置 | **自动生成**，也可自定义 |
| 安全 | 订阅链接固定不变 | **Token 可重生成**，旧链接立即失效 |
| 域名 | 随你便 | **DNS 验证**，证书申请前先检查解析 |

## 快速安装

```bash
git clone https://github.com/akriamail/sub-box.git /opt/subscribe
bash /opt/subscribe/manager.sh
```

选择 **1. 初始化安装**，然后：

```
输入域名 → 选协议 → 默认配置（密码/UUID/Token 全自动）→ 完成
```

全程约 1-2 分钟。

## 文件结构

```
/opt/subscribe/
├── manager.sh           # 推荐入口（转发到 bin/sub-box.sh）
├── bin/
│   ├── sub-box.sh       # Manager 主程序
│   ├── update.sh        # 订阅聚合引擎（常驻进程）
│   ├── fetch_ext.sh     # 机场节点抓取
│   └── refresh_clients.sh # 客户端安装包刷新
├── lib/
│   ├── common.sh        # 公共函数（颜色、密码生成、DNS 验证）
│   ├── install.sh       # 安装全流程
│   ├── config.sh        # 配置修改（9 项子功能）
│   ├── status.sh        # 系统状态面板
│   └── uninstall.sh     # 卸载（可选保留项）
├── config.ini           # 自建节点（受 .gitignore 保护）
├── airport_url.txt      # 机场订阅链接（受 .gitignore 保护）
└── extend.ini           # 抓取到的机场节点（受 .gitignore 保护）
```

## Manager 菜单详解

### 1. 初始化安装

完整部署一个新环境，按顺序自动执行：

```
检查系统 → 安装依赖 → 安装 acme.sh → 申请证书 → 安装 sing-box
→ 生成 sing-box 配置（按所选协议）→ 配置 Nginx 订阅分发
→ 生成 config.ini → 设置 crontab → 启动服务
```

安装模式：
- **快速安装（默认）**：所有密码/UUID/Token 自动生成，端口用默认值
- **自定义安装**：逐项设置端口、密码，选择开启的协议

安装时可选 DNS 验证，检查域名是否已解析到本机。

### 2. 修改配置

| # | 功能 | 说明 |
|---|------|------|
| 1 | 修改域名 / 重新申请证书 | 同步更新 Nginx 和 sing-box 配置 |
| 2 | 重新生成订阅 Token | 旧 Token 立即失效，客户端需更新 |
| 3 | 修改订阅端口 | 更新 Nginx 监听端口 |
| 4 | 管理订阅节点 | 自建/远端代理/机场抽取节点的添加、修改显示名、删除 |
| 5 | 管理机场订阅链接 | 修改 airport_url.txt，可触发立即抓取并写入 extend.ini |
| 6 | 修改抓取关键词 / 最大节点数 | 默认"台湾"、2 个 |
| 7 | 修改 sing-box 配置 | 编辑 JSON / 重置协议 / 查看配置 |
| 8 | 重启组件 | sing-box / Nginx / update.sh |
| 9 | 重新安装 sing-box | 下载最新版 |

主菜单还提供 **刷新客户端版本**，会从 GitHub Releases 拉取 Android v2rayNG APK 与 Windows v2rayN ZIP，保存到 Nginx 的 `/clients/` 目录，并刷新首页手册里的本地下载链接。

### 3. 查看状态

展示系统资源、sing-box 运行状态和监听端口、证书信息及过期时间、自建节点和机场节点数量、订阅链接、关键进程状态。

### 4. 卸载

二次确认后才执行，可选保留 SSL 证书、sing-box 二进制、acme.sh。

## 协议默认配置

| 协议 | 默认端口 | 认证 |
|------|---------|------|
| Trojan | 443 | 16 位随机密码 |
| VMess | 8443 | UUID v4 |
| VLESS + Reality | 8444 | UUID + Reality Key Pair |
| Hysteria2 | 8445 | 16 位随机密码 |

各协议端口均可自定义，密码/UUID 自动生成或手动输入。

## 订阅安全

订阅链接格式：`https://sub.akria.net:8080/{32位Token}`

- Token 32 位随机 hex，暴力破解不可行
- 菜单 2 可随时 **重新生成 Token**，旧链接立即失效
- `config.ini`、`airport_url.txt`、`extend.ini` 均受 `.gitignore` 保护，不会上传 GitHub

建议：定期更换 Token（如每月一次）。

## 节点管理

节点分两类保存：

- `config.ini`：自建节点、手动添加的远端代理节点
- `extend.ini`：从机场订阅抽取的节点

管理菜单可统一展示两类节点，支持修改客户端里显示的名称。手动添加节点时，如果代理主机不是本机，可以填写实际 Host/IP；留空则默认使用订阅域名。

## 客户端下载镜像

Nginx 首页是客户端使用手册，包含：

- iOS 小火箭 Shadowrocket 使用说明（App Store 安装）
- macOS 小火箭 Shadowrocket 使用说明（Mac App Store 安装）
- Android v2rayNG 本地 APK 下载与使用说明
- Windows v2rayN 本地 ZIP 下载与使用说明

Android 和 Windows 用户可能在首次配置前无法访问 GitHub，所以管理器支持把安装包下载到服务器本地：

```bash
bash /opt/subscribe/bin/refresh_clients.sh
```

或在 Manager 主菜单选择 **刷新客户端版本**。刷新后文件会保存到 `/var/www/subscribe/clients/`，首页会自动显示当前镜像版本。

## 端口规划

| 端口 | 用途 |
|------|------|
| 80 | acme.sh HTTP 验证（临时） |
| 443 | Trojan 入站 |
| 8080 | 订阅分发（Nginx HTTPS） |
| 8443 | VMess 入站 |
| 8444 | VLESS+Reality 入站 |
| 8445 | Hysteria2 入站 |

## 系统要求

- OS：Ubuntu 22.04+ / Debian 11+
- 架构：amd64 / arm64
- 依赖：安装时自动安装 curl、wget、nginx、acme.sh、sing-box

## Changelog

### v2.0（2025-04）

- 重构为交互式 Manager（安装/修改/状态/卸载）
- X-UI → sing-box，大幅降低资源占用
- 集成 acme.sh 自动证书管理
- 新增 DNS 验证、Token 重生成、节点管理
- 默认密码/UUID/Token 自动生成，支持自定义
- 新增安装概要预览，确认后才执行

### v1.x

- 基于 X-UI 的订阅聚合引擎
- inotify 实时监控配置变更
- Base64 订阅文件分发
- crontab 每日自动抓取机场节点
