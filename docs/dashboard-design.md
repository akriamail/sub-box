# sub-box Web 控制台设计

> v2 / 2026-06-03

## 定位

Web 控制台替代大部分 Manager CLI 日常操作。server 端统一管理自建节点、agent 节点、机场订阅、系统状态、证书周期和订阅输出。

```text
浏览器 https://subbox.server.akria.net/
   |
   |-- Dashboard  总览、系统、证书、订阅概览
   |-- Nodes      手动节点增删、TCP 测速
   |-- Agents     一键安装、心跳、配置下发、metrics
   |-- Airport    机场全量扫描、测速、选点
```

## 架构

| 层 | 方案 | 当前状态 |
|---|---|---|
| 后端 | Python FastAPI 单文件 `bin/dashboard.py` | 已实现 P1/P2 原型 |
| 前端 | Vue 3 + Vite SPA | 已实现 Dashboard / Nodes / Agents / Airport |
| 部署 | Nginx reverse proxy + Python 进程 | systemd 裸机可用，Pod 测试可 nohup |
| agent | Python daemon `bin/agent.py` | 已打通登记、拉取、上报 |
| 二进制分发 | server 托管固定版本 sing-box | `bin/prepare_artifacts.sh` 已实现 |

## 认证

Dashboard API 使用：

```text
X-Dashboard-Token: <token>
```

token 存储在：

```text
/opt/subscribe/.dashboard-token
```

前端不再通过公开 `/api/token` 自动拿 token。首次访问需要手动粘贴 token，避免浏览器打开即暴露管理权限。

## API

### Dashboard 与系统

```text
GET /api/dashboard
GET /api/system/status
GET /api/system/cert
GET /api/subscription
```

用途：

- 展示 sing-box、Nginx、Dashboard 状态。
- 展示 CPU、内存、磁盘。
- 展示证书剩余天数。
- 展示订阅 token、订阅链接和节点数量。

### 手动节点

```text
GET    /api/nodes
POST   /api/nodes
DELETE /api/nodes/{id}
POST   /api/nodes/{id}/speed
```

节点写入 `config.ini`，删除采用局部删除逻辑，避免重写整个 `[nodes]` 段导致用户注释或其它配置被误伤。

### Agent 控制面

```text
GET   /api/agents
POST  /api/agents/install-token
GET   /install/{token}
POST  /api/agents/enroll
GET   /api/agents/config
POST  /api/agents/report
PATCH /api/agents/{id}/desired
```

能力：

- Dashboard 生成一键安装命令。
- agent 用一次性 token 登记。
- agent 周期拉取 desired config。
- agent 上报 CPU、内存、磁盘、网络速率、证书周期、sing-box 状态。
- server 自动生成 `state/agent_nodes.ini` 并进入订阅合成。

### 机场

```text
GET  /api/airport/nodes
POST /api/airport/test
POST /api/airport/select
```

能力：

- 拉取机场订阅。
- 解码节点。
- 执行 TCP 测速。
- 按地区选点写入 `extend.ini`。

### 安装制品

```text
GET /artifacts/sing-box/linux/amd64
GET /artifacts/sing-box/linux/arm64
GET /artifacts/sha256sums.txt
```

agent 安装时从 server 下载固定版本 sing-box，不直接访问 GitHub。

## 前端页面

### Dashboard

显示：

- 系统健康：CPU、内存、磁盘。
- 服务状态：sing-box、Nginx、Dashboard。
- 证书剩余天数。
- 订阅链接与节点数量。
- 当前模式和主要配置。

### Nodes

显示：

- `config.ini` 手动节点。
- `extend.ini` 机场节点。
- `state/agent_nodes.ini` agent 节点。
- 节点增删和 TCP 测速。

### Agents

显示：

- 生成安装命令。
- 已登记 agent 列表。
- 在线/离线、最后心跳、应用状态。
- CPU、内存、磁盘、网络 rx/tx bps。
- 证书剩余天数、sing-box 状态。

后续要补：

- desired config 表单化编辑。
- agent token rotate。
- install token 过期时间。
- 操作审计日志。

### Airport

显示：

- 机场订阅节点。
- 地区统计。
- TCP 延迟。
- 选点写入 `extend.ini`。

## 部署

### 目录结构

```text
/opt/subscribe/
|-- bin/
|   |-- dashboard.py
|   |-- agent.py
|   |-- prepare_artifacts.sh
|   |-- update.sh
|-- lib/
|   |-- install.sh
|   |-- status.sh
|   |-- uninstall.sh
|-- web/
|   |-- index.html
|   |-- assets/
|-- state/
|   |-- agents.json
|   |-- install_tokens.json
|   |-- agent_nodes.ini
|-- artifacts/
|   |-- sing-box-linux-amd64
|   |-- sing-box-linux-arm64
|   |-- sha256sums.txt
```

### Nginx 路由

```nginx
location / {
    root /opt/subscribe/web;
    try_files $uri $uri/ /index.html;
}

location /api/ {
    proxy_pass http://127.0.0.1:9190;
}

location /install/ {
    proxy_pass http://127.0.0.1:9190;
}

location /artifacts/ {
    proxy_pass http://127.0.0.1:9190;
}
```

反代时需要保留 `X-Forwarded-Proto` 和 `Host`，安装命令才能生成正确的公网 URL。

## 状态文件

```text
/opt/subscribe/.dashboard-token
/opt/subscribe/state/agents.json
/opt/subscribe/state/install_tokens.json
/opt/subscribe/state/agent_nodes.ini
/opt/subscribe/artifacts/
```

这些路径均已加入 `.gitignore`。

## 实现状态

| 阶段 | 内容 | 状态 |
|---|---|---|
| P1 | FastAPI Dashboard 基础 API | 已完成 |
| P1 | Vue Dashboard / Nodes / Airport | 已完成 |
| P1 | 机场测速选点 | 已完成 |
| P2 | 一键安装 token 与 `/install/{token}` | 已完成原型 |
| P2 | agent 登记、拉取 desired config、上报 metrics | 已完成原型 |
| P2 | server 托管 sing-box 制品 | 已完成 |
| P2 | 订阅合成读入 agent 节点 | 已完成 |
| P3 | desired config 完整表单编辑 | 待做 |
| P3 | 审计日志、token rotate、权限模型 | 待做 |
| P3 | 真实 VPS systemd 端到端验证 | 待做 |

## 测试环境

prod k3s 的 `subbox-test` namespace：

```text
subbox-server  Ubuntu 22.04 Pod
subbox-worker  Ubuntu 22.04 Pod
```

已验证：

- Dashboard 可通过 `https://subbox.server.akria.net/` 访问。
- server 可生成安装命令。
- worker 可执行安装脚本并登记。
- worker 可从 server `/artifacts/` 下载 sing-box。
- worker report 包含 CPU、内存、磁盘、网络速率、证书、sing-box 状态。
- server 生成 `state/agent_nodes.ini`，订阅解码包含 agent 节点。

限制：

- Ubuntu Pod 不是 systemd init，Dashboard 和 agent 在测试中用 nohup/直接进程方式运行。
- 真实 VPS 仍需验证 systemd service 自启动、重启恢复、证书探测和端口变更。

## 设计判断

这个设计的关键价值是把“安装”和“长期控制”分开：

- 安装只需要一次性 token。
- 长期控制依赖 agent token 和 desired state。
- agent 主动拉取，server 不持有 SSH 权限。
- sing-box 版本由 server 固定分发，减少外网依赖和版本漂移。

当前多余或暂缓的部分：

- 复杂多用户权限先不做，Dashboard token 足够支撑单人运维。
- SSE/实时事件先不做，轮询足够支撑 P2。
- 远程 shell 执行先不做，避免把系统变成隐形 SSH 面板。
