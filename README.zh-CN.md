# adminpaste — 系统授权框里"按一次粘贴"代替手打管理员密码

在需要管理员密码的 macOS 授权框（`SecurityAgent`）里：**密码已经躺在剪贴板里，你只需按 ⌘V**。
目标是把"手打一串密码"变成一次按键，同时保留密码框、保留你亲手确认的那一下。

不需要管理员权限、不需要关 SIP、不需要 Karabiner、不需要辅助功能权限。密码只存在登录钥匙串里。

## 为什么只能做到"你按 ⌘V"

macOS 对授权框的密码框启用了 Secure Keyboard Entry：任何进程注入的按键（AppleScript
`keystroke`、`CGEventPost`、cliclick、Shortcuts"键入文本"、密码管理器填充）都会被系统丢弃；
自建虚拟 HID 键盘需要 Apple 特批的 `com.apple.developer.hid.virtual.device`，SIP 开启时拿不到。
所以"完全自动填进框"在这台机器上是死路。

能做的极限是：**把密码准备到剪贴板，粘贴由你发起**。授权框接受 ⌘V，这一步就成了。

## 安装

```bash
git clone https://github.com/xnklerEd/adminpaste.git
cd adminpaste
./install.sh
```

或用 [Releases](../../releases) 里的预编译包（arm64 + x86_64 通用二进制，不需要开发工具）：

```bash
unzip adminpaste-universal.zip && cd adminpaste-universal
./install.sh
```

源码编译需要 Command Line Tools：`xcode-select --install`。

`install.sh` 会：

1. 装二进制到 `~/bin/adminpaste`（包内是 arm64+x86_64 通用二进制；架构不匹配时改用 `swiftc` 就地编译）
2. 写配置 `~/.config/adminpaste/config.json`
3. 装 LaunchAgent `~/Library/LaunchAgents/com.local.adminpaste.plist`（登录自启、挂掉自动拉起）
4. 提示你输入这台 Mac 的管理员密码，存进登录钥匙串（不回显、不写盘、不进 shell 历史）

依赖：macOS 11+（Apple Silicon / Intel 均可）。如果用包内二进制，**不需要**开发工具。

## 用法

| 场景 | 操作 |
|---|---|
| 系统授权框（"xxx 想要进行更改"） | 框弹出时密码已自动在剪贴板 → **⌘V** → 回车 |
| 终端里的 `sudo` / `ssh` 口令 | **⌃⌥⌘P** → **⌘V** |
| 其它任何 App | ⌃⌥⌘P **无效**（白名单外一律不生效，日志记 `hotkey IGNORED`） |

还原时机：**当初放密码的那个 App 一离开前台**（授权框关闭、或你切走终端），
或 30 秒超时——两种情况都会把剪贴板**还原成覆盖前的内容**：原本为空就还原为空，
原本是一段文字/图片就原样写回（多类型项、多条目都保留）。如果期间你自己复制了别的东西，
不会去覆盖它。剪贴板里的密码带 `org.nspasteboard.ConcealedType` 标记，
Alfred / Raycast / Maccy 等剪贴板历史工具不会把它收进历史库。

## 它是怎么工作的

- **触发方式 1（自动）**：用 `NSWorkspace` 的 App 激活通知监听 `com.apple.SecurityAgent`。
  这条不依赖键盘事件，所以授权框一出现密码就到剪贴板。
- **触发方式 2（手动）**：Carbon `RegisterEventHotKey` 注册 ⌃⌥⌘P。选它是因为
  **Carbon 热键不受 Secure Input 影响**（用 CGEventTap 的 App 在密码框出现时会失效），
  而且不需要辅助功能权限。
- **默认拒绝**：热键只在前台 App 属于 `allowedBundleIDs` 时才生效；若该进程拿到了辅助功能权限，
  还会额外校验焦点元素是否为 `AXSecureTextField`。

## 两个必须知道的坑（踩过）

1. **进程必须有 App 身份，否则热键静默失效。** 裸 CLI 进程调用 `RegisterEventHotKey` 会返回
   `noErr`，但事件投递到"应用事件目标"时没有任何 app 记录接收它，表现就是"注册成功、按了没反应"。
   必须先 `NSApplication.shared` + `setActivationPolicy(.accessory)`，再注册热键，最后 `app.run()`。
   验证：`lsappinfo find pid=$(pgrep -f bin/adminpaste)` 应输出 `type="UIElement"`。

2. **合成按键触发不了任何系统全局热键。** 用 System Events 合成 ⌘Space 连 Spotlight 都打不开，
   所以这类功能只能用**真实按键**验证，别用 AppleScript / IOHIDPostEvent 去测（会得出错误结论）。

## 终端里的残余风险

终端里的密码提示（`sudo`、`ssh`）在辅助功能接口眼里就是普通文本区，无法与普通命令提示符区分。
因此在终端里这个热键是"整个 App 范围内有效"：

- 在普通命令提示符下误按 ⌃⌥⌘P 再 ⌘V，密码会出现在命令行上，回车执行还会进 shell 历史。
- 缓解：别在终端随手按；用完切走窗口即清空。

## 配置 `~/.config/adminpaste/config.json`

| 字段 | 默认 | 说明 |
|---|---|---|
| `service` | `admin-autotype` | 钥匙串 generic password 的 service 名 |
| `key` / `modifiers` | `p` / ctrl+option+cmd | 触发键；`key` 支持 a-z、0-9、space、return、tab、f1-f12 |
| `clearAfterSeconds` | `30` | 超时清空 |
| `armOnSecurityAgent` | `true` | 授权框成为前台时自动放密码到剪贴板 |
| `allowedBundleIDs` | SecurityAgent / Terminal / iTerm2 | 热键白名单，不在名单里的 App 一律无效 |
| `requireSecureFieldWhenPossible` | `true` | 有辅助功能权限时额外要求焦点是密码框 |
| `secureFieldCheckExemptBundleIDs` | Terminal / iTerm2 | 豁免上面那项校验（终端无法区分提示类型） |
| `restoreClipboardAfterUse` | `true` | 用完还原覆盖前的剪贴板内容（`false` 则用完直接清空） |
| `maxSnapshotBytes` | `4000000` | 快照上限；超过就不快照，用完直接清空（避免大文件/图片吃内存） |
| `log` | `~/.local/state/adminpaste.log` | 触发日志 |

改完配置：`launchctl kickstart -k gui/$UID/com.local.adminpaste`

## 诊断

```bash
tail -5 ~/.local/state/adminpaste.log     # started / policy / auto-arm / hotkey / poke / cleared
tail -20 ~/.local/state/adminpaste.err    # 启动期报错
~/bin/adminpaste --guard                  # 打印此刻组合键会不会放行（不用按键）
printf x > ~/.local/state/adminpaste.poke # 自检通道：0.5 秒内触发一次，不走键盘
bash test-dialog.sh                       # 弹真实授权框做端到端测试
```

`policy:` 行会打印当前白名单、字段校验开关、以及 `AXTrusted`（是否拿到辅助功能权限）。

## 卸载

```bash
bash uninstall.sh
```

## 换密码

```bash
security delete-generic-password -s admin-autotype
security add-generic-password -s admin-autotype -a "$USER" -w   # 交互输入
```