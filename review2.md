# sub-box v2.0 变更记录

> 2026-06-01

## bin/fetch_ext.sh — 机场节点抓取重构

**旧逻辑**：按 `KEYWORD` 关键词匹配，取前 `MAX_NODES` 个，不测速。

**新逻辑**：`REGIONS` 数组配置多地区（`"台湾:1"` `"日本:1"`），每个地区对所有匹配的 endpoint 做 TCP SYN 握手测速，取延迟最低的 N 个节点。

关键改进：
- 支持多地区同时抓取
- 自动跳过 127.0.0.1 / 流量提示等非节点行
- 按 host:port 去重，避免同一 endpoint 重复测速
- 超时节点（3s）自动排除
- 延迟日志完整输出，可追踪选点依据

## lib/config.sh — config_fetch_settings() 适配

- 匹配 fetch_ext.sh 的 `REGIONS` 格式
- 交互式修改时显示示例
