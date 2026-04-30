#!/bin/bash
# ==========================================
# sub-box v2.0 — 状态查看模块
# ==========================================

status_main() {
    title "sub-box 系统状态"

    # ── 系统 ──
    echo -e "${CYAN}── 系统 ──────────────────────────────${NC}"
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "  OS:       $NAME $VERSION_ID"
    fi
    echo "  架构:     $(uname -m)"
    local mem_total mem_used
    mem_total=$(free -m | awk '/^Mem:/{print $2}')
    mem_used=$(free -m | awk '/^Mem:/{print $3}')
    echo "  内存:     ${mem_used}M / ${mem_total}M"
    local cpu_load
    cpu_load=$(uptime | awk -F'load average:' '{print $2}' | tr -d ',')
    echo "  负载:    $cpu_load"

    # ── sing-box ──
    echo ""
    echo -e "${CYAN}── sing-box ───────────────────────────${NC}"
    if command -v sing-box &>/dev/null; then
        local sb_ver
        sb_ver=$(sing-box version 2>/dev/null | head -1)
        echo "  版本:     $sb_ver"
    else
        echo -e "  状态:     ${RED}未安装${NC}"
    fi

    if systemctl is-active sing-box &>/dev/null; then
        echo -e "  状态:     ${GREEN}● 运行中${NC} (pid $(systemctl show -p MainPID sing-box 2>/dev/null | cut -d= -f2))"
    else
        echo -e "  状态:     ${RED}● 未运行${NC}"
    fi

    # 显示 sing-box 监听端口
    if command -v ss &>/dev/null; then
        local ports
        ports=$(ss -tlnp | grep sing-box | awk '{print $4}' | awk -F: '{print $NF}' | sort -n | tr '\n' ', ' | sed 's/,$//')
        [[ -n "$ports" ]] && echo "  监听:     $ports"
    fi

    # ── 证书 ──
    echo ""
    echo -e "${CYAN}── 证书 ──────────────────────────────${NC}"
    local cert_domain
    cert_domain=$(grep '^cert_domain =' "$SUB_BOX_DIR/config.ini" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')
    local domain
    domain=$(grep '^domain =' "$SUB_BOX_DIR/config.ini" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')
    local cert_file="$CERT_DIR/${cert_domain:-$domain}/fullchain.pem"

    if [[ -f "$cert_file" ]]; then
        echo "  域名:     ${cert_domain:-$domain}"

        local cert_expire
        if command -v openssl &>/dev/null; then
            cert_expire=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
            local expire_epoch now_epoch days_left
            expire_epoch=$(date -d "$cert_expire" +%s 2>/dev/null)
            now_epoch=$(date +%s)
            if [[ -n "$expire_epoch" ]]; then
                days_left=$(( (expire_epoch - now_epoch) / 86400 ))
                echo "  过期:     $cert_expire (剩余 ${days_left} 天)"
                if (( days_left < 30 )); then
                    echo -e "  自动续期: ${YELLOW}⚠ acme.sh 将在到期前自动续期${NC}"
                else
                    echo -e "  自动续期: ${GREEN}✓ acme.sh${NC}"
                fi
            fi
        fi
    else
        echo -e "  证书:     ${RED}未找到${NC}"
    fi

    # ── Nginx ──
    echo ""
    echo -e "${CYAN}── Nginx ─────────────────────────────${NC}"
    if systemctl is-active nginx &>/dev/null; then
        echo -e "  状态:     ${GREEN}● 运行中${NC}"
    else
        echo -e "  状态:     ${RED}● 未运行${NC}"
    fi

    # ── 节点 ──
    echo ""
    echo -e "${CYAN}── 节点 ──────────────────────────────${NC}"

    local config_file="$SUB_BOX_DIR/config.ini"
    local ext_file="$SUB_BOX_DIR/extend.ini"
    local self_count=0
    local ext_count=0

    if [[ -f "$config_file" ]]; then
        self_count=$(sed -n '/^\[nodes\]/,$p' "$config_file" 2>/dev/null | grep -cE "^(trojan|vmess|vless|hysteria2|hy2|ss)\|" || true)
    fi
    if [[ -f "$ext_file" ]]; then
        ext_count=$(sed -n '/^\[nodes\]/,$p' "$ext_file" 2>/dev/null | grep -cE "^(trojan|vmess|vless|hysteria2|hy2|ss)\|" || true)
    fi

    echo "  自建节点: $self_count 个"
    echo "  机场节点: $ext_count 个"
    echo "  总计:     $((self_count + ext_count)) 个"

    # 读取 config.ini 中的订阅配置
    local sub_token sub_port sub_domain
    sub_token=$(grep '^token =' "$SUB_BOX_DIR/config.ini" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')
    sub_port=$(grep '^port =' "$SUB_BOX_DIR/config.ini" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')
    sub_domain=$(grep '^domain =' "$SUB_BOX_DIR/config.ini" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')
    echo ""
    if [[ -n "$sub_domain" && -n "$sub_port" && -n "$sub_token" ]]; then
        echo "  订阅链接: https://${sub_domain}:${sub_port}/${sub_token:0:8}...${sub_token:(-8)}"
    fi

    # ── 进程 ──
    echo ""
    echo -e "${CYAN}── 进程 ──────────────────────────────${NC}"
    if pgrep -f "$SUB_BOX_BIN_DIR/update.sh" &>/dev/null; then
        echo -e "  update.sh:  ${GREEN}● 运行中${NC}"
    else
        echo -e "  update.sh:  ${RED}● 未运行${NC}"
    fi
    if pgrep -f "inotifywait.*$SUB_BOX_DIR" &>/dev/null; then
        echo -e "  inotify:    ${GREEN}● 监控中${NC}"
    else
        echo -e "  inotify:    ${YELLOW}○ 未监控${NC}"
    fi

    # acme.sh
    if command -v ~/.acme.sh/acme.sh &>/dev/null; then
        echo -e "  acme.sh:    ${GREEN}✓ 已安装${NC}"
    else
        echo -e "  acme.sh:    ${RED}✗ 未安装${NC}"
    fi

    echo ""
    read -r -p "按回车键返回菜单..."
}
