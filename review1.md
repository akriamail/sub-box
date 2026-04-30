# sub-box v2.0 代码审查

> 审查范围：`services/sub-box/` 全部源码
> 审查日期：2026-04-30

---

## 严重

### 1. uninstall.sh 删除 config.ini 后再读取，导致 `rm -rf /root/cert/` — 已修复

**文件**: [lib/uninstall.sh:108-111](lib/uninstall.sh#L108)

**问题**: 卸载流程在第 100 行删除 `$SUB_BOX_DIR`（含 config.ini），然后第 108-111 行通过 grep 读取 config.ini 获取 `cert_domain`/`domain`。此时文件已不存在，变量为空，第 111 行 `rm -rf "$CERT_DIR/${cert_domain:-$domain}"` 退化为 `rm -rf /root/cert/`，删除整个证书目录。

**修复方向**: 读取配置应在删除 config.ini 之前完成，或在删除前将域名保存到临时变量。

**修复记录**: 已在执行卸载前读取并保存 `domain/cert_domain`；删除证书前校验证书域名非空，若读取失败则跳过证书删除，避免误删整个证书目录。

---

### 2. 纯字符串拼接 JSON，密码含特殊字符即炸

**文件**: [lib/install.sh:383-544](lib/install.sh#L383)

**问题**: `generate_sing_box_config()` 全程用 `cat >>` + `echo ","` 手动拼接 JSON。如果 `trojan_pass`、`vmess_uuid` 等包含 `"`、`\`、换行符，会生成非法 JSON，sing-box 启动失败。无任何转义处理。

**修复方向**: 引入 `jq` 依赖，用 `jq -n --arg key val '...'` 构建 JSON，或至少对字符串值做 `sed` 转义。

---

## 高

### 3. token 为空时订阅文件写入目标变目录，find 误删 — 已确认不成立

**文件**: [bin/update.sh:94-95](bin/update.sh#L94)

**问题**:
```bash
token_file="$WEB_DIR/$token"   # token="" → token_file="/var/www/subscribe/"
find ... -delete                # token="" → 删除所有非 index.html 文件
```
`load_config()` 若因 ini 格式问题读不到 token，会导致订阅目录被清空，所有订阅文件丢失。

**修复方向**: 使用前校验 `$token` 非空，并限定 `-delete` 的匹配范围。

**确认记录**: 当前代码已在写入订阅文件和执行 `find -delete` 前校验 token 非空：`[[ -z "$token" ]]` 时直接 `return 1`，因此当前版本不存在该误删路径。

---

### 4. `gen_uuid()` fallback 不可靠

**文件**: [lib/common.sh:54-55](lib/common.sh#L54)

**问题**: `od -x /dev/urandom | head -1` 凑 UUID 格式，不保证符合 RFC 4122 规范（version/variant 位可能错误）。连招太长，任意一段失败就出无效 UUID。

**修复方向**: 直接使用 `python3 -c 'import uuid; print(uuid.uuid4())'`。

---

### 5. 重置 sing-box 配置后不同步 config.ini — 已修复

**文件**: [lib/config.sh:427-477](lib/config.sh#L427)

**问题**: `config_singbox()` option 2 生成新密码/UUID/端口并调用 `generate_sing_box_config()`，但不更新 `config.ini`。后果：
- sing-box 用新密码运行
- `config.ini` 保留旧密码
- `update.sh` 基于旧密码生成订阅链接 → 客户端拿到失效节点

**修复方向**: 重置配置后调用 `generate_config_ini` 同步写入 config.ini。

**修复记录**: 已在重置 sing-box 配置后读取原订阅 `token/port`，调用 `generate_config_ini` 同步写回 `config.ini`，并触发订阅文件重新生成。

---

### 6. 跨 ini section 匹配

**文件**: [lib/common.sh:134-141](lib/common.sh#L134), 多处

**问题**: `load_config()` 及全仓库各处用 `grep '^key =' config.ini` 读取配置，完全不认 ini section 边界。若 `[nodes]` 段出现同名 key 会覆盖 `[common]` 的值。

**修复方向**: 用 `sed -n '/^\[common\]/,/^\[/{/^key =/p}'` 限定 section，或改用 Python `configparser`。

---

## 中

### 7. `install_sing_box()` cd 到临时目录后异常退出不清理

**文件**: [lib/install.sh:344](lib/install.sh#L344)

**问题**: `cd "$tmp_dir" || return 1` 后若 `tar` 等步骤失败，`return 1` 跳过后续 `rm -rf "$tmp_dir"`，产生临时文件残留。

**修复方向**: 用 trap 确保退出时清理，或将清理写在 return 前。

---

### 8. `sed -i` 修改 JSON 字符串

**文件**: [lib/config.sh:87-90](lib/config.sh#L87), 多处

**问题**: 用 `sed "s/\"server_name\": \".*\"/.../"` 修改 JSON 文件。域名含 `.`（regex 通配符）可能误匹配；JSON 格式化变化（换行、缩进）也会导致 sed 失败。

**修复方向**: 统一使用 `jq` 操作 JSON 文件，消除 regex 依赖。

---

### 9. fetch_ext.sh 静默忽略 base64 解码错误 — 已修复

**文件**: [bin/fetch_ext.sh:19](bin/fetch_ext.sh#L19)

**问题**: `base64 -d 2>/dev/null` 隐藏解码错误，后续只判断输出是否为空。用户无法区分"网络不通"和"格式不对"。

**修复方向**: 分开检查 curl 返回值和解码结果，分别输出不同错误信息。

**修复记录**: 已拆分为空链接跳过、curl 下载失败、Base64 解码失败、解码后内容为空四类输出，便于定位是网络问题还是订阅格式问题。

---

### 10. crontab 临时文件固定路径 — 已修复

**文件**: [lib/install.sh:973-977](lib/install.sh#L973), [lib/uninstall.sh:136-138](lib/uninstall.sh#L136)

**问题**: 使用固定路径 `/tmp/cron_tmp`，多进程并发时有竞态条件。应使用 `mktemp`。

**修复记录**: `setup_crontab()` 和卸载清理 crontab 均已改为 `mktemp` 临时文件。

---

## 低 / 风格

### 11. Reality handshake server 硬编码

[lib/install.sh:483](lib/install.sh#L483) — `www.microsoft.com:443` 写死在代码里。若该域名被墙则 Reality 不可用。建议做成可配置项。

### 12. inotifywait 主进程信号响应

[bin/update.sh:102](bin/update.sh#L102) — inotifywait 作为 update.sh 主进程运行，`pkill -f update.sh` 发 SIGTERM 时 inotifywait 可能不退出（取决于系统实现）。建议加 `-t` 超时或包装层。

### 13. refresh_clients.sh asset 正则偏宽

[bin/refresh_clients.sh:78-79](bin/refresh_clients.sh#L78) — APK/ZIP 匹配链最后 fallback 到 `\.apk$` / `\.zip$`，上游 release 若有多个同名后缀 asset 可能下错文件。

### 14. 推荐改用 jq

全仓库多次手拼/手撕 JSON（install.sh config.sh），建议统一引入 `jq` 依赖，消除全部 JSON 相关的 regex 脆弱点。
