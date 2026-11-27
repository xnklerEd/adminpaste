# adminpaste

Stop typing your admin password into macOS authorization dialogs. Press **⌘V** instead.

When macOS shows its system authorization prompt (`SecurityAgent` — "X wants to make changes"),
`adminpaste` has already put your admin password in the clipboard (without the concealed-type
flag, so clipboard-history utilities ignore it). You press ⌘V, hit return, done. When the dialog
closes, the clipboard is **restored to whatever it was before**, not just cleared.

No admin rights, no SIP changes, no Karabiner, no Accessibility permission. The password lives
only in your login keychain — never in a config file, never in a log.

[中文说明](README.zh-CN.md)

## Why it can't just fill the field for you

The password field in the authorization dialog runs under **Secure Keyboard Entry**.
Everything userspace tries is discarded by the kernel: AppleScript `keystroke`, `CGEventPost`,
`cliclick`, Shortcuts "Type Text", password-manager autofill. Building your own virtual HID
keyboard needs Apple's restricted entitlement `com.apple.developer.hid.virtual.device`, which a
self-signed binary cannot get with SIP enabled (I measured it: `IOHIDUserDeviceCreate` returns nil).

So the ceiling for a userspace tool is: **prepare the clipboard, let the human paste**.
The dialog accepts ⌘V, which turns "type 17 characters" into one keystroke.

## Install

```bash
git clone https://github.com/xnklerEd/adminpaste.git
cd adminpaste
./install.sh
```

Or grab the prebuilt universal binary (arm64 + x86_64) from [Releases](../../releases) and run
`./install.sh` from that archive — no Xcode tooling needed then. Building from source needs
Command Line Tools (`xcode-select --install`).

`install.sh` puts `adminpaste` in `~/bin`, writes `~/.config/adminpaste/config.json`, installs a
LaunchAgent (starts at login, restarted if it dies), and asks once for the admin password to
store it in the login keychain.

## Usage

| Where | Do this |
|---|---|
| System authorization dialog | password is already in the clipboard → **⌘V** → return |
| `sudo` / `ssh` prompt in Terminal or iTerm2 | **⌃⌥⌘P** → **⌘V** |
| Any other app | ⌃⌥⌘P does **nothing** (allowlist, logged as `hotkey IGNORED`) |

Clipboard is restored when the armed app leaves the foreground (dialog closes, you switch away
from the terminal) or after 30 s — whichever comes first. If you copy something new in the
meantime, it is left alone.

## How it works

- **Auto-arm**: `NSWorkspace` activation notification for `com.apple.SecurityAgent`. No keyboard
  events involved, so it works while Secure Input is active.
- **Manual trigger**: Carbon `RegisterEventHotKey` (⌃⌥⌘P). Carbon hotkeys are **not** affected by
  Secure Input, unlike CGEventTap-based ones, and they need no Accessibility permission.
- **Default deny**: the hotkey only fires when the frontmost app is in `allowedBundleIDs`
  (SecurityAgent, Terminal, iTerm2). If the process happens to have Accessibility permission, an
  extra check requires the focused element to be `AXSecureTextField`.
- **Secret handling**: read from the login keychain at fire time via `security find-generic-password`;
  written to the pasteboard with `org.nspasteboard.ConcealedType`; the previous pasteboard
  contents are snapshotted in memory and written back afterwards (4 MB cap).

## Two traps that cost me an evening (worth knowing if you build something similar)

1. **A plain CLI process silently swallows global hotkeys.** `RegisterEventHotKey` returns `noErr`,
   the log says "hotkey registered", and nothing ever fires: without an app record in the
   WindowServer, `kEventHotKeyPressed` has nowhere to go. You must become an app first —
   `NSApplication.shared` + `setActivationPolicy(.accessory)`, *then* register, *then* `app.run()`.
   Check with `lsappinfo find pid=<pid>` (should print `type="UIElement"`).
2. **Synthetic key events cannot trigger system-wide hotkeys at all.** Synthesizing ⌘Space via
   System Events does not open Spotlight on current macOS. Hotkey code can only be validated with
   a real key press — AppleScript/IOHIDPostEvent tests produce false negatives.

## Residual risks — read this

- While the password is on the clipboard, **any app could read it**. That window is the dialog's
  lifetime (or 30 s). Mitigations in place: concealed type, restore-on-leave, no history capture.
- Auto-arm means any app that can summon a real authorization dialog gets the password armed
  before you consent. That is the deliberate trade-off; set `"armOnSecurityAgent": false` to
  require an explicit ⌃⌥⌘P instead.
- In terminals the hotkey is *app-wide*: a terminal's password prompt is just a text view to the
  Accessibility API, so pressing ⌃⌥⌘P at a plain shell prompt and pasting puts the password on
  your command line (and into shell history if you hit return). Don't.
- The password sits in your keychain as a generic password readable by `/usr/bin/security`.

## Configuration `~/.config/adminpaste/config.json`

| Key | Default | Meaning |
|---|---|---|
| `service` | `admin-autotype` | keychain generic-password service name |
| `key` / `modifiers` | `p` / control+option+command | trigger chord |
| `clearAfterSeconds` | `30` | restore the clipboard after this long |
| `armOnSecurityAgent` | `true` | auto-arm when the authorization dialog appears |
| `allowedBundleIDs` | SecurityAgent, Terminal, iTerm2 | hotkey allowlist; everything else is denied |
| `requireSecureFieldWhenPossible` | `true` | with Accessibility granted, require `AXSecureTextField` focus |
| `secureFieldCheckExemptBundleIDs` | Terminal, iTerm2 | skip that check (terminals can't distinguish prompts) |
| `restoreClipboardAfterUse` | `true` | restore the previous clipboard instead of clearing |
| `maxSnapshotBytes` | `4000000` | don't snapshot above this size; just clear |

After editing: `launchctl kickstart -k gui/$UID/com.local.adminpaste`

## Diagnostics

```bash
tail -5 ~/.local/state/adminpaste.log      # started / policy / auto-arm / hotkey / poke / restore
~/bin/adminpaste --guard                   # would the chord be allowed right now? (no keypress needed)
printf x > ~/.local/state/adminpaste.poke  # self-test trigger, bypasses the keyboard
./test-dialog.sh                           # end-to-end test against a real (harmless) dialog
```

## Uninstall

```bash
./uninstall.sh
```

## License

MIT. See [LICENSE](LICENSE).