#!/bin/bash
# 弹一个真实（但无副作用）的系统授权框用于测试
echo "即将弹出系统授权框（执行 true，无任何副作用）"
echo "在框里按 ⌃⌥⌘P（仅终端需要），然后 ⌘V，再回车。"
echo "若授权框里密码已自动就位，直接 ⌘V + 回车即可。"
echo
osascript -e 'do shell script "true" with administrator privileges' && \
  echo "✅ 授权成功——链路通了" || echo "❌ 未通过（取消或密码不对）"
echo
echo "日志：tail -5 ~/.local/state/adminpaste.log"