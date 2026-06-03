# Agent 登记与受控安装设计

> v2 / 2026-06-03

## 目标

server 端新增一台 agent 时，生成一条带一次性 token 的安装命令。把命令 SSH 粘贴到 agent 主机后，agent 自动安装受控系统、登记到 server、拉取配置并上报状态；后续不再需要 SSH 到 agent，端口、协议、密码、订阅节点和基础监控都由 server 控制台统一管理。

```text
Dashboard 生成 install token
        |
        v
curl -fsSL https://server/install/<token> | bash
        |
        v
agent 下载 server 托管的 sing-box + agent.py
        |
        v
POST /api/agents/enroll 换长期 agent token
        |
        v
GET /api/agents/config 拉 desired config
        |
        v
POST /api/agents/report 上报运行状态
```

## 模型选择

当前采用 **agent 主动拉取模型**：

- server 不 SSH 到 agent，也不保存 agent 的 SSH 凭据。
- agent 周期访问 server，适合 NAT、防火墙后主机。
- server 只保存 desired state；agent 自己负责应用配置和重启 sing-box。
- 安装时只使用一次性 install token，登记后换取长期 agent token。

这比旧草案里的 `/enroll` 表单同步更稳：server 可以统一管理 desired config、metrics、订阅合成和安装二进制版本。

## 安装流程

### 1. server 生成安装 token

```http
POST /api/agents/install-token
X-Dashboard-Token: <dashboard-token>
```

请求体示例：

```json
{
  "name": "worker2",
  "protocol": "vmess",
  "listen_port": 8443,
  "domain": "subbox.worker.akria.net"
}
```

响应包含：

```json
{
  "token": "<one-time-token>",
  "install_url": "https://subbox.server.akria.net/install/<token>",
  "command": "curl -fsSL https://subbox.server.akria.net/install/<token> | bash"
}
```

### 2. agent 执行安装命令

agent 主机上只需要执行：

```bash
curl -fsSL https://subbox.server.akria.net/install/<token> | bash
```

脚本完成：

1. 安装 Python venv、curl、ca-certificates 等基础依赖。
2. 从 server `/artifacts/` 下载固定版本 `sing-box`，不直接访问 GitHub。
3. 安装 `bin/agent.py`。
4. 写入本机初始状态。
5. 在 systemd 环境创建并启动 `sub-box-agent.service`。
6. 在非 systemd 测试容器内降级为直接进程模式。

### 3. agent 登记

```http
POST /api/agents/enroll
X-Install-Token: <one-time-token>
```

agent 提交 hostname、arch、os、版本等信息。server 校验一次性 token 后返回：

```json
{
  "agent_id": "worker2",
  "agent_token": "<long-lived-token>",
  "desired": {
    "protocol": "vmess",
    "listen_port": 8443,
    "domain": "subbox.worker.akria.net"
  }
}
```

一次性 token 登记后标记为 used，不再重复使用。

### 4. agent 拉取 desired config

```http
GET /api/agents/config
X-Agent-Id: worker2
X-Agent-Token: <long-lived-token>
```

server 返回 revision 与 desired config。agent 发现 revision 变化后重写：

```text
/etc/sing-box/config.json
```

并重启 sing-box。

### 5. agent 上报状态

```http
POST /api/agents/report
X-Agent-Id: worker2
X-Agent-Token: <long-lived-token>
```

上报内容包括：

- CPU 使用率与负载。
- 内存、磁盘使用率。
- 网络 rx/tx 总量和 bps 速率。
- sing-box 运行状态与版本。
- TLS 证书剩余天数、证书域名。
- last_apply_ok / last_apply_error。
- 当前 applied revision。

server 根据 report 自动刷新 `state/agent_nodes.ini`，订阅聚合时会读入该文件。

## API 一览

| API | 调用方 | 说明 |
|---|---|---|
| `POST /api/agents/install-token` | Dashboard | 生成一次性安装 token 与命令 |
| `GET /install/{token}` | agent shell | 返回安装脚本 |
| `POST /api/agents/enroll` | agent | 使用 install token 换长期凭据 |
| `GET /api/agents/config` | agent | 拉取 desired config |
| `POST /api/agents/report` | agent | 上报 metrics 和应用结果 |
| `PATCH /api/agents/{id}/desired` | Dashboard | 修改端口、协议、密码、域名等 desired state |

## 状态文件

server：

```text
/opt/subscribe/state/install_tokens.json  # 一次性安装 token
/opt/subscribe/state/agents.json          # agent desired/reported 状态
/opt/subscribe/state/agent_nodes.ini      # 订阅合成用节点
```

agent：

```text
/opt/subscribe/state/agent.json           # agent_id、agent_token、server_url、revision
/etc/sing-box/config.json                 # 当前 sing-box 配置
```

这些文件均不进入 Git。

## server 托管 sing-box

server 端固定准备 sing-box 版本，agent 从 server 下载：

```bash
bash /opt/subscribe/bin/prepare_artifacts.sh
```

分发路径：

```text
/artifacts/sing-box/linux/amd64
/artifacts/sing-box/linux/arm64
/artifacts/sha256sums.txt
```

这样 agent 安装不依赖 GitHub 可达性，也避免不同 agent 自动装到不同 sing-box 版本。

## 订阅同步

`bin/update.sh` 会读取：

```text
config.ini
extend.ini
state/agent_nodes.ini
```

因此 agent 成功登记和上报后，server 会把 agent 节点合成进订阅文件。Dashboard 修改 desired config 后，agent 应用成功并上报，订阅端随之更新。

## 安全边界

- install token 一次性使用，建议设置过期时间。
- agent token 长期保存，仅用于该 agent。
- Dashboard token 与订阅 token 分离。
- `/install/` 和 `/artifacts/` 对安装流程开放，但 sensitive state 不暴露。
- 后续可加：install token TTL、agent token rotate、IP allowlist、审计日志。

## 测试记录

2026-06-03 在 prod k3s 的 `subbox-test` namespace 验证：

- server：`subbox-server`，域名 `subbox.server.akria.net`。
- worker：`subbox-worker`，域名 `subbox.worker.akria.net`。
- server 已能生成安装命令。
- worker 已通过 `/install/<token>` 安装，sing-box 从 server `/artifacts/` 下载。
- worker 在 Pod 非 systemd 环境下使用进程模式启动 agent。
- server 收到 worker report，包含 CPU、内存、磁盘、网络、证书、sing-box 状态。
- `state/agent_nodes.ini` 已生成，订阅解码后包含 server 节点和 worker 节点。

测试 Pod 不是真实 systemd init 环境，systemd service 安装路径仍需在真实 Ubuntu/Debian VPS 上再做一次端到端验证。
