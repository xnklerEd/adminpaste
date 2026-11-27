#!/bin/bash
# adminpaste 安装器（纯用户级，不需要管理员密码、不碰 SIP）
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
ARCH=$(uname -m)
DEST_DIR="$HOME/bin"
BIN="$DEST_DIR/adminpaste"
SRC="$DIR/adminpaste.swift"
CFG_DIR="$HOME/.config/adminpaste"
CFG="$CFG_DIR/config.json"
PLIST="$HOME/Library/LaunchAgents/com.local.adminpaste.plist"
LABEL="com.local.adminpaste"
SERVICE="admin-autotype"

echo "==> 目标: $BIN ($ARCH)"

mkdir -p "$DEST_DIR" "$CFG_DIR" "$HOME/.local/state"

# 1) 二进制：优先用包内预编译（含 arm64 + x86_64），架构不匹配则就地编译
USE_PREBUILT=0
if [ -f "$DIR/bin/adminpaste" ] && lipo -archs "$DIR/bin/adminpaste" 2>/dev/null | grep -qw "$ARCH"; then
  USE_PREBUILT=1
fi

if [ "$USE_PREBUILT" = "1" ]; then
  echo "==> 安装预编译二进制"
  cp "$DIR/bin/adminpaste" "$BIN"
else
  echo "==> 包内二进制不支持 $ARCH，改为就地编译"
  if ! xcode-select -p >/dev/null 2>&1; then
    echo "!! 需要 Xcode Command Line Tools：xcode-select --install，装完重跑" >&2
    exit 1
  fi
  swiftc -O -o "$BIN" "$SRC" -framework Carbon -framework AppKit
fi

chmod 755 "$BIN"
xattr -d com.apple.quarantine "$BIN" 2>/dev/null || true
# 传输后签名可能失效（Apple Silicon 上未签名会被内核杀掉），重新 ad-hoc 签一次
codesign --force -s - "$BIN" >/dev/null 2>&1 || true
echo "==> 签名: $(codesign -dv "$BIN" 2>&1 | grep -m1 'Signature' || echo '(none)')"

# 2) 配置（已存在则保留）
if [ ! -f "$CFG" ]; then
  cat > "$CFG" <<EOF
{
  "service": "$SERVICE",
  "key": "p",
  "modifiers": ["control", "option", "command"],
  "clearAfterSeconds": 30,
  "armOnSecurityAgent": true,
  "allowedBundleIDs": [
    "com.apple.SecurityAgent",
    "com.apple.Terminal",
    "com.googlecode.iterm2"
  ],
  "requireSecureFieldWhenPossible": true,
  "log": "~/.local/state/adminpaste.log"
}
EOF
  chmod 600 "$CFG"
  echo "==> 已写默认配置 $CFG"
else
  echo "==> 保留已有配置 $CFG"
fi

# 3) LaunchAgent（登录自启 + 挂掉自动拉起）
echo "==> 写 $PLIST"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardErrorPath</key><string>$HOME/.local/state/adminpaste.err</string>
  <key>StandardOutPath</key><string>$HOME/.local/state/adminpaste.out</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST"
sleep 1

# 4) 密码写入登录钥匙串（交互输入，不进 shell 历史）
if security find-generic-password -s "$SERVICE" >/dev/null 2>&1; then
  echo "==> 钥匙串里已有 $SERVICE，跳过"
else
  echo
  echo "==> 请输入这台 Mac 的管理员密码（存进登录钥匙串，不回显、不写盘）"
  security add-generic-password -s "$SERVICE" -a "$USER" -w
fi

echo
echo "==> 状态"
launchctl print "gui/$UID/$LABEL" 2>/dev/null | grep -E "^\s*(state|pid)" || true
tail -2 "$HOME/.local/state/adminpaste.log" 2>/dev/null || true

cat <<'TIP'

完成。用法：
  1) 任何需要管理员密码的系统授权框弹出 -> 密码已在剪贴板 -> 按 ⌘V -> 回车
  2) 终端里 sudo/ssh 提示 -> 按 ⌃⌥⌘P -> 按 ⌘V
  3) 其它 App 里按 ⌃⌥⌘P 无效（白名单外一律不生效）

自检：bash test-dialog.sh
日志：tail -5 ~/.local/state/adminpaste.log
TIP