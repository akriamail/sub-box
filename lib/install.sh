#!/bin/bash
# ==========================================
# sub-box v2.0 — 初始化安装模块
# ==========================================

install_main() {
    title "sub-box v2.0 初始化安装"

    # ---------- 前置检查 ----------
    info "检查运行环境..."
    if ! is_root; then
        error "请以 root 用户运行"
        return 1
    fi

    local os
    os=$(detect_os)
    if [[ "$os" != "ubuntu" && "$os" != "debian" ]]; then
        error "仅支持 Ubuntu/Debian，当前系统: $os"
        return 1
    fi
    success "系统: $os $(detect_arch)"

    # ---------- 域名输入与验证 ----------
    title "域名配置"
    echo "请输入用于订阅服务的域名"
    echo "例如: sub.yourdomain.com"
    echo ""

    local domain
    while :; do
        read -r -p "域名: " domain
        [[ -z "$domain" ]] && error "域名不能为空" && continue

        if confirm "是否验证域名 DNS 解析？"; then
            if check_dns "$domain"; then
                break
            else
                warn "DNS 验证失败，可选择："
                echo "  1) 重新输入域名"
                echo "  2) 跳过验证继续安装"
                read -r -p "请选择 [1/2]: " dns_choice
                if [[ "$dns_choice" == "2" ]]; then
                    warn "已跳过 DNS 验证"
                    break
                fi
            fi
        else
            break
        fi
    done

    # ---------- 安装模式选择 ----------
    title "安装模式"
    local use_defaults=true
    if ! confirm "使用默认配置快速安装？" "Y"; then
        use_defaults=false
    fi

    # ---------- 协议选择 ----------
    title "协议配置"
    local enable_trojan=true
    local enable_vmess=true
    local enable_vless=true
    local enable_hy2=true

    if ! $use_defaults; then
        echo "选择要开启的协议（默认全开）:"
        read -r -p "  Trojan (默认 443) [Y/n]: " ans
        [[ "$ans" =~ ^[Nn] ]] && enable_trojan=false

        read -r -p "  VMess (默认 8443) [Y/n]: " ans
        [[ "$ans" =~ ^[Nn] ]] && enable_vmess=false

        read -r -p "  VLESS+Reality (默认 8444) [Y/n]: " ans
        [[ "$ans" =~ ^[Nn] ]] && enable_vless=false

        read -r -p "  Hysteria2 (默认 8445) [Y/n]: " ans
        [[ "$ans" =~ ^[Nn] ]] && enable_hy2=false
    fi

    # ---------- 参数配置 ----------
    title "参数配置"

    # Trojan
    local trojan_port=443
    local trojan_pass=""
    if $enable_trojan; then
        if $use_defaults; then
            trojan_pass=$(gen_password)
            info "Trojan: 端口 443，密码自动生成"
        else
            trojan_port=$(read_input "Trojan 端口" "443")
            trojan_pass=$(read_input "Trojan 密码（回车自动生成）" "")
            [[ -z "$trojan_pass" ]] && trojan_pass=$(gen_password)
        fi
    fi

    # VMess
    local vmess_port=8443
    local vmess_uuid=""
    if $enable_vmess; then
        if $use_defaults; then
            vmess_uuid=$(gen_uuid)
            info "VMess: 端口 8443，UUID 自动生成"
        else
            vmess_port=$(read_input "VMess 端口" "8443")
            vmess_uuid=$(read_input "VMess UUID（回车自动生成）" "")
            [[ -z "$vmess_uuid" ]] && vmess_uuid=$(gen_uuid)
        fi
    fi

    # VLESS+Reality
    local vless_port=8444
    local vless_uuid=""
    local reality_private_key=""
    local reality_public_key=""
    if $enable_vless; then
        if $use_defaults; then
            vless_uuid=$(gen_uuid)
            info "VLESS+Reality: 端口 8444，UUID 自动生成"
        else
            vless_port=$(read_input "VLESS+Reality 端口" "8444")
            vless_uuid=$(read_input "VLESS UUID（回车自动生成）" "")
            [[ -z "$vless_uuid" ]] && vless_uuid=$(gen_uuid)
        fi
    fi

    # Hysteria2
    local hy2_port=8445
    local hy2_pass=""
    if $enable_hy2; then
        if $use_defaults; then
            hy2_pass=$(gen_password)
            info "Hysteria2: 端口 8445，密码自动生成"
        else
            hy2_port=$(read_input "Hysteria2 端口" "8445")
            hy2_pass=$(read_input "Hysteria2 密码（回车自动生成）" "")
            [[ -z "$hy2_pass" ]] && hy2_pass=$(gen_password)
        fi
    fi

    # ---------- 订阅配置 ----------
    title "订阅配置"
    local sub_token=""
    local sub_port=8080

    if $use_defaults; then
        sub_token=$(gen_token)
        info "订阅 Token 已自动生成"
    else
        sub_token=$(read_input "订阅 Token（回车自动生成）" "")
        [[ -z "$sub_token" ]] && sub_token=$(gen_token)
        sub_port=$(read_input "订阅端口" "8080")
    fi
    info "订阅链接: https://$domain:$sub_port/$sub_token"

    # ---------- 确认安装 ----------
    title "安装概要"
    echo "  域名:           $domain"
    echo "  Trojan:         $( $enable_trojan && echo '✓' || echo '✗') 端口 $trojan_port"
    echo "  VMess:          $( $enable_vmess && echo '✓' || echo '✗') 端口 $vmess_port"
    echo "  VLESS+Reality:  $( $enable_vless && echo '✓' || echo '✗') 端口 $vless_port"
    echo "  Hysteria2:      $( $enable_hy2 && echo '✓' || echo '✗') 端口 $hy2_port"
    echo "  订阅端口:       $sub_port"
    echo "  订阅 Token:     $sub_token"
    echo ""

    if ! confirm "确认安装？"; then
        warn "安装已取消"
        return 1
    fi

    # ========== 执行安装 ==========
    title "开始安装"

    # 1. 安装系统依赖
    echo ""
    info "安装系统依赖..."
    apt update
    apt install -y curl wget nginx uuid-runtime coreutils cron python3 bind9-dnsutils dnsutils openssl inotify-tools
    success "系统依赖已安装"

    # 2. 安装 acme.sh
    echo ""
    title "安装 acme.sh"
    if command -v ~/.acme.sh/acme.sh &>/dev/null; then
        success "acme.sh 已安装"
    else
        info "正在安装 acme.sh..."
        curl -fsSL https://get.acme.sh | bash
        if [[ $? -eq 0 ]]; then
            success "acme.sh 安装成功"
        else
            error "acme.sh 安装失败"
            return 1
        fi
    fi

    # 3. 申请证书
    echo ""
    title "申请 SSL 证书"
    local cert_dir="$CERT_DIR/$domain"

    if [[ -f "$cert_dir/fullchain.pem" ]]; then
        info "证书已存在: $cert_dir"
        if ! confirm "是否重新申请？"; then
            info "使用现有证书"
        else
            ~/.acme.sh/acme.sh --issue -d "$domain" --standalone --force
            ~/.acme.sh/acme.sh --install-cert -d "$domain" \
                --fullchain-file "$cert_dir/fullchain.pem" \
                --key-file "$cert_dir/privkey.pem"
        fi
    else
        info "正在申请证书..."
        mkdir -p "$cert_dir"
        ~/.acme.sh/acme.sh --issue -d "$domain" --standalone
        if [[ $? -eq 0 ]]; then
            ~/.acme.sh/acme.sh --install-cert -d "$domain" \
                --fullchain-file "$cert_dir/fullchain.pem" \
                --key-file "$cert_dir/privkey.pem"
            success "证书申请成功"
        else
            error "证书申请失败，请检查域名是否已解析到本机"
            return 1
        fi
    fi

    # 4. 安装 sing-box
    echo ""
    title "安装 sing-box"
    if command -v sing-box &>/dev/null; then
        local sb_ver
        sb_ver=$(sing-box version 2>/dev/null | head -1)
        info "sing-box 已安装: $sb_ver"
        if ! confirm "是否重新安装/升级？"; then
            info "跳过 sing-box 安装"
        else
            install_sing_box
        fi
    else
        install_sing_box
    fi

    # 5. 生成 sing-box 配置
    echo ""
    title "生成 sing-box 配置"
    generate_sing_box_config \
        "$enable_trojan" "$trojan_port" "$trojan_pass" \
        "$enable_vmess" "$vmess_port" "$vmess_uuid" \
        "$enable_vless" "$vless_port" "$vless_uuid" \
        "$enable_hy2" "$hy2_port" "$hy2_pass" \
        "$domain" "$cert_dir"
    success "sing-box 配置已生成"

    # 6. 配置 Nginx
    echo ""
    title "配置 Nginx 订阅分发"
    configure_nginx "$domain" "$sub_port" "$cert_dir" "$sub_token"
    success "Nginx 已配置"

    if confirm "是否立即下载 Android/Windows 客户端到本机镜像？"; then
        if bash "$SUB_BOX_BIN_DIR/refresh_clients.sh"; then
            generate_manual_page "$domain" "$sub_port" "$sub_token"
        else
            warn "客户端刷新失败，可稍后在管理菜单中手动刷新"
        fi
    fi

    # 7. 生成 config.ini
    echo ""
    title "生成配置文件"
    generate_config_ini \
        "$domain" "$sub_token" "$sub_port" \
        "$enable_trojan" "$trojan_port" "$trojan_pass" \
        "$enable_vmess" "$vmess_port" "$vmess_uuid" \
        "$enable_vless" "$vless_port" "$vless_uuid" \
        "$enable_hy2" "$hy2_port" "$hy2_pass"
    success "config.ini 已生成"

    # 8. 确保脚本可执行
    chmod +x "$SUB_BOX_DIR"/*.sh "$SUB_BOX_BIN_DIR"/*.sh "$SUB_BOX_DIR"/lib/*.sh 2>/dev/null

    # 9. 设置 crontab
    echo ""
    title "设置定时任务"
    setup_crontab
    success "定时任务已设置"

    # 10. 启动服务
    echo ""
    title "启动服务"
    systemctl daemon-reload
    systemctl enable sing-box
    systemctl restart sing-box
    systemctl restart nginx

    # 启动 update.sh
    pkill -f "$SUB_BOX_BIN_DIR/update.sh" 2>/dev/null
    nohup "$SUB_BOX_BIN_DIR/update.sh" > /dev/null 2>&1 &

    # 11. 完成
    echo ""
    title "✅ 安装完成"
    echo ""
    echo "  ├─ 管理命令: bash $SUB_BOX_DIR/manager.sh"
    echo "  ├─ 订阅链接: https://$domain:$sub_port/$sub_token"
    echo "  └─ 节点密码: 已保存至 $SUB_BOX_DIR/config.ini"
    echo ""

    # 如果开启了 reality，提示 key 信息
    if $enable_vless; then
        info "VLESS+Reality 需要客户端配置以下公钥："
        echo "  PublicKey: ${REALITY_PUBKEY:-（请查看 config.ini 注释）}"
        echo "  ServerName: $domain"
        echo "  ShortId: "
        echo ""
    fi
}

# ==========================================
# 安装 sing-box
# ==========================================
install_sing_box() {
    local arch
    arch=$(detect_arch)

    info "下载 sing-box ($arch)..."
    local tag
    tag=$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest 2>/dev/null | \
          grep '"tag_name":' | cut -d'"' -f4)

    if [[ -z "$tag" ]]; then
        error "获取 sing-box 最新版本失败"
        return 1
    fi

    local ver="${tag#v}"
    local url="https://github.com/SagerNet/sing-box/releases/download/${tag}/sing-box-${ver}-linux-${arch}.tar.gz"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || return 1

    curl -fsSL "$url" -o sing-box.tar.gz
    if [[ $? -ne 0 ]]; then
        error "下载 sing-box 失败"
        rm -rf "$tmp_dir"
        return 1
    fi

    tar xzf sing-box.tar.gz
    cp "sing-box-${ver}-linux-${arch}/sing-box" "$SING_BOX_BIN"
    chmod +x "$SING_BOX_BIN"
    rm -rf "$tmp_dir"

    success "sing-box ${ver} 已安装到 $SING_BOX_BIN"
}

# ==========================================
# 生成 sing-box 配置
# ==========================================
generate_sing_box_config() {
    local enable_trojan="$1"; shift
    local trojan_port="$1"; shift
    local trojan_pass="$1"; shift
    local enable_vmess="$1"; shift
    local vmess_port="$1"; shift
    local vmess_uuid="$1"; shift
    local enable_vless="$1"; shift
    local vless_port="$1"; shift
    local vless_uuid="$1"; shift
    local enable_hy2="$1"; shift
    local hy2_port="$1"; shift
    local hy2_pass="$1"; shift
    local domain="$1"; shift
    local cert_dir="$1"

    mkdir -p "$(dirname "$SING_BOX_CONFIG")"

    # 使用 cat 构建 JSON
    cat > "$SING_BOX_CONFIG" <<JSONEOF
{
  "log": {
    "level": "warn",
    "output": "/var/log/sing-box.log"
  },
  "inbounds": [
JSONEOF

    local first=true

    # Trojan
    if $enable_trojan; then
        $first || echo "," >> "$SING_BOX_CONFIG"
        cat >> "$SING_BOX_CONFIG" << JSONEOF
    {
      "type": "trojan",
      "tag": "trojan-in",
      "listen": "::",
      "listen_port": ${trojan_port},
      "tcp_fast_open": true,
      "sniff": true,
      "sniff_override_destination": true,
      "users": [
        {
          "password": "${trojan_pass}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${domain}",
        "certificate_path": "${cert_dir}/fullchain.pem",
        "key_path": "${cert_dir}/privkey.pem"
      }
    }
JSONEOF
        first=false
    fi

    # VMess
    if $enable_vmess; then
        $first || echo "," >> "$SING_BOX_CONFIG"
        cat >> "$SING_BOX_CONFIG" << JSONEOF
    {
      "type": "vmess",
      "tag": "vmess-in",
      "listen": "::",
      "listen_port": ${vmess_port},
      "tcp_fast_open": true,
      "sniff": true,
      "sniff_override_destination": true,
      "users": [
        {
          "uuid": "${vmess_uuid}",
          "alterId": 0
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${domain}",
        "certificate_path": "${cert_dir}/fullchain.pem",
        "key_path": "${cert_dir}/privkey.pem"
      }
    }
JSONEOF
        first=false
    fi

    # VLESS + Reality
    if $enable_vless; then
        # 生成 reality keypair
        local reality_keys
        reality_keys=$(sing-box generate reality-keypair 2>/dev/null)
        local priv_key
        local pub_key
        priv_key=$(echo "$reality_keys" | grep "PrivateKey:" | awk '{print $2}')
        pub_key=$(echo "$reality_keys" | grep "PublicKey:" | awk '{print $2}')

        $first || echo "," >> "$SING_BOX_CONFIG"
        cat >> "$SING_BOX_CONFIG" << JSONEOF
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "::",
      "listen_port": ${vless_port},
      "tcp_fast_open": true,
      "sniff": true,
      "sniff_override_destination": true,
      "users": [
        {
          "uuid": "${vless_uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${domain}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "www.microsoft.com",
            "server_port": 443
          },
          "private_key": "${priv_key}",
          "short_id": [
            ""
          ]
        }
      }
    }
JSONEOF
        # 保存公钥到 config.ini 用
        REALITY_PUBKEY="$pub_key"
        REALITY_PRIVKEY="$priv_key"
        first=false
    fi

    # Hysteria2
    if $enable_hy2; then
        $first || echo "," >> "$SING_BOX_CONFIG"
        cat >> "$SING_BOX_CONFIG" << JSONEOF
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": ${hy2_port},
      "tcp_fast_open": true,
      "sniff": true,
      "sniff_override_destination": true,
      "up_mbps": 100,
      "down_mbps": 500,
      "users": [
        {
          "password": "${hy2_pass}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${domain}",
        "certificate_path": "${cert_dir}/fullchain.pem",
        "key_path": "${cert_dir}/privkey.pem"
      }
    }
JSONEOF
        first=false
    fi

    # 补完 JSON
    cat >> "$SING_BOX_CONFIG" << JSONEOF
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ]
}
JSONEOF
}

# ==========================================
# 配置 Nginx 订阅分发
# ==========================================
configure_nginx() {
    local domain="$1"
    local port="$2"
    local cert_dir="$3"
    local token="${4:-}"

    mkdir -p "$WEB_DIR"
    generate_manual_page "$domain" "$port" "$token"

    cat > "/etc/nginx/sites-available/sub-box" << NGINXEOF
server {
    listen ${port} ssl http2;
    listen [::]:${port} ssl http2;
    server_name ${domain};

    ssl_certificate ${cert_dir}/fullchain.pem;
    ssl_certificate_key ${cert_dir}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root ${WEB_DIR};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # 禁用访问日志（订阅请求量大）
    access_log off;
}
NGINXEOF

    ln -sf "/etc/nginx/sites-available/sub-box" "/etc/nginx/sites-enabled/" 2>/dev/null
}

# ==========================================
# 生成 Nginx 首页手册
# ==========================================
generate_manual_page() {
    local domain="$1"
    local port="$2"
    local token="$3"
    local sub_url
    local v2rayng_version="待刷新"
    local v2rayng_file=""
    local v2rayn_version="待刷新"
    local v2rayn_file=""

    if [[ -z "$token" && -f "$SUB_BOX_DIR/config.ini" ]]; then
        token=$(grep '^token =' "$SUB_BOX_DIR/config.ini" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')
    fi
    if [[ -f "$CLIENTS_META" ]]; then
        # shellcheck disable=SC1090
        source "$CLIENTS_META"
        v2rayng_version="${V2RAYNG_VERSION:-待刷新}"
        v2rayng_file="${V2RAYNG_FILE:-}"
        v2rayn_version="${V2RAYN_VERSION:-待刷新}"
        v2rayn_file="${V2RAYN_FILE:-}"
    fi
    [[ -z "$token" ]] && token="{Token}"
    sub_url="https://${domain}:${port}/${token}"
    local v2rayng_href="#"
    local v2rayn_href="#"
    [[ -n "$v2rayng_file" ]] && v2rayng_href="/clients/${v2rayng_file}"
    [[ -n "$v2rayn_file" ]] && v2rayn_href="/clients/${v2rayn_file}"

    cat > "$WEB_DIR/index.html" <<HTMLEOF
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>sub-box 使用手册</title>
  <style>
    :root {
      color-scheme: light;
      --ink: #17202a;
      --muted: #5d6b7a;
      --line: #d9e2ec;
      --paper: #f7f9fc;
      --panel: #ffffff;
      --blue: #2563eb;
      --teal: #0f766e;
      --rose: #be123c;
      --amber: #b45309;
      --violet: #6d28d9;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif;
      color: var(--ink);
      background:
        linear-gradient(135deg, rgba(37, 99, 235, .08), transparent 34%),
        linear-gradient(315deg, rgba(15, 118, 110, .08), transparent 32%),
        var(--paper);
      line-height: 1.65;
    }
    a { color: var(--blue); text-decoration: none; }
    a:hover { text-decoration: underline; }
    .wrap { max-width: 1120px; margin: 0 auto; padding: 44px 22px 72px; }
    .hero {
      display: grid;
      grid-template-columns: minmax(0, 1.2fr) minmax(280px, .8fr);
      gap: 28px;
      align-items: stretch;
      min-height: 430px;
    }
    .hero-main {
      padding: 46px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: rgba(255,255,255,.9);
      box-shadow: 0 24px 70px rgba(15, 23, 42, .08);
    }
    .eyebrow { margin: 0 0 12px; color: var(--teal); font-weight: 700; letter-spacing: 0; }
    h1 { margin: 0; font-size: 44px; line-height: 1.12; letter-spacing: 0; }
    .lead { margin: 18px 0 0; max-width: 680px; color: var(--muted); font-size: 18px; }
    .subbox {
      margin-top: 28px;
      padding: 18px;
      border: 1px solid #bfdbfe;
      border-radius: 8px;
      background: #eff6ff;
    }
    .subbox label { display: block; margin-bottom: 8px; color: #1e40af; font-size: 13px; font-weight: 700; }
    .url {
      overflow-wrap: anywhere;
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      color: #0f172a;
      font-size: 15px;
    }
    .url-tools { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 14px; }
    .hero-side {
      display: grid;
      gap: 14px;
    }
    .metric {
      padding: 22px;
      border-radius: 8px;
      background: #102a43;
      color: white;
      min-height: 122px;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
    }
    .metric:nth-child(2) { background: #174e4a; }
    .metric:nth-child(3) { background: #5b2a86; }
    .metric span { color: rgba(255,255,255,.72); font-size: 13px; }
    .metric strong { font-size: 24px; letter-spacing: 0; }
    .section { margin-top: 34px; }
    .section h2 { margin: 0 0 14px; font-size: 26px; letter-spacing: 0; }
    .grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 18px;
    }
    .card {
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      padding: 24px;
      box-shadow: 0 10px 30px rgba(15, 23, 42, .05);
    }
    .card h3 { margin: 0 0 8px; font-size: 21px; letter-spacing: 0; }
    .tag {
      display: inline-flex;
      align-items: center;
      min-height: 26px;
      padding: 0 9px;
      border-radius: 999px;
      color: white;
      font-size: 12px;
      font-weight: 700;
      background: var(--blue);
    }
    .tag.teal { background: var(--teal); }
    .tag.rose { background: var(--rose); }
    .tag.amber { background: var(--amber); }
    ol { margin: 14px 0 0; padding-left: 22px; }
    li { margin: 8px 0; }
    .actions { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 18px; }
    .btn {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-height: 38px;
      padding: 0 14px;
      border-radius: 8px;
      background: #111827;
      color: white;
      font-weight: 700;
      font-size: 14px;
    }
    .btn.secondary { background: #e5e7eb; color: #111827; }
    .btn:hover { text-decoration: none; filter: brightness(.96); }
    .note {
      margin-top: 18px;
      padding: 14px 16px;
      border-left: 4px solid var(--amber);
      background: #fffbeb;
      color: #713f12;
      border-radius: 0 8px 8px 0;
    }
    .footer {
      margin-top: 34px;
      color: var(--muted);
      font-size: 13px;
      text-align: center;
    }
    @media (max-width: 820px) {
      .wrap { padding: 26px 14px 48px; }
      .hero, .grid { grid-template-columns: 1fr; }
      .hero-main { padding: 28px; }
      h1 { font-size: 34px; }
    }
  </style>
</head>
<body>
  <main class="wrap">
    <section class="hero">
      <div class="hero-main">
        <p class="eyebrow">sub-box 订阅中心</p>
        <h1>客户端下载与使用手册</h1>
        <p class="lead">按你的设备选择客户端，导入下方订阅链接后更新节点，再开启系统代理或 VPN 模式即可使用。</p>
        <div class="subbox">
          <label>当前订阅链接</label>
          <div class="url" id="subscription-url">${sub_url}</div>
          <div class="url-tools">
            <button class="btn" id="copy-subscription" type="button">复制链接</button>
          </div>
        </div>
        <div class="note">订阅链接包含私人 Token，请不要公开分享。更换 Token 后，旧链接会失效。</div>
      </div>
      <aside class="hero-side">
        <div class="metric"><span>Apple</span><strong>iOS / macOS 小火箭</strong></div>
        <div class="metric"><span>Android</span><strong>v2rayNG 本地下载</strong></div>
        <div class="metric"><span>Windows</span><strong>v2rayN 图形客户端</strong></div>
      </aside>
    </section>

    <section class="section">
      <h2>Apple 设备</h2>
      <div class="grid">
        <article class="card">
          <span class="tag">iOS</span>
          <h3>小火箭 Shadowrocket</h3>
          <ol>
            <li>在 App Store 安装 Shadowrocket。</li>
            <li>复制本页顶部的订阅链接。</li>
            <li>打开 Shadowrocket，点击右上角加号，类型选择 Subscribe。</li>
            <li>粘贴订阅链接，保存后点击更新。</li>
            <li>选择节点，打开首页连接开关。</li>
          </ol>
          <div class="actions">
            <a class="btn" href="https://apps.apple.com/us/app/shadowrocket/id932747118">打开 App Store</a>
          </div>
        </article>
        <article class="card">
          <span class="tag teal">macOS</span>
          <h3>Mac 小火箭 Shadowrocket</h3>
          <ol>
            <li>在 Mac App Store 安装 Shadowrocket。</li>
            <li>复制订阅链接，在 Shadowrocket 中新增 Subscribe。</li>
            <li>更新订阅，选择可用节点。</li>
            <li>在菜单栏或主界面开启代理。</li>
          </ol>
          <div class="actions">
            <a class="btn" href="https://apps.apple.com/us/app/shadowrocket/id932747118?platform=mac">打开 Mac App Store</a>
          </div>
        </article>
      </div>
    </section>

    <section class="section">
      <h2>Android 与 Windows</h2>
      <div class="grid">
        <article class="card">
          <span class="tag rose">Android</span>
          <h3>v2rayNG</h3>
          <p>本地镜像版本：${v2rayng_version}</p>
          <ol>
            <li>点击下方本地下载按钮安装 APK。</li>
            <li>打开 v2rayNG，点击右上角加号。</li>
            <li>选择从剪贴板导入订阅，或进入订阅设置添加本页订阅链接。</li>
            <li>更新订阅，选择节点，点击右下角连接按钮。</li>
          </ol>
          <div class="actions">
            <a class="btn" href="${v2rayng_href}">本地下载 APK</a>
            <a class="btn secondary" href="https://github.com/2dust/v2rayNG">项目主页</a>
          </div>
        </article>
        <article class="card">
          <span class="tag amber">Windows</span>
          <h3>v2rayN</h3>
          <p>本地镜像版本：${v2rayn_version}</p>
          <ol>
            <li>点击下方本地下载按钮获取 Windows 压缩包。</li>
            <li>解压后运行 v2rayN.exe。</li>
            <li>进入订阅分组，添加订阅地址。</li>
            <li>更新订阅，选择节点，开启系统代理。</li>
          </ol>
          <div class="actions">
            <a class="btn" href="${v2rayn_href}">本地下载 ZIP</a>
            <a class="btn secondary" href="https://github.com/2dust/v2rayN/wiki">查看 Wiki</a>
          </div>
        </article>
      </div>
    </section>

    <section class="section">
      <div class="card">
        <h3>常见问题</h3>
        <ol>
          <li>订阅为空：确认节点已在管理器中添加，或机场抓取已成功执行。</li>
          <li>无法更新订阅：确认域名、端口和 HTTPS 证书正常，客户端网络可访问本页。</li>
          <li>节点不可用：检查服务端端口是否放行，sing-box 是否运行。</li>
        </ol>
      </div>
    </section>

    <p class="footer">Generated by sub-box · ${domain}</p>
  </main>
  <script>
    (function () {
      var token = "${token}";
      var target = document.getElementById("subscription-url");
      var copyButton = document.getElementById("copy-subscription");
      if (!target || !token || token === "{Token}") return;
      function buildUrl() {
        var protocol = window.location.protocol === "http:" ? "http:" : "https:";
        var hostname = window.location.hostname || "${domain}";
        var currentPort = window.location.port || "${port}";
        var host = hostname;
        if (currentPort) host += ":" + currentPort;
        target.textContent = protocol + "//" + host + "/" + token;
      }
      if (copyButton && navigator.clipboard) {
        copyButton.addEventListener("click", function () {
          navigator.clipboard.writeText(target.textContent);
          copyButton.textContent = "已复制";
          setTimeout(function () { copyButton.textContent = "复制链接"; }, 1400);
        });
      }
      buildUrl();
    })();
  </script>
</body>
</html>
HTMLEOF
}

# ==========================================
# 生成 sub-box config.ini
# ==========================================
generate_config_ini() {
    local domain="$1"; shift
    local token="$1"; shift
    local port="$1"; shift
    local enable_trojan="$1"; shift
    local trojan_port="$1"; shift
    local trojan_pass="$1"; shift
    local enable_vmess="$1"; shift
    local vmess_port="$1"; shift
    local vmess_uuid="$1"; shift
    local enable_vless="$1"; shift
    local vless_port="$1"; shift
    local vless_uuid="$1"; shift
    local enable_hy2="$1"; shift
    local hy2_port="$1"; shift
    local hy2_pass="$1"; shift

    local config_file="$SUB_BOX_DIR/config.ini"

    cat > "$config_file" << INIEOF
[common]
# 订阅服务域名
domain = ${domain}
# 订阅认证 Token（客户端以此构建订阅链接）
token = ${token}
# 订阅服务端口
port = ${port}
# 证书域名（acme.sh 签发用）
cert_domain = ${domain}

[sing-box]
# sing-box 配置路径
config_path = ${SING_BOX_CONFIG}

[nodes]
# 节点格式: 协议|Host/IP|端口|密码/UUID|显示名
# 兼容旧格式: 协议|端口|密码/UUID|显示名（Host 默认使用订阅域名）
# Trojan
INIEOF

    if $enable_trojan; then
        echo "trojan|${domain}|${trojan_port}|${trojan_pass}|自建-Trojan-${trojan_port}" >> "$config_file"
    fi

    if $enable_vmess; then
        echo "vmess|${domain}|${vmess_port}|${vmess_uuid}|自建-VMess-${vmess_port}" >> "$config_file"
    fi

    if $enable_vless; then
        # 需要 REALITY_PUBKEY
        echo "vless|${domain}|${vless_port}|${vless_uuid}|自建-VLESS-${vless_port}" >> "$config_file"
        echo "# VLESS Reality 公钥: ${REALITY_PUBKEY:-}" >> "$config_file"
        echo "# Reality ServerName: ${domain}" >> "$config_file"
    fi

    if $enable_hy2; then
        echo "hysteria2|${domain}|${hy2_port}|${hy2_pass}|自建-Hy2-${hy2_port}" >> "$config_file"
    fi

    echo "" >> "$config_file"
    echo "# 机场节点由 bin/fetch_ext.sh 写入 extend.ini" >> "$config_file"
}

# ==========================================
# 设置定时任务
# ==========================================
setup_crontab() {
    local cron_tmp
    cron_tmp=$(mktemp)
    (crontab -l 2>/dev/null | grep -v "update.sh" | grep -v "fetch_ext.sh") > "$cron_tmp" 2>/dev/null
    echo "@reboot nohup $SUB_BOX_BIN_DIR/update.sh > /dev/null 2>&1 &" >> "$cron_tmp"
    echo "0 3 * * * /bin/bash $SUB_BOX_BIN_DIR/fetch_ext.sh > /dev/null 2>&1" >> "$cron_tmp"
    crontab "$cron_tmp"
    rm -f "$cron_tmp"
}
