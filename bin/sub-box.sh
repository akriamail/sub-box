#!/bin/bash
# ==========================================
# sub-box v2.0 — 管理器主菜单
# ==========================================
# 基于 sing-box 的全协议订阅聚合管理工具
# ==========================================

VERSION="2.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 加载所有模块（共享函数可互相调用）
for _lib in common install config status uninstall; do
    source "$PROJECT_DIR/lib/${_lib}.sh" 2>/dev/null || {
        echo "[ERR] 无法加载 lib/${_lib}.sh"
        exit 1
    }
done

# ==========================================
# 主菜单
# ==========================================
main_menu() {
    while :; do
        clear 2>/dev/null || true

        echo ""
        echo -e "${CYAN}╔═══════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║          sub-box v${VERSION} 管理器            ║${NC}"
        echo -e "${CYAN}║    全协议订阅聚合 · sing-box 引擎          ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════════╝${NC}"
        echo ""

        # 检测安装状态
        local installed=false
        if [[ -f "$SUB_BOX_DIR/config.ini" ]] && systemctl is-active sing-box &>/dev/null 2>&1; then
            installed=true
        fi

        if $installed; then
            echo -e "  ${GREEN}■${NC} 状态: 已安装"
            local domain port
            domain=$(grep '^domain =' "$SUB_BOX_DIR/config.ini" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')
            port=$(grep '^port =' "$SUB_BOX_DIR/config.ini" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')
            [[ -n "$domain" ]] && echo -e "  ${CYAN}■${NC} 域名: $domain"
            [[ -n "$port" ]] && echo -e "  ${CYAN}■${NC} 端口: $port"
        else
            echo -e "  ${YELLOW}■${NC} 状态: 未安装"
        fi
        echo ""

        echo "  ┌─────────────────────────────────────┐"
        echo "  │  1. 初始化安装                        │"
        echo "  │  2. 修改配置                          │"
        echo "  │  3. 查看状态                          │"
        echo "  │  4. 卸载                              │"
        echo "  │  5. 刷新客户端版本                    │"
        echo "  │  0. 退出                              │"
        echo "  └─────────────────────────────────────┘"
        echo ""
        read -r -p "  请选择 [0-5]: " choice

        case "$choice" in
            1) install_main ;;
            2)
                if [[ ! -f "$SUB_BOX_DIR/config.ini" ]]; then
                    warn "尚未安装，请先执行初始化安装"
                    read -r -p "按回车继续..."
                    continue
                fi
                config_main
                ;;
            3) status_main ;;
            4) uninstall_main ;;
            5) refresh_clients_main ;;
            0)
                echo ""
                info "再见！"
                exit 0
                ;;
            *)
                error "无效选择"
                sleep 1
                ;;
        esac
    done
}

# ==========================================
# 启动
# ==========================================
# 如果未以 root 运行，尝试 sudo 重启动
if [[ $EUID -ne 0 ]]; then
    if command -v sudo &>/dev/null; then
        exec sudo "$0" "$@"
    else
        error "请以 root 用户运行: sudo bash $0"
        exit 1
    fi
fi

main_menu
