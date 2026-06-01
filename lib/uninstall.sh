#!/bin/bash
# ==========================================
# sub-box v2.0 — 卸载模块
# ==========================================

uninstall_main() {
    local mode
    mode=$(detect_mode)

    title "卸载 sub-box"

    echo -e "${RED}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           这是一个破坏性操作！                  ║${NC}"
    echo -e "${RED}║  将停止所有相关服务并删除配置文件               ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════╝${NC}"
    echo ""

    # 列出将要卸载的组件
    echo "将执行以下操作:"
    echo "  1. 停止 sing-box 服务并禁用开机自启"
    if [[ "$mode" == "full" ]]; then
        echo "  2. 停止 nginx 订阅站点（保留 nginx 本身）"
        echo "  3. 停止 update.sh 进程"
        echo "  4. 删除 ${SUB_BOX_DIR} 目录"
        echo "  5. 删除 ${WEB_DIR} 订阅文件目录"
        echo "  6. 删除 Nginx 站点配置"
        echo "  7. 移除 crontab 任务"
    else
        echo "  2. 删除 ${SUB_BOX_DIR} 目录"
        echo "  3. 移除 acme.sh 续期任务"
    fi
    echo ""
    echo "  可选保留:"
    echo "  - SSL 证书 (保留可复用)"
    echo "  - sing-box 二进制 (保留可重新配置)"
    echo "  - acme.sh (保留可管理其他域名证书)"
    echo ""

    if ! confirm "确认卸载 sub-box？" "N"; then
        warn "卸载已取消"
        return 1
    fi

    # 二次确认
    echo ""
    warn "再次确认：真的要卸载 sub-box 吗？"
    if ! confirm "输入 yes 确认卸载" "N"; then
        warn "卸载已取消"
        return 1
    fi

    # ========== 执行卸载 ==========
    echo ""
    title "执行卸载"

    local cert_domain
    local domain
    cert_domain=$(grep '^cert_domain =' "$SUB_BOX_DIR/config.ini" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')
    domain=$(grep '^domain =' "$SUB_BOX_DIR/config.ini" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')

    # 1. 停止进程
    echo ""
    info "停止服务..."
    systemctl stop sing-box 2>/dev/null
    systemctl disable sing-box 2>/dev/null
    if [[ "$mode" == "full" ]]; then
        pkill -f "$SUB_BOX_BIN_DIR/update.sh" 2>/dev/null
        pkill -f "inotifywait.*$SUB_BOX_DIR" 2>/dev/null
    fi
    success "服务已停止"

    # 2. 清理 Nginx（仅 full 模式）
    if [[ "$mode" == "full" ]]; then
        echo ""
        info "清理 Nginx 配置..."
        rm -f "/etc/nginx/sites-enabled/sub-box"
        rm -f "/etc/nginx/sites-available/sub-box"
        systemctl reload nginx 2>/dev/null
        success "Nginx 配置已清理"
    fi

    # 3. 可选保留项
    echo ""
    local keep_cert=true
    confirm "保留 SSL 证书？" "Y" && keep_cert=true || keep_cert=false

    local keep_singbox=true
    confirm "保留 sing-box 二进制？" "Y" && keep_singbox=true || keep_singbox=false

    local keep_acme=true
    confirm "保留 acme.sh？" "Y" && keep_acme=true || keep_acme=false

    # 4. 删除订阅文件目录（仅 full）
    if [[ "$mode" == "full" ]]; then
        echo ""
        info "清理订阅文件..."
        rm -rf "$WEB_DIR"
        success "订阅文件已删除"
    fi

    # 5. 删除 sub-box 目录
    echo ""
    info "清理 sub-box 目录..."
    rm -rf "$SUB_BOX_DIR"
    success "sub-box 目录已删除"

    # 6. 删除证书
    if ! $keep_cert; then
        echo ""
        info "删除 SSL 证书..."
        local cert_name="${cert_domain:-$domain}"
        if [[ -z "$cert_name" ]]; then
            warn "未能从 config.ini 读取证书域名，跳过证书删除以避免误删 $CERT_DIR"
        else
            rm -rf "$CERT_DIR/$cert_name"
            success "证书已删除: $CERT_DIR/$cert_name"
        fi
    fi

    # 7. 删除 sing-box
    if ! $keep_singbox; then
        echo ""
        info "删除 sing-box..."
        rm -f "$SING_BOX_BIN"
        rm -f /etc/systemd/system/sing-box.service
        systemctl daemon-reload
        success "sing-box 已删除"
    fi

    # 8. 删除 acme.sh
    if ! $keep_acme; then
        echo ""
        info "删除 acme.sh..."
        rm -rf ~/.acme.sh
        success "acme.sh 已删除"
    fi

    # 9. 清理 crontab
    echo ""
    info "清理 crontab..."
    local cron_tmp
    cron_tmp=$(mktemp)
    (crontab -l 2>/dev/null | grep -v "update.sh" | grep -v "fetch_ext.sh" | grep -v "acme.sh") > "$cron_tmp" 2>/dev/null
    crontab "$cron_tmp" 2>/dev/null
    rm -f "$cron_tmp"
    success "crontab 已清理"

    # ========== 完成 ==========
    echo ""
    title "✅ 卸载完成"
    echo ""
    if $keep_cert; then
        info "证书已保留在 $CERT_DIR"
    fi
    if $keep_singbox; then
        info "sing-box 已保留: $SING_BOX_BIN"
    fi
    if $keep_acme; then
        info "acme.sh 已保留"
    fi
    echo ""
    warn "如要完全清理，可手动删除:"
    if ! $keep_singbox; then
        echo "  已删除 sing-box"
    fi
    echo "  - /var/log/sing-box.log"
    echo ""

    read -r -p "按回车键返回..."
}
