#!/bin/bash
# ==========================================
# sub-box v2.0 — 配置修改模块
# ==========================================

config_main() {
    while :; do
        clear 2>/dev/null || true
        title "修改配置"
        echo "  1. 修改订阅域名 / 重新申请证书"
        echo "  2. 重新生成订阅 Token"
        echo "  3. 修改订阅端口"
        echo "  4. 管理订阅节点 (添加/改名/删除)"
        echo "  5. 管理机场订阅链接"
        echo "  6. 修改抓取关键词 / 最大节点数"
        echo "  7. 修改 sing-box 配置（增删协议/改端口/改密码）"
        echo "  8. 重启组件 (sing-box / nginx / update.sh)"
        echo "  9. 重新安装 sing-box"
        echo "  10. 修改 Web 手册登录密码"
        echo "  0. 返回主菜单"
        echo ""
        read -r -p "请选择 [0-10]: " choice

        case "$choice" in
            1) config_domain ;;
            2) config_regenerate_token ;;
            3) config_port ;;
            4) config_manage_nodes ;;
            5) config_manage_airport ;;
            6) config_fetch_settings ;;
            7) config_singbox ;;
            8) config_restart ;;
            9) config_reinstall_singbox ;;
            10) config_web_auth ;;
            0) return 0 ;;
            *) error "无效选择" ;;
        esac
    done
}

# ==========================================
# 1. 修改域名 / 重新申请证书
# ==========================================
config_domain() {
    title "修改域名 / 重新申请证书"

    load_config
    local current_domain="${domain:-$(grep '^domain =' "$SUB_BOX_DIR/config.ini" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')}"
    info "当前域名: $current_domain"

    read -r -p "新域名（留空不修改）: " new_domain
    [[ -z "$new_domain" ]] && new_domain="$current_domain"

    if [[ "$new_domain" != "$current_domain" ]]; then
        if confirm "是否验证 DNS 解析？"; then
            check_dns "$new_domain" || {
                warn "DNS 验证失败，是否继续？"
                confirm "继续？" "N" || return 1
            }
        fi
    fi

    if confirm "重新申请 SSL 证书？"; then
        ~/.acme.sh/acme.sh --issue -d "$new_domain" --standalone --force
        mkdir -p "$CERT_DIR/$new_domain"
        ~/.acme.sh/acme.sh --install-cert -d "$new_domain" \
            --fullchain-file "$CERT_DIR/$new_domain/fullchain.pem" \
            --key-file "$CERT_DIR/$new_domain/privkey.pem"
        if [[ $? -eq 0 ]]; then
            success "证书已更新"
        else
            error "证书申请失败"
            return 1
        fi
    fi

    # 更新 config.ini
    sed -i "s/^domain = .*/domain = $new_domain/" "$SUB_BOX_DIR/config.ini"
    sed -i "s/^cert_domain = .*/cert_domain = $new_domain/" "$SUB_BOX_DIR/config.ini"

    # 更新 nginx 配置
    local sub_port
    sub_port=$(grep '^port =' "$SUB_BOX_DIR/config.ini" | cut -d'=' -f2- | tr -d ' ')
    configure_nginx "$new_domain" "$sub_port" "$CERT_DIR/$new_domain"
    systemctl reload nginx

    # 更新 sing-box 配置
    if [[ -f "$SING_BOX_CONFIG" ]]; then
        sed -i "s/\"server_name\": \".*\"/\"server_name\": \"$new_domain\"/" "$SING_BOX_CONFIG"
        sed -i "s|\"certificate_path\": \".*\"|\"certificate_path\": \"$CERT_DIR/$new_domain/fullchain.pem\"|" "$SING_BOX_CONFIG"
        sed -i "s|\"key_path\": \".*\"|\"key_path\": \"$CERT_DIR/$new_domain/privkey.pem\"|" "$SING_BOX_CONFIG"
        systemctl restart sing-box
    fi

    success "域名已更新为 $new_domain"
    read -r -p "按回车继续..."
}

# ==========================================
# 2. 重新生成 Token
# ==========================================
config_regenerate_token() {
    title "重新生成订阅 Token"

    warn "重新生成后，现有订阅链接将立即失效！"
    warn "所有客户端需要更新订阅链接"
    echo ""

    if ! confirm "确认重新生成？"; then
        return 1
    fi

    local new_token
    new_token=$(gen_token)

    sed -i "s/^token = .*/token = $new_token/" "$SUB_BOX_DIR/config.ini"
    trigger_subscription_update

    local domain port
    domain=$(grep '^domain =' "$SUB_BOX_DIR/config.ini" | cut -d'=' -f2- | tr -d ' ')
    port=$(grep '^port =' "$SUB_BOX_DIR/config.ini" | cut -d'=' -f2- | tr -d ' ')

    success "Token 已更新！"
    info "新订阅链接: https://${domain}:${port}/${new_token}"
    read -r -p "按回车继续..."
}

# ==========================================
# 3. 修改端口
# ==========================================
config_port() {
    title "修改订阅端口"

    local current_port
    current_port=$(grep '^port =' "$SUB_BOX_DIR/config.ini" | cut -d'=' -f2- | tr -d ' ')
    info "当前端口: $current_port"

    local new_port
    new_port=$(read_input "新端口" "$current_port")
    [[ "$new_port" == "$current_port" ]] && return 0

    sed -i "s/^port = .*/port = $new_port/" "$SUB_BOX_DIR/config.ini"

    local domain cert_domain
    domain=$(grep '^domain =' "$SUB_BOX_DIR/config.ini" | cut -d'=' -f2- | tr -d ' ')
    cert_domain=$(grep '^cert_domain =' "$SUB_BOX_DIR/config.ini" | cut -d'=' -f2- | tr -d ' ')
    [[ -z "$cert_domain" ]] && cert_domain="$domain"

    configure_nginx "$domain" "$new_port" "$CERT_DIR/$cert_domain"
    systemctl reload nginx
    generate_manual_page "$domain" "$new_port" ""

    success "订阅端口已更新为 $new_port"
    read -r -p "按回车继续..."
}

# ==========================================
# 4. 管理订阅节点
# ==========================================
node_display_name() {
    local line="$1"
    local proto host port secret name
    if [[ "$line" == *"://"* ]]; then
        [[ "$line" == *"|"* ]] && echo "${line#*|}" || echo "${line##*#}"
        return
    fi
    IFS='|' read -r proto host port secret name _ <<< "$line"
    if [[ "$host" =~ ^[0-9]+$ ]]; then
        echo "$secret"
    else
        echo "$name"
    fi
}

replace_node_line() {
    local file="$1"
    local old_line="$2"
    local new_line="$3"
    awk -v old="$old_line" -v new="$new_line" 'BEGIN{done=0} $0 == old && !done {print new; done=1; next} {print}' "$file" > "${file}.tmp"
    mv "${file}.tmp" "$file"
}

delete_node_line() {
    local file="$1"
    local old_line="$2"
    awk -v old="$old_line" 'BEGIN{done=0} $0 == old && !done {done=1; next} {print}' "$file" > "${file}.tmp"
    mv "${file}.tmp" "$file"
}

rename_node_line() {
    local line="$1"
    local new_name="$2"
    local proto host port secret name

    if [[ "$line" == *"://"* ]]; then
        echo "${line%%|*}|${new_name}"
        return
    fi

    IFS='|' read -r proto host port secret name _ <<< "$line"
    if [[ "$host" =~ ^[0-9]+$ ]]; then
        echo "${proto}|${host}|${port}|${new_name}"
    else
        echo "${proto}|${host}|${port}|${secret}|${new_name}"
    fi
}

trigger_subscription_update() {
    if [[ -x "$SUB_BOX_BIN_DIR/update.sh" || -f "$SUB_BOX_BIN_DIR/update.sh" ]]; then
        bash "$SUB_BOX_BIN_DIR/update.sh" >/dev/null 2>&1 &
    fi
}

config_manage_nodes() {
    title "管理订阅节点"

    local files=("$SUB_BOX_DIR/config.ini" "$SUB_BOX_DIR/extend.ini")
    local labels=("手动" "机场")
    local nodes=()
    local node_files=()
    local i=0

    echo "当前订阅节点:"
    echo ""
    for idx in 0 1; do
        local file="${files[$idx]}"
        [[ -f "$file" ]] || continue
        while IFS= read -r line; do
            [[ "$line" =~ ^#|^\[|^$ ]] && continue
            if [[ "$line" == *"://"* || "$line" =~ ^(trojan|vmess|vless|hysteria2|hy2|ss)\| ]]; then
                i=$((i+1))
                nodes+=("$line")
                node_files+=("$file")
                echo "  $i) [${labels[$idx]}] $(node_display_name "$line")"
                echo "     $line"
            fi
        done < <(sed -n '/^\[nodes\]/,$p' "$file" 2>/dev/null)
    done

    [[ $i -eq 0 ]] && echo "  (暂无节点)"
    echo ""
    echo "  a) 添加手动节点"
    [[ $i -gt 0 ]] && echo "  r) 修改显示名"
    [[ $i -gt 0 ]] && echo "  d) 删除节点"
    echo "  0) 返回"
    echo ""

    read -r -p "请选择: " node_choice

    case "$node_choice" in
        a|A)
            add_node_interactive
            trigger_subscription_update
            ;;
        r|R)
            [[ $i -eq 0 ]] && return 0
            read -r -p "输入要改名的节点编号 [1-$i]: " edit_idx
            if [[ "$edit_idx" =~ ^[0-9]+$ ]] && (( edit_idx >= 1 && edit_idx <= i )); then
                local old_line="${nodes[$((edit_idx-1))]}"
                local file="${node_files[$((edit_idx-1))]}"
                local old_name
                old_name=$(node_display_name "$old_line")
                local new_name
                new_name=$(read_input "新的显示名" "$old_name")
                replace_node_line "$file" "$old_line" "$(rename_node_line "$old_line" "$new_name")"
                trigger_subscription_update
                success "显示名已更新"
            fi
            ;;
        d|D)
            [[ $i -eq 0 ]] && return 0
            read -r -p "输入要删除的节点编号 [1-$i]: " del_idx
            if [[ "$del_idx" =~ ^[0-9]+$ ]] && (( del_idx >= 1 && del_idx <= i )); then
                local del_line="${nodes[$((del_idx-1))]}"
                local file="${node_files[$((del_idx-1))]}"
                if confirm "确认删除 $(node_display_name "$del_line")？" "N"; then
                    delete_node_line "$file" "$del_line"
                    trigger_subscription_update
                    success "已删除节点"
                fi
            fi
            ;;
    esac

    read -r -p "按回车继续..."
}

add_node_interactive() {
    echo ""
    echo "选择协议类型:"
    echo "  1. Trojan"
    echo "  2. VMess"
    echo "  3. VLESS (Reality)"
    echo "  4. Hysteria2"
    echo "  5. Shadowsocks"
    read -r -p "请选择 [1-5]: " proto

    local prefix=""
    case "$proto" in
        1) prefix="trojan" ;;
        2) prefix="vmess" ;;
        3) prefix="vless" ;;
        4) prefix="hysteria2" ;;
        5) prefix="ss" ;;
        *) warn "无效选择" ; return 1 ;;
    esac

    local host port pass remark domain
    domain=$(grep '^domain =' "$SUB_BOX_DIR/config.ini" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')
    host=$(read_input "代理 Host/IP（留空使用本机域名）" "$domain")

    port=$(read_input "端口" "")
    [[ -z "$port" ]] && port=$(shuf -i 10000-65535 -n 1)

    pass=$(read_input "密码/UUID（回车自动生成）" "")
    [[ -z "$pass" ]] && pass=$(gen_password)

    remark=$(read_input "备注" "自建-${prefix}-${port}")

    echo "${prefix}|${host}|${port}|${pass}|${remark}" >> "$SUB_BOX_DIR/config.ini"
    success "已添加节点: ${prefix}|${host}|${port}|***|${remark}"

    # 同步到 update.sh 的 config.ini 节点池
    # 不需要额外操作，update.sh 自动读取所有 .ini
}

# ==========================================
# 5. 管理机场订阅链接
# ==========================================
config_manage_airport() {
    title "管理机场订阅"

    local url_file="$SUB_BOX_DIR/airport_url.txt"

    if [[ -f "$url_file" ]]; then
        local current_url
        current_url=$(cat "$url_file" | tr -d '\n\r ')
        info "当前机场链接: ${current_url:0:30}..."
    else
        info "当前机场链接: (未设置)"
    fi

    echo ""
    echo "  1. 修改机场订阅链接"
    echo "  2. 清空机场订阅链接"
    echo "  3. 手动触发抓取"
    echo "  0. 返回"
    echo ""

    read -r -p "请选择 [0-3]: " airport_choice

    case "$airport_choice" in
        1)
            read -r -p "请输入新订阅链接: " new_url
            echo "$new_url" > "$url_file"
            success "机场链接已更新"
            if confirm "立即触发抓取？"; then
                bash "$SUB_BOX_BIN_DIR/fetch_ext.sh"
            fi
            ;;
        2)
            if confirm "确认清空？"; then
                > "$url_file"
                success "机场链接已清空"
            fi
            ;;
        3)
            bash "$SUB_BOX_BIN_DIR/fetch_ext.sh"
            read -r -p "按回车继续..."
            ;;
    esac
}

# ==========================================
# 6. 修改抓取关键词 / 最大节点数
# ==========================================
config_fetch_settings() {
    title "修改抓取设置"

    local ext_file="$SUB_BOX_DIR/extend.ini"

    local keyword
    local max_nodes
    keyword=$(grep '^KEYWORD=' "$SUB_BOX_BIN_DIR/fetch_ext.sh" | cut -d'"' -f2)
    max_nodes=$(grep '^MAX_NODES=' "$SUB_BOX_BIN_DIR/fetch_ext.sh" | cut -d'=' -f2)

    info "当前关键词: $keyword"
    info "最大节点数: $max_nodes"

    echo ""
    local new_keyword
    new_keyword=$(read_input "新关键词（如: 台湾、香港、日本）" "$keyword")
    local new_max
    new_max=$(read_input "最大节点数" "$max_nodes")

    sed -i 's/^KEYWORD=".*"/KEYWORD="'"$new_keyword"'"/' "$SUB_BOX_BIN_DIR/fetch_ext.sh"
    sed -i 's/^MAX_NODES=[0-9]*/MAX_NODES='"$new_max"'/' "$SUB_BOX_BIN_DIR/fetch_ext.sh"

    success "已更新"

    if confirm "立即触发抓取？"; then
        bash "$SUB_BOX_BIN_DIR/fetch_ext.sh"
        read -r -p "按回车继续..."
    fi
}

# ==========================================
# 7. 修改 sing-box 配置
# ==========================================
config_singbox() {
    title "修改 sing-box 配置"

    echo "  1. 编辑 sing-box 配置文件 (vi)"
    echo "  2. 重置 sing-box 配置（重新选择协议）"
    echo "  3. 查看当前 sing-box 配置"
    echo "  0. 返回"
    echo ""

    read -r -p "请选择 [0-3]: " sb_choice

    case "$sb_choice" in
        1)
            vi "$SING_BOX_CONFIG"
            if confirm "重启 sing-box？"; then
                systemctl restart sing-box
                systemctl status sing-box --no-pager -l | head -10
            fi
            ;;
        2)
            warn "将重新生成 sing-box 配置，并同步更新 config.ini 节点"
            if ! confirm "确认重置？"; then
                return 1
            fi

            # 读取现有域名和证书路径
            local domain cert_dir
            domain=$(grep '^domain =' "$SUB_BOX_DIR/config.ini" | cut -d'=' -f2- | tr -d ' ')
            cert_domain=$(grep '^cert_domain =' "$SUB_BOX_DIR/config.ini" | cut -d'=' -f2- | tr -d ' ')
            [[ -z "$cert_domain" ]] && cert_domain="$domain"
            cert_dir="$CERT_DIR/$cert_domain"

            # 选协议
            local enable_trojan=true enable_vmess=true enable_vless=true enable_hy2=true
            read -r -p "  Trojan [Y/n]: " ans
            [[ "$ans" =~ ^[Nn] ]] && enable_trojan=false
            read -r -p "  VMess [Y/n]: " ans
            [[ "$ans" =~ ^[Nn] ]] && enable_vmess=false
            read -r -p "  VLESS+Reality [Y/n]: " ans
            [[ "$ans" =~ ^[Nn] ]] && enable_vless=false
            read -r -p "  Hysteria2 [Y/n]: " ans
            [[ "$ans" =~ ^[Nn] ]] && enable_hy2=false

            # 设置端口
            local tp=62333 vp=8443 vlp=8444 hp=8445
            read -r -p "  Trojan 端口 [62333]: " tp_ans
            [[ -n "$tp_ans" ]] && tp="$tp_ans"
            read -r -p "  VMess 端口 [8443]: " vp_ans
            [[ -n "$vp_ans" ]] && vp="$vp_ans"
            read -r -p "  VLESS 端口 [8444]: " vlp_ans
            [[ -n "$vlp_ans" ]] && vlp="$vlp_ans"
            read -r -p "  Hysteria2 端口 [8445]: " hp_ans
            [[ -n "$hp_ans" ]] && hp="$hp_ans"

            # 生成密码
            local tp_pass vp_uuid vlp_uuid hp_pass
            tp_pass=$(gen_password)
            vp_uuid=$(gen_uuid)
            vlp_uuid=$(gen_uuid)
            hp_pass=$(gen_password)

            generate_sing_box_config \
                "$enable_trojan" "$tp" "$tp_pass" \
                "$enable_vmess" "$vp" "$vp_uuid" \
                "$enable_vless" "$vlp" "$vlp_uuid" \
                "$enable_hy2" "$hp" "$hp_pass" \
                "$domain" "$cert_dir"

            local sub_token sub_port
            sub_token=$(grep '^token =' "$SUB_BOX_DIR/config.ini" | cut -d'=' -f2- | tr -d ' ')
            sub_port=$(grep '^port =' "$SUB_BOX_DIR/config.ini" | cut -d'=' -f2- | tr -d ' ')
            generate_config_ini \
                "$domain" "$sub_token" "$sub_port" \
                "$enable_trojan" "$tp" "$tp_pass" \
                "$enable_vmess" "$vp" "$vp_uuid" \
                "$enable_vless" "$vlp" "$vlp_uuid" \
                "$enable_hy2" "$hp" "$hp_pass"
            trigger_subscription_update

            systemctl restart sing-box
            success "sing-box 配置已重置，config.ini 已同步，并已重启"
            ;;
        3)
            if [[ -f "$SING_BOX_CONFIG" ]]; then
                cat "$SING_BOX_CONFIG"
            else
                error "sing-box 配置不存在"
            fi
            read -r -p "按回车继续..."
            ;;
    esac
}

# ==========================================
# 8. 重启组件
# ==========================================
config_restart() {
    title "重启组件"
    echo "  1. 全部重启"
    echo "  2. sing-box"
    echo "  3. Nginx"
    echo "  4. update.sh (订阅引擎)"
    echo "  0. 返回"
    echo ""

    read -r -p "请选择 [0-4]: " restart_choice

    case "$restart_choice" in
        1)
            systemctl restart sing-box
            systemctl restart nginx
            pkill -f "$SUB_BOX_BIN_DIR/update.sh" 2>/dev/null
            nohup "$SUB_BOX_BIN_DIR/update.sh" > /dev/null 2>&1 &
            success "全部已重启"
            ;;
        2)
            systemctl restart sing-box
            systemctl status sing-box --no-pager -l | head -5
            ;;
        3)
            systemctl restart nginx
            systemctl status nginx --no-pager -l | head -5
            ;;
        4)
            pkill -f "$SUB_BOX_BIN_DIR/update.sh" 2>/dev/null
            nohup "$SUB_BOX_BIN_DIR/update.sh" > /dev/null 2>&1 &
            success "update.sh 已重启"
            ;;
    esac
    read -r -p "按回车继续..."
}

# ==========================================
# 9. 重新安装 sing-box
# ==========================================
config_reinstall_singbox() {
    title "重新安装 sing-box"

    warn "将重新下载并安装最新版 sing-box"
    if ! confirm "确认？"; then
        return 1
    fi

    install_sing_box

    if confirm "重启 sing-box 服务？"; then
        systemctl restart sing-box
        systemctl status sing-box --no-pager -l | head -10
    fi

    read -r -p "按回车继续..."
}

# ==========================================
# 刷新客户端版本
# ==========================================
refresh_clients_main() {
    title "刷新客户端版本"

    info "将从 GitHub Releases 拉取 Android v2rayNG 与 Windows v2rayN 最新安装包"
    warn "如果服务器当前无法访问 GitHub，本次刷新会失败，但不会影响已有客户端文件"
    echo ""

    if ! confirm "开始刷新？"; then
        return 1
    fi

    bash "$SUB_BOX_BIN_DIR/refresh_clients.sh"
    local rc=$?

    local domain port cert_domain
    domain=$(grep '^domain =' "$SUB_BOX_DIR/config.ini" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')
    port=$(grep '^port =' "$SUB_BOX_DIR/config.ini" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')
    cert_domain=$(grep '^cert_domain =' "$SUB_BOX_DIR/config.ini" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')
    [[ -z "$cert_domain" ]] && cert_domain="$domain"

    if [[ -n "$domain" && -n "$port" ]]; then
        generate_manual_page "$domain" "$port" ""
        success "手册页已更新"
    fi

    if [[ $rc -eq 0 ]]; then
        success "客户端版本刷新完成"
    else
        warn "刷新脚本返回异常，请检查上方输出"
    fi
    read -r -p "按回车继续..."
}

# ==========================================
# 修改 Web 手册登录密码
# ==========================================
config_web_auth() {
    title "修改 Web 手册登录密码"

    info "用户名固定为: $WEB_AUTH_USER"
    warn "修改后访问手册页和客户端下载区需要使用新密码"
    echo ""

    local pass1 pass2
    read -r -s -p "新密码: " pass1
    echo ""
    read -r -s -p "再次输入: " pass2
    echo ""

    if [[ -z "$pass1" ]]; then
        error "密码不能为空"
        read -r -p "按回车继续..."
        return 1
    fi
    if [[ "$pass1" != "$pass2" ]]; then
        error "两次输入不一致"
        read -r -p "按回车继续..."
        return 1
    fi

    mkdir -p "$(dirname "$WEB_AUTH_FILE")"
    printf '%s:%s\n' "$WEB_AUTH_USER" "$(openssl passwd -apr1 "$pass1")" > "$WEB_AUTH_FILE"
    chmod 644 "$WEB_AUTH_FILE"

    if systemctl is-active nginx &>/dev/null; then
        systemctl reload nginx
    fi

    success "Web 手册登录密码已更新"
    read -r -p "按回车继续..."
}
