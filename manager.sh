#!/bin/bash
# ==========================================
# sub-box v2.0 — 管理器入口
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/bin/sub-box.sh" "$@"
