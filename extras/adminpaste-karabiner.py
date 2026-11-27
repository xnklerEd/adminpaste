#!/usr/bin/env python3
"""
adminpaste-karabiner.py —— 一次组合键完成整个授权（等价于按一次 Touch ID）

规则（仅在系统授权框 SecurityAgent 前台时生效）：
  ⌃⌥⌘P -> 从钥匙串取密码写入剪贴板 (shell_command)
        -> 300ms 后由 Karabiner 的 DriverKit 虚拟键盘发 ⌘V
        -> 紧接着发回车，按下默认按钮「好」

为什么必须用 Karabiner：用户态进程注入的 ⌘V / keystroke 会被 Secure Input 丢弃；
自建虚拟 HID 设备需要 Apple 特批的 com.apple.developer.hid.virtual.device
（SIP 开启时自签二进制拿不到）。Karabiner 的虚拟键盘驱动是已授权的，
它发出的按键是内核 HID 事件，能落进授权框的密码框。

密码始终留在钥匙串，配置文件里没有明文，只在按键那一刻被读出来。

用法：
  python3 ~/bin/adminpaste-karabiner.py                 # 写入 ~/.config/karabiner/karabiner.json
  python3 ~/bin/adminpaste-karabiner.py --dry-run        # 只打印规则
  python3 ~/bin/adminpaste-karabiner.py --delay-ms 500   # pbcopy 慢的话加大延迟
  python3 ~/bin/adminpaste-karabiner.py --remove         # 移除规则
"""

import argparse, json, os, sys

KJ = os.path.expanduser("~/.config/karabiner/karabiner.json")
DESC = "Admin password -> paste + OK (SecurityAgent only)"
SERVICE = "admin-autotype"
DELAY_MS = 300


def shell_cmd() -> str:
    return f"/usr/bin/security find-generic-password -s {SERVICE} -w | /usr/bin/pbcopy"


def rule(chord: str, delay_ms: int = DELAY_MS) -> dict:
    parts = [p.strip() for p in chord.split("+") if p.strip()]
    key, mods = parts[-1], parts[:-1]
    return {
        "description": DESC,
        "manipulators": [{
            "type": "basic",
            "from": {"key_code": key,
                     "modifiers": {"mandatory": mods} if mods else {}},
            "conditions": [{"type": "frontmost_application_if",
                            "bundle_identifiers": [r"^com\.apple\.SecurityAgent$"]}],
            "to": [{"shell_command": shell_cmd()}],
            "parameters": {"basic.to_delayed_action_delay_milliseconds": delay_ms},
            "to_delayed_action": {
                "to_if_invoked": [
                    {"key_code": "v", "modifiers": ["command"]},
                    {"key_code": "return"},
                ],
                "to_if_canceled": [],
            },
        }],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--chord", default="ctrl+alt+cmd+p")
    ap.add_argument("--delay-ms", type=int, default=DELAY_MS)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--remove", action="store_true")
    a = ap.parse_args()

    r = rule(a.chord, a.delay_ms)

    if a.dry_run:
        print(json.dumps(r, ensure_ascii=False, indent=2))
        return

    if not os.path.exists(KJ):
        print(f"找不到 {KJ}\n先安装并启动一次 Karabiner-Elements（它会生成该文件），再重跑本脚本。",
              file=sys.stderr)
        raise SystemExit(2)

    cfg = json.load(open(KJ, encoding="utf-8"))
    prof = next((p for p in cfg.get("profiles", []) if p.get("selected")),
                (cfg.get("profiles") or [{}])[0])
    rules = prof.setdefault("complex_modifications", {}).setdefault("rules", [])
    rules[:] = [x for x in rules if x.get("description") != DESC]
    if not a.remove:
        rules.append(r)

    tmp = KJ + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    os.chmod(tmp, 0o600)
    os.replace(tmp, KJ)
    print(("已移除规则: " if a.remove else "已写入规则: ") + KJ)


if __name__ == "__main__":
    main()