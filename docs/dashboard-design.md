# sub-box Web 控制台 — 设计草案

> 2026-06-02

## 定位

一个 Web 控制台替代 Manager CLI，server 端（hk2）部署，统一管理所有 proxy 节点、机场订阅、证书、流量。

```
浏览器 https://hk2.changuoo.com:8080/admin/
   │
   ├── 仪表盘（总览）
   ├── 代理节点管理（增删改查 + 一键安装链接）
   ├── 机场管理（测速选点 + 节点预览）
   ├── 订阅管理（Token + 链接 + 节点预览）
   └── 系统（证书 / 流量 / 日志）
```

## 架构选型

| 层 | 方案 | 理由 |
|------|------|------|
| 后端 | Python FastAPI + uvicorn | 与 monitoring-center 同栈，cluster 运维经验复用 |
| 前端 | Vue 3 + Vite SPA | 与 monitoring-center 同技术栈 |
| 通信 | REST + Server-Sent Events (SSE) | SSE 比 WebSocket 轻量，nginx 原生支持 |
| 部署 | systemd + Nginx reverse proxy | 与 Trojan/update.sh 同一台机器 |

### 为什么不用 shell CGI

- shell 处理 JSON / 并发请求太痛苦
- 仪表盘需要聚合多来源数据（多台 proxy + 机场 API），Python 天然优势
- 后续可复用 monitoring-center 的图表组件

## 一、API 设计

### 1.1 认证

`X-Dashboard-Token: <32 hex>` — 与订阅 Token 独立，存在 `/opt/subscribe/.dashboard-token`

### 1.2 代理节点

```
GET    /api/nodes              → 所有节点列表（自建 + 机场 + 已登记）
POST   /api/nodes              → 手动添加节点
PUT    /api/nodes/<id>         → 修改端口/密码/协议
DELETE /api/nodes/<id>         → 删除节点
POST   /api/nodes/<id>/speed   → 单节点测速
```

### 1.3 已登记 Proxy 客户端

```
GET    /api/agents             → 已登记 proxy 列表 + 最后心跳
GET    /api/agents/<hostname>  → 单台详情
POST   /api/agents/<hostname>/push-config  → 推送配置变更到 proxy
GET    /api/agents/<hostname>/install.sh   → 生成一键安装脚本
```

### 1.4 机场管理

```
GET    /api/airport/nodes      → 全部机场节点（按地区/延迟排序）
GET    /api/airport/test       → 全量 TCP 测速
POST   /api/airport/select     → 选中 N 个节点写入 extend.ini
PUT    /api/airport/settings   → 修改 URL / 地区 / 最大节点数
```

### 1.5 订阅

```
GET    /api/subscription       → 当前订阅链接 + Token
POST   /api/subscription/rotate-token → 重新生成 Token
GET    /api/subscription/preview     → 订阅文件预览（解码后）
```

### 1.6 系统

```
GET    /api/system/status      → sing-box/Nginx/证书/磁盘/内存
GET    /api/system/cert        → 证书域名 + 过期时间
GET    /api/system/traffic     → sing-box 流量统计（如有）
```

### 1.7 一键安装链接

```
GET /install/<token>
```

响应：shell 脚本，内容为 `curl ... | bash` 风格，自动填写 server 地址、登记 token、默认配置。proxy 主机只需：

```bash
curl -fsSL https://hk2.changuoo.com:8080/install/<token> | bash
```

## 二、前端页面

### 2.1 仪表盘

```
┌──────────────────────────────────────────────────────┐
│  sub-box 控制台                        [刷新] [设置] │
├────────────┬────────────┬────────────┬───────────────┤
│ 代理节点   │ 机场节点   │ 订阅链接   │ 系统健康      │
│  5 在线    │ 15 可选    │ 有效       │ 证书 87 天    │
│  0 离线    │ 2 已启用   │ 已用 3 月  │ sing-box ✅   │
├────────────┴────────────┴────────────┴───────────────┤
│                                                      │
│  代理节点拓扑图                                       │
│  ┌─ hk (Hysteria2 :443 UDP) ──── 在线 12h ──┐       │
│  ├─ lax (Trojan :443 TCP) ────── 在线 12h ──┤       │
│  └─ (未登记) ─── 等待新节点加入 ─────────────┘       │
│                                                      │
│  机场节点延迟分布                                     │
│  台湾 ████ 109ms   日本 ██ 61ms                      │
│  香港 ██████ 45ms  新加坡 ███ 80ms                   │
│                                                      │
│  最近事件                                            │
│  12:00  lax 心跳正常                                  │
│  11:55  订阅文件已更新 (6 节点)                       │
│  03:00  机场抓取完成 (选中 台湾1/日本1)               │
└──────────────────────────────────────────────────────┘
```

### 2.2 代理节点

```
┌──────────────────────────────────────────────────────┐
│  代理节点管理                           [+ 添加节点] │
│                                                      │
│  ┌─ 已登记 ──────────────────────────────────────┐  │
│  │ hk      Hysteria2 :443   在线 12h    [改] [删] │  │
│  │ lax     Trojan :443      在线 12h    [改] [删] │  │
│  └────────────────────────────────────────────────┘  │
│                                                      │
│  ┌─ 手动 ────────────────────────────────────────┐  │
│  │ 自建.HK │ trojan://...   [改] [删]            │  │
│  │ 自建.LAX│ trojan://...   [改] [删]            │  │
│  └────────────────────────────────────────────────┘  │
│                                                      │
│  [ 生成一键安装链接 ]                                 │
│  bash <(curl -fsSL https://hk2.../install/xxx)        │
└──────────────────────────────────────────────────────┘
```

### 2.3 机场管理

```
┌──────────────────────────────────────────────────────┐
│  机场管理                               [刷新测速]   │
│                                                      │
│  订阅源: liangxin.xyz       到期: 2026-10-28         │
│  流量: 998.99 GB / 剩余 27 天                         │
│                                                      │
│  地区     节点数    已启用   选中延迟                  │
│  ───────────────────────────────────────             │
│  台湾      2         1        109ms [改] [测速]      │
│  日本      15        1        61ms  [改] [测速]      │
│  香港      10        0        -     [+启用]          │
│  新加坡    9         0        -     [+启用]          │
│  韩国      2         0        -     [+启用]          │
│                                                      │
│  [ 应用更改 → 重新生成订阅 ]                          │
└──────────────────────────────────────────────────────┘
```

### 2.4 一键安装向导

```
┌──────────────────────────────────────────────────────┐
│  一键安装链接                                         │
│                                                      │
│  1. 选择协议: [Trojan ▾]                              │
│  2. 端口:     [443]                                   │
│  3. 密码:     [自动生成] 🔄                           │
│  4. 节点备注: [自建.XXX]                              │
│                                                      │
│  5. 有效时间:  [1小时 ▾]                              │
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │ curl -fsSL https://hk2.../install/abc123 \   │    │
│  │   | bash                                     │    │
│  └──────────────────────────────────────────────┘    │
│  [📋 复制]  [重新生成]                                │
└──────────────────────────────────────────────────────┘
```

## 三、Server 部署

### 3.1 目录结构

```
/opt/subscribe/
├── manager.sh
├── bin/
│   ├── sub-box.sh
│   ├── update.sh
│   ├── fetch_ext.sh
│   ├── refresh_clients.sh
│   ├── handle_enroll.sh     ← 新增：登记请求处理（未来阶段）
│   └── dashboard.py         ← 新增：FastAPI 后端单文件
├── web/                     ← 新增：前端静态文件
│   ├── index.html
│   ├── assets/
│   └── ...
└── ...
```

### 3.2 systemd 服务

```ini
# /etc/systemd/system/sub-box-dashboard.service
[Unit]
Description=sub-box dashboard
After=network.target

[Service]
User=root
WorkingDirectory=/opt/subscribe
ExecStart=/usr/bin/python3 bin/dashboard.py
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

### 3.3 Nginx 路由

```nginx
# /admin/ 和 /api/ → dashboard (127.0.0.1:9190)
location /admin/ {
    auth_basic "sub-box admin";
    auth_basic_user_file /opt/subscribe/web.htpasswd;
    proxy_pass http://127.0.0.1:9190;
}
location /api/ {
    proxy_pass http://127.0.0.1:9190;
}
# /install/<token> → dashboard 生成安装脚本
location /install/ {
    proxy_pass http://127.0.0.1:9190;
}
# /clients/ 和订阅 token 路径保持不变
```

## 四、实现阶段

| 阶段 | 内容 | 预估 |
|------|------|------|
| **P1 核心** | FastAPI 单文件后端 + 节点 CRUD + 机场测速 + SSE 状态 | 3-4 天 |
| **P1 核心** | Vue 前端 SPA（仪表盘 + 节点 + 机场3个页面） | 2-3 天 |
| **P2 增强** | 一键安装链接生成 + 登记流程对接 | 1-2 天 |
| **P2 增强** | 流量统计 + 图表 + 事件日志 | 1-2 天 |
| **P3 完善** | proxy 远程推送配置 + 心跳监控 | 2-3 天 |
| **P3 完善** | 多用户 + 权限 | 1 天 |

## 五、Prod 集群测试

```
┌─ prod k3s ─────────────────────────────┐
│                                         │
│  server pod (ubuntu:22.04)              │
│  ├─ sing-box (full)                     │
│  ├─ Nginx :8080                         │
│  ├─ dashboard :9190                     │
│  └─ NodePort :30808 → :8080             │
│                                         │
│  proxy pod × 2 (ubuntu:22.04)           │
│  ├─ sing-box (proxy)                    │
│  └─ 通过 server 一键安装                │
│                                         │
└─────────────────────────────────────────┘
```

## 六、关键决策待确认

1. **前端框架**：Vue 3（与 monitoring-center 同栈）还是更轻量的 vanilla JS + HTMX？
2. **dashboard.py**：单文件还是拆成 `web/` 模块？
3. **一键安装**：是通过 token 即时生成脚本，还是预生成写入文件？
4. **cluster 部署**：dashboard 是否最终要跑在 prod k3s 集群里（而不是 hk2 裸机）？
