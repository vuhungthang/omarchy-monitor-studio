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
| `node ProfileMatcher.js` | Compare normalized connected-display identities with saved profiles |

The scripts also use Bash, Node.js, `jq`, `awk`, `sha256sum`, `readlink`, `head`,
`stat`, `chmod`, `mktemp`, `mkdir`, `mv`, `rm`, `rmdir`, `sleep`, and `setsid`.

## Filesystem writes

| Path | Contents | Lifetime |
|---|---|---|
| `${XDG_RUNTIME_DIR:-/tmp}/omarchy-monitor-studio/` | Mode `0700` preview transactions and before/proposed JSON | Removed after Keep/Revert; stale data disappears with the runtime directory |
| `${XDG_RUNTIME_DIR:-/tmp}/omarchy-monitor-studio-edid/` | Mode `0600` EDID hash/native-resolution cache | Runtime cache |
| `${XDG_STATE_HOME:-~/.local/state}/omarchy/monitor-studio/profiles.json` | Mode `0600` versioned profile store (schema v2): profiles, connected sets, topology, workspace assignments | Persists until the user removes it |
| `${XDG_STATE_HOME:-~/.local/state}/omarchy/monitor-studio/layout.json` | Legacy schema-v1 layout, retained as a recovery backup after migration | Removed only after the first confirmed v2 Keep; pre-migration files are never deleted without a match |

Writes use private permissions and same-directory temporary files followed by
atomic rename. Runtime paths must be user-owned, non-symlink directories;
`XDG_RUNTIME_DIR` is additionally required to deny group and other access. The
plugin does not edit `monitors.lua`, `hyprland.lua`, shell configuration, or
package-owned files.

### Schema-v2 profile contents

Each profile has a validated ID/name, sorted connected set, identity evidence,
timestamps, and one active topology. A topology contains the complete monitor
records, workspace assignments, a persistent anchor, and optional confirmed
variants for Internal only, External only, Extend, and Duplicate. Signed
coordinates are stored relative to the anchor. Existing schema-v2 profiles
without anchors or variants remain readable and gain those fields on a later
confirmed Keep.

## Input validation

- Monitor identifiers allow only ASCII letters, digits, `.`, `_`, `:`, and `-`.
- Signed anchor-relative coordinates are integers within `-100000..100000`.
- Width and height are positive integers capped at `32768`.
- Refresh rates must be positive and no greater than `1000`.
- Scale must be within `0.5..4`.
- Display transforms must be integers within Hyprland's supported `0..7` range.
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
3. **Keep** claims the transaction, atomically saves the confirmed topology
   into the versioned profile store (schema v2), reloads Hyprland, reapplies
   saved monitor/workspace state, and removes the transaction. The first
   confirmed v2 Keep also retires the retained schema-v1 backup.
4. **Revert**, closing the panel, or watchdog expiry claims the transaction,
   reapplies the previous live monitor state, and removes the transaction.
5. A claim directory prevents Keep and Revert from winning simultaneously.
6. Monitor arrival/removal events are coalesced for a one-second quiet window
   (three-second maximum). If the hardware generation changes during a preview,
   the transaction is claimed and canceled without writing profile state. The
   recovery path restores compatible before-settings for outputs that remain,
   retains freshly enumerated settings for changed/new outputs, and guarantees
   at least one currently available display stays enabled.
7. `omarchy shell omarchy.monitor revert` invokes `revert-pending` without
   depending on the panel's visible screen. It races through the same atomic
   claim as Keep, the panel Revert, and the watchdog; repeated calls are safe.
   No global binding is installed—users may bind that command explicitly.

## Guarded restore and migration

- Restore re-enumerates the current displays and applies the active profile
  only when every saved identity is an exact match. A moved, weak, ambiguous,
  or new set performs no `hyprctl eval` and reports a recoverable status
  instead. Connector-only legacy profiles retain their original exact-name
  behavior until their first confirmed v2 Keep records strong identities.
- Confirming a moved layout requires an explicit `update-profile` or
  `fork-profile` choice. Forking preserves the source profile; updating changes
  only the selected profile. Neither path modifies unrelated profiles.
- Profile rename, selection, duplication, and confirmed deletion mutate only
  `profiles.json`; they never invoke `hyprctl` or change the live topology.
- Schema-v1 `layout.json` is imported atomically as a legacy profile only when
  its monitor set exactly matches the current connected set. Mismatched or
  malformed v1/v2 state is never applied and never overwritten; the v1 backup
  remains until the first confirmed v2 Keep.

Match status is deliberately visible: `exact` may restore, `moved` requires an
update-or-fork decision and fresh mode validation, `weak` and `ambiguous`
require Identify/manual confirmation, and `new` creates a separate connected-
set profile. Discovery and Refresh never write profile state.

## Failure and recovery

- Invalid input exits before running `hyprctl` or writing persistent state.
- A failed preview remains uncommitted and reports an error in the panel.
- A failed Keep leaves its transaction available rather than silently claiming
  success.
- A hot-plug during confirmation cannot be kept accidentally; the stable
  post-burst snapshot cancels the preview and restores a usable live topology.
- `hyprctl reload` returns to the user's Hyprland configuration without reading
  the plugin state file.
- Removing the saved JSON prevents the plugin from restoring it on its next
  load.

Structured reason codes turn missing outputs, unavailable modes, compositor
adjustments, and runtime rejections into actionable plain-text UI. Link/GPU
bandwidth cannot always be predicted from advertised modes; those failures are
learned from the compositor during preview and remain protected by rollback.

See [`acceptance-matrix.md`](acceptance-matrix.md) for fixture, transaction,
and available-hardware release evidence.

## Known operational limitation

The plugin restores kept state when its enabled bar widget is instantiated, not
before the Omarchy shell starts. At login, Hyprland may briefly use the user's
ordinary monitor rules before Monitor Studio reapplies its state.
