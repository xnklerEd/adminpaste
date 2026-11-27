#!/bin/bash
# 卸载 adminpaste：移除 LaunchAgent、二进制、配置；可选删除钥匙串里的密码
set -uo pipefail

LABEL="com.local.adminpaste"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SERVICE="admin-autotype"

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null && echo "已停止 $LABEL" || echo "未在运行"
rm -f "$PLIST" && echo "已删 $PLIST"
rm -f "$HOME/bin/adminpaste" "$HOME/bin/adminpaste.swift"
rm -rf "$HOME/.config/adminpaste"
rm -f "$HOME/.local/state/adminpaste.log" "$HOME/.local/state/adminpaste.err" \
      "$HOME/.local/state/adminpaste.out" "$HOME/.local/state/adminpaste.poke"

echo
read -p "同时删除钥匙串里的 $SERVICE 密码？(y/N) " ans
if [ "${ans:-N}" = "y" ] || [ "${ans:-N}" = "Y" ]; then
  security delete-generic-password -s "$SERVICE" >/dev/null 2>&1 && echo "已删除钥匙串项" || echo "钥匙串项不存在"
else
  echo "保留钥匙串项（下次装回去可直接用）"
fi