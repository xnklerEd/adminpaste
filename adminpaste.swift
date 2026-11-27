// adminpaste — 把管理员密码"按需"放进剪贴板，由你自己按 ⌘V 粘贴
//
// 两条触发路径：
//   1) armOnSecurityAgent: com.apple.SecurityAgent 成为前台 App 时自动把密码写入剪贴板。
//      不依赖键盘事件，所以授权框一出现密码就在剪贴板里。
//   2) 全局组合键 (Carbon RegisterEventHotKey)：默认拒绝，只在白名单 App 里生效；
//      若该进程拿到辅助功能权限，还会进一步要求"焦点确实是密码框"才放行。
//
// 安全约束：
//   - 秘密只存登录钥匙串，运行时才读，磁盘无明文
//   - 剪贴板在"当初 arm 的那个 App 离开前台"或超时后清空（仅当没被别的内容覆盖）

import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox

let configPath = ("~/.config/adminpaste/config.json" as NSString).expandingTildeInPath

struct Config: Decodable {
    var service: String = "admin-autotype"
    var key: String = "p"
    var modifiers: [String] = ["control", "option", "command"]
    var clearAfterSeconds: Int = 30
    var armOnSecurityAgent: Bool = true
    var securityAgentBundleID: String = "com.apple.SecurityAgent"
    var logFile: String = "~/.local/state/adminpaste.log"
    var pokeFile: String = "~/.local/state/adminpaste.poke"
    // 热键白名单：只有这些 App 在前台时组合键才生效。默认拒绝，其余一律无效。
    var allowedBundleIDs: [String] = [
        "com.apple.SecurityAgent",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
    ]
    // 辅助功能权限可用时，额外要求焦点元素是密码框（AXSecureTextField）
    var requireSecureFieldWhenPossible: Bool = true
    // 这些 App 豁免焦点校验：终端的密码提示在 AX 眼里就是普通文本区，无法区分
    var secureFieldCheckExemptBundleIDs: [String] = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
    ]
    // 用完把剪贴板还原成覆盖前的内容（原本为空就还原为空）
    var restoreClipboardAfterUse: Bool = true
    // 快照上限：超过就不快照，用完直接清空（避免复制大文件图片时吃内存）
    var maxSnapshotBytes: Int = 4_000_000

    enum CodingKeys: String, CodingKey {
        case service, key, modifiers, clearAfterSeconds, armOnSecurityAgent
        case securityAgentBundleID
        case logFile = "log"
        case pokeFile
        case allowedBundleIDs
        case requireSecureFieldWhenPossible
        case secureFieldCheckExemptBundleIDs
        case restoreClipboardAfterUse
        case maxSnapshotBytes
    }

    // 缺字段时用默认值，而不是整体退回默认（Swift 合成的 init 不会套用属性默认值）
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.service = try c.decodeIfPresent(String.self, forKey: .service) ?? self.service
        self.key = try c.decodeIfPresent(String.self, forKey: .key) ?? self.key
        self.modifiers = try c.decodeIfPresent([String].self, forKey: .modifiers) ?? self.modifiers
        self.clearAfterSeconds = try c.decodeIfPresent(Int.self, forKey: .clearAfterSeconds) ?? self.clearAfterSeconds
        self.armOnSecurityAgent = try c.decodeIfPresent(Bool.self, forKey: .armOnSecurityAgent) ?? self.armOnSecurityAgent
        self.securityAgentBundleID = try c.decodeIfPresent(String.self, forKey: .securityAgentBundleID) ?? self.securityAgentBundleID
        self.logFile = try c.decodeIfPresent(String.self, forKey: .logFile) ?? self.logFile
        self.pokeFile = try c.decodeIfPresent(String.self, forKey: .pokeFile) ?? self.pokeFile
        self.allowedBundleIDs = try c.decodeIfPresent([String].self, forKey: .allowedBundleIDs) ?? self.allowedBundleIDs
        self.requireSecureFieldWhenPossible = try c.decodeIfPresent(Bool.self, forKey: .requireSecureFieldWhenPossible) ?? self.requireSecureFieldWhenPossible
        self.secureFieldCheckExemptBundleIDs = try c.decodeIfPresent([String].self, forKey: .secureFieldCheckExemptBundleIDs) ?? self.secureFieldCheckExemptBundleIDs
        self.restoreClipboardAfterUse = try c.decodeIfPresent(Bool.self, forKey: .restoreClipboardAfterUse) ?? self.restoreClipboardAfterUse
        self.maxSnapshotBytes = try c.decodeIfPresent(Int.self, forKey: .maxSnapshotBytes) ?? self.maxSnapshotBytes
    }
}

let keyCodes: [String: Int] = [
    "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
    "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
    "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
    "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
    "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
    "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
    "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
    "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
    "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
    "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    "space": kVK_Space, "return": kVK_Return, "tab": kVK_Tab,
    "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4,
    "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
    "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
]

func modifierMask(_ names: [String]) -> UInt32 {
    var mask: UInt32 = 0
    for n in names {
        switch n.lowercased() {
        case "cmd", "command": mask |= UInt32(cmdKey)
        case "opt", "option", "alt": mask |= UInt32(optionKey)
        case "ctrl", "control": mask |= UInt32(controlKey)
        case "shift": mask |= UInt32(shiftKey)
        default: FileHandle.standardError.write("unknown modifier: \(n)\n".data(using: .utf8)!)
        }
    }
    return mask
}

var cfg = Config()
var cfgProblem: String?
if let data = FileManager.default.contents(atPath: configPath) {
    do { cfg = try JSONDecoder().decode(Config.self, from: data) }
    catch { cfgProblem = "config decode failed (\(error)); using defaults" }
} else {
    cfgProblem = "config not found at \(configPath); using defaults"
}

let logPath = (cfg.logFile as NSString).expandingTildeInPath
func logLine(_ s: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "\(ts) \(s)\n"
    FileHandle.standardError.write(line.data(using: .utf8)!)
    try? FileManager.default.createDirectory(
        atPath: (logPath as NSString).deletingLastPathComponent,
        withIntermediateDirectories: true)
    if let fh = FileHandle(forWritingAtPath: logPath) {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        fh.closeFile()
    } else {
        try? line.write(toFile: logPath, atomically: true, encoding: .utf8)
    }
}

func readPassword(service: String) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = ["find-generic-password", "-s", service, "-w"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    do { try p.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { return nil }
    var s = String(data: data, encoding: .utf8) ?? ""
    if s.hasSuffix("\n") { s.removeLast() }
    return s.isEmpty ? nil : s
}

var lastArm = Date.distantPast
var lastCopiedChangeCount: Int?
var armedForBundleID: String?

// 覆盖剪贴板前的快照：区分"原本为空"/"已快照"/"太大或读不了"
enum ClipRestore {
    case empty
    case items([[(NSPasteboard.PasteboardType, Data)]])
    case skip
}

var pendingRestore: ClipRestore?

func snapshotClipboard(limitBytes: Int) -> ClipRestore {
    let pb = NSPasteboard.general
    guard let objs = pb.pasteboardItems, !objs.isEmpty else { return .empty }
    var entries: [[(NSPasteboard.PasteboardType, Data)]] = []
    var total = 0
    for obj in objs {
        var entry: [(NSPasteboard.PasteboardType, Data)] = []
        for t in obj.types {
            guard let d = obj.data(forType: t) else { continue }
            total += d.count
            if total > limitBytes { return .skip }
            entry.append((t, d))
        }
        if !entry.isEmpty { entries.append(entry) }
    }
    // 只有一个空字符串项（`: | pbcopy` 的效果）也算空
    let hasRealContent = entries.contains { $0.contains { !$0.1.isEmpty } }
    return hasRealContent ? .items(entries) : .empty
}

func restoreClipboard(_ snap: ClipRestore) -> String {
    let pb = NSPasteboard.general
    switch snap {
    case .empty:
        pb.clearContents()
        return "原剪贴板为空，已还原为空"
    case .skip:
        pb.clearContents()
        return "原剪贴板过大或无法读取，已清空（不还原）"
    case .items(let entries):
        pb.clearContents()
        var newItems: [NSPasteboardItem] = []
        for entry in entries {
            let it = NSPasteboardItem()
            for (t, d) in entry { it.setData(d, forType: t) }
            newItems.append(it)
        }
        if newItems.isEmpty {
            pb.clearContents()
            return "原剪贴板内容无法重建，已清空（不还原）"
        }
        pb.writeObjects(newItems)
        return "已还原原剪贴板（\(newItems.count) 项）"
    }
}

func clearIfOurs(reason: String) {
    armedForBundleID = nil
    guard let c = lastCopiedChangeCount else { return }
    if NSPasteboard.general.changeCount == c {
        lastCopiedChangeCount = nil
        let snap = pendingRestore ?? .skip
        pendingRestore = nil
        logLine("\(reason): \(restoreClipboard(snap))")
    }
}

func fire(_ reason: String) {
    // 防抖：授权框激活通知可能连发
    if Date().timeIntervalSince(lastArm) < 1.0 { return }
    lastArm = Date()
    guard let pw = readPassword(service: cfg.service) else {
        logLine("\(reason) but keychain item '\(cfg.service)' missing/unreadable")
        return
    }
    let pb = NSPasteboard.general
    // 覆盖前先快照原剪贴板；若当前内容还是我们上次放的密码，保留既有快照别把密码当"原件"
    let currentChange = pb.changeCount
    if !(lastCopiedChangeCount == currentChange && pendingRestore != nil) {
        pendingRestore = cfg.restoreClipboardAfterUse
            ? snapshotClipboard(limitBytes: cfg.maxSnapshotBytes)
            : .skip
    }
    // 打上 concealed 标记：Alfred / Raycast / Maccy 等剪贴板历史工具看到它就不会记录
    let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    pb.clearContents()
    pb.declareTypes([.string, concealed], owner: nil)
    pb.setString(pw, forType: .string)
    pb.setData(Data(), forType: concealed)
    let count = pb.changeCount
    lastCopiedChangeCount = count
    armedForBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    logLine("\(reason): copied \(pw.count) chars to clipboard "
            + "(armed for \(armedForBundleID ?? "?"), restores in \(cfg.clearAfterSeconds)s or when that app leaves frontmost)")
    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(max(1, cfg.clearAfterSeconds))) {
        if NSPasteboard.general.changeCount == count {
            clearIfOurs(reason: "timeout \(cfg.clearAfterSeconds)s")
        }
    }
}

// ---- 焦点元素是否为密码框（需要辅助功能权限；拿不到权限返回 nil） ----
func focusedElementIsSecureField() -> Bool? {
    let sys = AXUIElementCreateSystemWide()
    var focusedRaw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focusedRaw) == .success,
          let raw = focusedRaw else { return nil }
    let el = unsafeBitCast(raw, to: AXUIElement.self)
    var subRaw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &subRaw) == .success,
          let sub = subRaw as? String else { return nil }
    return sub == "AXSecureTextField"
}

// 返回 nil 表示放行，否则返回拒绝原因
func hotkeyGuard() -> String? {
    let front = NSWorkspace.shared.frontmostApplication
    let bid = front?.bundleIdentifier ?? "(unknown)"
    let name = front?.localizedName ?? "-"
    if !cfg.allowedBundleIDs.contains(bid) {
        return "frontmost=\(name)/\(bid) 不在 allowedBundleIDs 白名单里"
    }
    if cfg.requireSecureFieldWhenPossible && AXIsProcessTrusted()
        && !cfg.secureFieldCheckExemptBundleIDs.contains(bid) {
        switch focusedElementIsSecureField() {
        case .some(false):
            return "frontmost=\(name)/\(bid) 的焦点不是密码框（明文区域）"
        case .none:
            logLine("AX 探测无结果，退回按 App 白名单放行")
        case .some(true):
            break
        }
    }
    return nil
}

// `--guard` 在启动时打印一次放行判定然后退出，用于不按键就能验证白名单逻辑
if CommandLine.arguments.contains("--guard") {
    print("guard: " + (hotkeyGuard() ?? "ALLOW"))
    exit(0)
}

// ---- 路径 1：授权框成为前台时自动 arm ----
if cfg.armOnSecurityAgent {
    NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification,
        object: nil, queue: .main
    ) { note in
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == cfg.securityAgentBundleID else { return }
        fire("SecurityAgent frontmost -> auto-arm")
    }
}

// arm 过的那个 App 一离开前台（授权框关闭、切走终端）就立刻撤掉剪贴板里的密码
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didDeactivateApplicationNotification,
    object: nil, queue: .main
) { note in
    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
          let armed = armedForBundleID,
          app.bundleIdentifier == armed else { return }
    clearIfOurs(reason: "\(armed) left frontmost")
}

// ---- 关键：让进程成为真正的 App（否则 Carbon 热键事件不会被投递） ----
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
let ttStatus = TransformProcessType(&psn, ProcessApplicationTransformState(kProcessTransformToUIElementApplication))
logLine("NSApplication ready; activationPolicy=accessory transformProcessType=\(ttStatus)")

// ---- 路径 2：全局组合键（默认拒绝，白名单 + 焦点校验） ----
let hotKeyHandler: EventHandlerUPP = { _, _, _ in
    if let denial = hotkeyGuard() {
        logLine("hotkey IGNORED: \(denial)")
        return noErr
    }
    fire("hotkey")
    return noErr
}

var registered = false
if let keyCode = keyCodes[cfg.key.lowercased()] {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                             eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, nil)
    var hotKeyRef: EventHotKeyRef?
    let hkID = EventHotKeyID(signature: OSType(0x41445054), id: 1) // 'ADPT'
    let status = RegisterEventHotKey(UInt32(keyCode), modifierMask(cfg.modifiers),
                                     hkID, GetApplicationEventTarget(), 0, &hotKeyRef)
    if status == noErr {
        registered = true
    } else {
        logLine("RegisterEventHotKey failed: \(status)")
    }
} else {
    logLine("unknown trigger key: \(cfg.key) (hotkey disabled)")
}

// ---- 自检通道：往 pokeFile 写入任意内容即触发一次（不受白名单限制） ----
let pokePath = (cfg.pokeFile as NSString).expandingTildeInPath
Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
    if FileManager.default.fileExists(atPath: pokePath) {
        try? FileManager.default.removeItem(atPath: pokePath)
        fire("poke")
    }
}

logLine("started; hotkey=\(registered ? cfg.modifiers.joined(separator: "+") + "+" + cfg.key : "disabled") "
        + "autoArm=\(cfg.armOnSecurityAgent) service=\(cfg.service)")
logLine("policy: allowlist=\(cfg.allowedBundleIDs.joined(separator: ",")) "
        + "requireSecureField=\(cfg.requireSecureFieldWhenPossible) AXTrusted=\(AXIsProcessTrusted())")
if let p = cfgProblem { logLine(p) }

if CommandLine.arguments.contains("--once") {
    fire("--once")
    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { exit(0) }
}

app.run()