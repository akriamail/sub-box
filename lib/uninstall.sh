#!/bin/bash
# ==========================================
# sub-box v2.0 — 卸载模块
# ==========================================

uninstall_main() {
    title "卸载 sub-box"

    echo -e "${RED}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           这是一个破坏性操作！                  ║${NC}"
    echo -e "${RED}║  将停止所有相关服务并删除配置文件               ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════╝${NC}"
    echo ""

    # 列出将要卸载的组件
    echo "将执行以下操作:"
    echo "  1. 停止 sing-box 服务并禁用开机自启"
    echo "  2. 停止 nginx 订阅站点（保留 nginx 本身）"
    echo "  3. 停止 update.sh 进程"
    echo "  4. 删除 ${SUB_BOX_DIR} 目录"
    echo "  5. 删除 ${WEB_DIR} 订阅文件目录"
    echo "  6. 删除 Nginx 站点配置"
    echo "  7. 移除 crontab 任务"
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
    pkill -f "$SUB_BOX_BIN_DIR/update.sh" 2>/dev/null
    pkill -f "inotifywait.*$SUB_BOX_DIR" 2>/dev/null
    success "服务已停止"

    # 2. 移除 Nginx 订阅站点
    echo ""
    info "清理 Nginx 配置..."
    rm -f "/etc/nginx/sites-enabled/sub-box"
    rm -f "/etc/nginx/sites-available/sub-box"
    systemctl reload nginx 2>/dev/null
    success "Nginx 配置已清理"

    # 3. 可选：保留证书
    echo ""
    local keep_cert=true
    if confirm "保留 SSL 证书？" "Y"; then
        keep_cert=true
        info "证书已保留"
    else
        keep_cert=false
    fi

    # 4. 可选：保留 sing-box
    local keep_singbox=true
    if confirm "保留 sing-box 二进制？" "Y"; then
        keep_singbox=true
    else
        keep_singbox=false
    fi

    # 5. 可选：保留 acme.sh
    local keep_acme=true
    if confirm "保留 acme.sh？" "Y"; then
        keep_acme=true
    else
        keep_acme=false
    fi

    # 6. 删除订阅文件目录
    echo ""
    info "清理订阅文件..."
    rm -rf "$WEB_DIR"
    success "订阅文件已删除"

    # 7. 删除 sub-box 目录
    echo ""
    info "清理 sub-box 目录..."
    rm -rf "$SUB_BOX_DIR"
    success "sub-box 目录已删除"

    # 8. 删除证书（如果不保留）
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

    # 9. 删除 sing-box（如果不保留）
    if ! $keep_singbox; then
        echo ""
        info "删除 sing-box..."
        rm -f "$SING_BOX_BIN"
        rm -f /etc/systemd/system/sing-box.service
        systemctl daemon-reload
        success "sing-box 已删除"
    fi

    # 10. 删除 acme.sh（如果不保留）
    if ! $keep_acme; then
        echo ""
        info "删除 acme.sh..."
        rm -rf ~/.acme.sh
        success "acme.sh 已删除"
    fi

    # 11. 移除 crontab 相关任务
    echo ""
    info "清理 crontab..."
    local cron_tmp
    cron_tmp=$(mktemp)
    (crontab -l 2>/dev/null | grep -v "update.sh" | grep -v "fetch_ext.sh") > "$cron_tmp" 2>/dev/null
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
    $keep_singbox || echo "  - $SING_BOX_BIN"
    echo "  - /var/log/sing-box.log"
    echo ""

    read -r -p "按回车键返回..."
}
