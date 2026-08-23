# Security and Operations

## Execution boundary

Monitor Studio executes inside the long-running, unsandboxed Omarchy
Quickshell process. QML launches repository-local Bash scripts and installed
Omarchy/Hyprland commands. It does not elevate privileges or download code.

### Commands

| Command | Purpose |
|---|---|
| `hyprctl monitors all -j` | Read connected display state and modes |
| `hyprctl workspaces -j` | Read active workspace placement |
| `hyprctl workspacerules -j` | Read configured workspace rules |
| `hyprctl eval` | Preview, restore, and keep monitor/workspace Lua statements |
| `hyprctl reload` | Clear superseded runtime rules before reapplying kept state |
| `omarchy-brightness-display` | Read or set focused-display brightness |
| `omarchy-hyprland-monitor-scaling` | Read the current monitor scale |
| `omarchy-display-text-size` | Set Omarchy shell and GTK text size |
| `edid-decode` | Optionally read the native EDID resolution |

The scripts also use Bash, `jq`, `awk`, `sha256sum`, `readlink`, `head`,
`mktemp`, `mkdir`, `mv`, `rm`, `rmdir`, `sleep`, and `setsid`.

## Filesystem writes

| Path | Contents | Lifetime |
|---|---|---|
| `${XDG_RUNTIME_DIR:-/tmp}/omarchy-monitor-studio/` | Mode `0700` preview transactions and previous/proposed JSON | Removed after Keep/Revert; stale data disappears with the runtime directory |
| `${XDG_RUNTIME_DIR:-/tmp}/omarchy-monitor-studio-edid/` | Mode `0600` EDID hash/native-resolution cache | Runtime cache |
| `${XDG_STATE_HOME:-~/.local/state}/omarchy/monitor-studio/layout.json` | Mode `0600` last kept monitor and workspace state | Persists until the user removes it |

Writes use private permissions and same-directory temporary files followed by
atomic rename. The plugin does not edit `monitors.lua`, `hyprland.lua`, shell
configuration, or package-owned files.

## Input validation

- Monitor identifiers allow only ASCII letters, digits, `.`, `_`, `:`, and `-`.
- Coordinates are normalized non-negative integers within `0..100000`.
- Width and height are positive integers capped at `32768`.
- Refresh rates must be positive and no greater than `1000`.
- Scale must be within `0.5..4`.
- Workspace keys are limited to `1..10` and values use the monitor-identifier
  allowlist.
- Transaction identifiers use the same conservative identifier allowlist.

The script builds Lua only after validation and sends it as one argument to
`hyprctl eval`; it does not evaluate payloads as shell source.

## Display metadata rendering

Monitor make, model, and description fields can originate in external display
EDID data. They remain untrusted when transformed into friendly labels by the
UI model. Every QML `Text` sink that receives monitor-derived strings declares
`Text.PlainText`, preventing rich-text and resource markup interpretation.

The shared Omarchy `Button` tooltip renders with automatic text detection and
does not expose a format override. Monitor Studio therefore keeps EDID-derived
labels out of those tooltips and uses trusted static workspace guidance there.

## Apply/Keep/Revert transaction

1. **Apply** validates proposed and previous states, creates a private runtime
   transaction, and changes only the live monitor layout.
2. A detached watchdog waits 15 seconds.
3. **Keep** claims the transaction, atomically saves JSON, reloads Hyprland,
   reapplies saved monitor/workspace state, and removes the transaction.
4. **Revert**, closing the panel, or watchdog expiry claims the transaction,
   reapplies the previous live monitor state, and removes the transaction.
5. A claim directory prevents Keep and Revert from winning simultaneously.

## Failure and recovery

- Invalid input exits before running `hyprctl` or writing persistent state.
- A failed preview remains uncommitted and reports an error in the panel.
- A failed Keep leaves its transaction available rather than silently claiming
  success.
- `hyprctl reload` returns to the user's Hyprland configuration without reading
  the plugin state file.
- Removing the saved JSON prevents the plugin from restoring it on its next
  load.

## Known operational limitation

The plugin restores kept state when its enabled bar widget is instantiated, not
before the Omarchy shell starts. At login, Hyprland may briefly use the user's
ordinary monitor rules before Monitor Studio reapplies its state.
