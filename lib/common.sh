#!/bin/bash
# ==========================================
# sub-box v2.0 — 公共函数库
# ==========================================

# ---------- 颜色 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERR]${NC}  $*"; }
title() { echo -e "\n${CYAN}═══════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}═══════════════════════════════════════${NC}\n"; }

# ---------- 工具函数 ----------
is_root() {
    [[ $EUID -eq 0 ]]
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "armv7" ;;
        *)       echo "$arch" ;;
    esac
}

# ---------- 密码/令牌生成 ----------
gen_password() {
    openssl rand -hex 8  # 16 位
}

gen_token() {
    openssl rand -hex 16  # 32 位
}

gen_uuid() {
    uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || \
        echo "$(od -x /dev/urandom | head -1 | tr -d ' ' | awk '{print substr($0,1,8)}')-$(od -x /dev/urandom | head -1 | tr -d ' ' | awk '{print substr($0,1,4)}')-4$(od -x /dev/urandom | head -1 | tr -d ' ' | awk '{print substr($0,1,3)}')-$(printf '%x' $((RANDOM%4+8)))$(od -x /dev/urandom | head -1 | tr -d ' ' | awk '{print substr($0,1,3)}')-$(od -x /dev/urandom | head -1 | tr -d ' ' | awk '{print substr($0,1,12)}')"
}

gen_reality_keypair() {
    # sing-box reality keypair (需要 sing-box 工具)
    if command -v sing-box &>/dev/null; then
        sing-box generate reality-keypair 2>/dev/null
    else
        echo "private_key=请安装 sing-box 后重新生成"
        echo "public_key=请安装 sing-box 后重新生成"
    fi
}

# ---------- 输入函数 ----------
read_input() {
    # 用法: read_input "提示信息" 默认值
    # 如果输入为空则返回默认值
    local prompt="$1"
    local default="$2"
    local input

    if [[ -n "$default" ]]; then
        read -r -p "$prompt [$default]: " input
        echo "${input:-$default}"
    else
        read -r -p "$prompt: " input
        echo "$input"
    fi
}

confirm() {
    # 用法: confirm "确认执行？" → 返回 true/false
    local prompt="$1"
    local default="${2:-Y}"
    local input

    if [[ "$default" == "Y" ]]; then
        read -r -p "$prompt [Y/n]: " input
        [[ "$input" =~ ^[Yy]?$ ]] && return 0 || return 1
    else
        read -r -p "$prompt [y/N]: " input
        [[ "$input" =~ ^[Yy]$ ]] && return 0 || return 1
    fi
}

# ---------- DNS 验证 ----------
check_dns() {
    local domain="$1"
    local my_ip

    my_ip=$(curl -4 -s --max-time 5 https://api.ipify.org 2>/dev/null || \
            curl -4 -s --max-time 5 https://icanhazip.com 2>/dev/null || \
            echo "")

    if [[ -z "$my_ip" ]]; then
        warn "无法获取本机公网 IP，跳过 DNS 验证"
        return 0
    fi

    local resolved_ip
    resolved_ip=$(dig +short "$domain" 2>/dev/null | head -1)

    if [[ -z "$resolved_ip" ]]; then
        error "域名 $domain 未解析到任何 IP"
        return 1
    fi

    if [[ "$resolved_ip" != "$my_ip" ]]; then
        error "域名 $domain 解析到 $resolved_ip，但本机公网 IP 是 $my_ip"
        warn "请先将域名 A 记录指向本机 IP 后再安装"
        return 1
    fi

    success "域名 $domain → $resolved_ip ✓"
    return 0
}

# ---------- 配置文件读写 ----------
load_config() {
    local config_file="${1:-$SUB_BOX_DIR/config.ini}"
    if [[ -f "$config_file" ]]; then
        # 只读取 [common] 和 [sing-box] 段的配置
        domain=$(grep '^domain =' "$config_file" | cut -d'=' -f2- | tr -d ' ')
        token=$(grep '^token =' "$config_file" | cut -d'=' -f2- | tr -d ' ')
        port=$(grep '^port =' "$config_file" | cut -d'=' -f2- | tr -d ' ')
        cert_domain=$(grep '^cert_domain =' "$config_file" | cut -d'=' -f2- | tr -d ' ')
    fi
}

# ---------- 常量 ----------
SUB_BOX_DIR="/opt/subscribe"
SUB_BOX_BIN_DIR="$SUB_BOX_DIR/bin"
WEB_DIR="/var/www/subscribe"
CLIENTS_DIR="$WEB_DIR/clients"
CLIENTS_META="$CLIENTS_DIR/clients.env"
WEB_AUTH_FILE="$SUB_BOX_DIR/web.htpasswd"
WEB_AUTH_USER="admin"
SING_BOX_CONFIG="/etc/sing-box/config.json"
SING_BOX_BIN="/usr/local/bin/sing-box"
CERT_DIR="/root/cert"
