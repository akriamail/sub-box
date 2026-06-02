# 节点登记同步系统 — 需求文档

> 草案 v1 / 2026-06-01

## 愿景

server 一台（hk2 full 模式），多台 proxy 从 server 拿登记 token 自动推送节点信息，server 自动生成订阅。改密码、改端口、改域名后自动同步。

```
                ┌─────────────────────┐
   proxy lax ──▶│  POST /enroll       │
   (trojan)     │  X-Enroll-Token: x  │
                │                     │──▶ 写入 config.ini [nodes]
   proxy hk ───▶│  Nginx :8080        │──▶ 触发 update.sh
   (hysteria2)  │  (hk2 full 模式)    │──▶ 订阅文件重新生成
                └─────────────────────┘
```

## 一、登记流程

```
┌─ Server (hk2) ─┐                   ┌─ Proxy (lax/hk) ─┐
│  1. 生成 Token  │                   │                   │
│                 │  2. 安装时输入    │                   │
│                 │◀── Token + URL ──│ 3. 安装完成后     │
│                 │                   │    POST 节点信息  │
│  4. 写入 nodes  │                   │                   │
│  5. 更新订阅    │                   │                   │
│                 │  6. 后续变更      │                   │
│                 │◀── POST 同步 ────│ 端口/密码变更     │
└─────────────────┘                   └───────────────────┘
```

## 二、API 设计

### 登记端点

```
POST /enroll
```

**Headers**：

| Header | 说明 |
|--------|------|
| `X-Enroll-Token` | 32 位 hex 登记令牌 |
| `X-Node-Host` | 主机名（如 lax） |

**Body**（application/x-www-form-urlencoded）：

| 字段 | 必填 | 示例 |
|------|------|------|
| `action` | ✅ | `register` / `update` / `heartbeat` |
| `domain` | ✅ | `lax.akria.net` |
| `protocol` | ✅ | `trojan` |
| `port` | ✅ | `443` |
| `password` | * | `z1a2q3W4`（trojan/hy2） |
| `uuid` | * | `xxx-xxx-xxx`（vmess/vless） |
| `remark` | | `自建.LAX.AI.only` |
| `pubkey` | | Reality 公钥（vless） |
| `node_uri` | | 完整 URI（与字段模式互斥） |

两种提交模式：
- **字段模式**：逐个传 domain/protocol/port 等，server 拼成节点 URI
- **URI 模式**：只传 `node_uri` 和 `remark`，server 直接写入

### 响应

```json
{"ok": true, "action": "registered", "node_count": 6}
{"ok": true, "action": "updated", "node_count": 6}
{"ok": false, "error": "invalid token"}
```

### 心跳

```
POST /enroll
X-Enroll-Token: xxx
action=heartbeat
```

Server 记录心跳时间戳，不修改节点配置。Manager 面板可查看各节点最后心跳。

## 三、Server 端改动

### 3.1 登记令牌

```
/opt/subscribe/.enroll-token    32位hex，manager 可重生成
/opt/subscribe/.enroll-state    节点状态文件（hostname → 最后心跳）
```

### 3.2 Nginx 配置

`/enroll` 路径不收 Basic Auth 限制，但需要验 `X-Enroll-Token`：

```nginx
location /enroll {
    # 由 shell CGI 处理，内部验 token
    fastcgi_pass unix:/var/run/enroll.sock;  # 或直接 proxy_pass
}
```

或者更简单：Nginx 直接 `proxy_pass` 给一个本地 fastapi/flask 小服务，由它验 token、写 ini、触发 update.sh。

### 3.3 处理逻辑（`bin/handle_enroll.sh` 或 Python）

1. 读 `X-Enroll-Token`，比对 `.enroll-token`
2. 验证 `action` 参数
3. `register`：按 hostname 去重写入 config.ini `[nodes]`
4. `update`：按 hostname 找到旧行，替换
5. `heartbeat`：更新 `.enroll-state` 时间戳
6. 触发 `update.sh`（touch config.ini 触发 inotifywait）

### 3.4 Manager 菜单新增

```
7. 管理已登记节点
   ├─ 1. 查看登记列表（hostname / 域名 / 协议 / 最后心跳）
   ├─ 2. 查看单节点详情
   ├─ 3. 删除登记节点
   ├─ 4. 重新生成登记 Token（旧 Token 立即失效）
   └─ 0. 返回
```

### 3.5 字段/URI 写入格式

写入 `config.ini` 的 `[nodes]` 段：

```
# 格式: 链接|备注  #enrolled=<hostname> <timestamp>
trojan://xxx@lax.akria.net:443...|自建.LAX.AI.only  #enrolled=lax 2026-06-01T12:00:00Z
```

`#enrolled=` 注释用于去重和状态追踪，不影响 `update.sh` 解析（`#` 后的内容被忽略）。

## 四、Proxy 端改动

### 4.1 安装流程

```
域名 → 协议 → 端口/密码 → 确认
   │
   ├─ "是否登记到订阅服务器？[Y/n]"
   │     ├─ 服务器地址: [hk2.changuoo.com:8080]
   │     ├─ 登记 Token:  [粘贴]
   │     └─ 节点备注:    [自建.LAX.AI.only]
   │
   └─ 安装完成后 → POST /enroll
```

### 4.2 配置变更自动同步

```bash
# lib/config.sh config_proxy_* 函数末尾加：
if [[ -f "$SUB_BOX_DIR/.enroll-server" ]]; then
    post_enrollment "update"
fi
```

### 4.3 本地状态

```
/opt/subscribe/.enroll-server   服务器地址（如 hk2.changuoo.com:8080）
/opt/subscribe/.enroll-token    登记 Token（从 server 拿到的那份）
```

## 五、安全

- 登记 Token 通过 Manager 菜单手动输入，不落 `.gitignore`（已在 gitignore 中 `*.ini` `*.txt`，token 文件同理）
- Token 支持随时重生成，旧 Token 立即失效
- 建议后续加 IP 白名单（仅允许已知 proxy IP）
- 通信走 HTTPS（server 已有 SSL 证书）

## 六、测试计划

### prod 集群 Ubuntu Pod 测试

```
┌─ prod k3s ──────────────────────────┐
│                                      │
│  ┌─────────────────────┐             │
│  │ sub-box-server      │             │
│  │ image: ubuntu:22.04 │             │
│  │ + sub-box full 模式 │             │
│  │ NodePort :30808     │             │
│  └─────────────────────┘             │
│              ▲                       │
│              │ POST /enroll          │
│  ┌───────────┴─────────┐             │
│  │ sub-box-client      │             │
│  │ image: ubuntu:22.04 │             │
│  │ + sub-box proxy 模式│             │
│  └─────────────────────┘             │
│                                      │
└──────────────────────────────────────┘
```

**测试步骤**：

1. 两个 Ubuntu Pod，分别 `apt update && apt install curl git`
2. Server Pod 跑 `manager.sh` → full 模式安装
3. Client Pod 跑 `manager.sh` → proxy 模式安装，输入 server 地址和登记 token
4. 验证：查看 server 的 config.ini 是否自动新增了 client 节点
5. 测试：client 改密码 → 验证 server 是否自动同步
6. 测试：删除登记节点 → client 重新登记

### Pod manifest（参考）

```yaml
# manifests/apps/sub-box-test/server.yaml
apiVersion: v1
kind: Pod
metadata:
  name: sub-box-server
  namespace: default
  labels:
    app: sub-box-server
spec:
  containers:
  - name: ubuntu
    image: ubuntu:22.04
    command: ["sleep", "infinity"]
    ports:
    - containerPort: 8080
      name: enroll
---
apiVersion: v1
kind: Service
metadata:
  name: sub-box-server
spec:
  type: NodePort
  selector:
    app: sub-box-server
  ports:
  - port: 8080
    nodePort: 30808
```

## 七、实现阶段

| 阶段 | 内容 | 优先级 |
|------|------|--------|
| P1 | Server 端 `.enroll-token` + Nginx `/enroll` 端点 + 写入逻辑 | 核心 |
| P1 | Proxy 端安装时登记流程 + 安装后 POST | 核心 |
| P2 | Server Manager「管理已登记节点」面板 | 面板 |
| P2 | Proxy 配置变更自动同步 | 自动化 |
| P2 | 心跳机制 + 状态展示 | 可观测 |
| P3 | Prod 集群 Pod 测试 | 验证 |
| P3 | IP 白名单 | 安全加固 |
