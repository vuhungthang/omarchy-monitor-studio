# Hyprland Topology Capability Contract

Frozen against **Hyprland 0.56.2** (`hyprctl version`, verified locally). This
document records the exact runtime operations Monitor Studio depends on, how
each fails, and the fallback for each topology operation. Code must not grow
dependencies on Hyprland behavior that is not listed here. When a capability
probe fails at runtime, the degraded behavior in the last column applies.

## Enumeration and reporting

| Capability | Interface | Notes |
|---|---|---|
| Monitor enumeration | `hyprctl monitors all -j` | Includes disabled outputs (`disabled: true`), mirroring (`mirrorOf`), advertised modes (`availableModes`), EDID make/model/serial, physical size, transform, scale, and logical `x`/`y` |
| Workspace placement | `hyprctl workspaces -j`, `hyprctl workspacerules -j` | Used for workspace assignment persistence |
| Runtime configuration | `hyprctl eval "hl.monitor({...})"` | Single-argument Lua; no `hyprctl keyword monitor` (hyprlang is deprecated since 0.55) |
| Workspace rules | `hyprctl eval "hl.workspace_rule({...})"` | Runtime rules; cleared by `hyprctl reload` |

Post-apply reporting always re-enumerates `hyprctl monitors all -j` and
compares the actual result with the proposal (adjusted positions, compositor
fallback modes, effective scales). The generations in the snapshot library are
derived from this enumeration and are local optimistic-concurrency tokens only.

## Topology operations

| Operation | Command | Failure behavior | Fallback / degraded behavior |
|---|---|---|---|
| Mode + refresh | `hl.monitor({ output = NAME, mode = "WxH@Hz", ... })` | Invalid mode string is rejected by Lua layer; unsupported mode makes Hyprland keep or auto-pick a mode and log a warning | Validate requested mode against `availableModes` before apply; post-apply reconcile reports a `mode-adjusted` reason |
| Position | `position = "XxY"` | Overlapping positions produce a warning, layout still applies | Validate non-overlap in the topology model; normalize anchor-relative coordinates to compositor space at the apply boundary |
| Signed positions | Native (`-1920x0` is valid; inverse-Y cartesian) | n/a | Store signed anchor-relative coordinates in profiles; translate only at apply |
| Scale | `scale = N` | Non-dividing scale logs "Invalid scale" warning and falls back | `Model.cleanScale` quantizes to a dividing scale pre-apply; reconcile reports `scale-adjusted` |
| Transform | `transform = 0..7` | Out-of-range rejected | Validation clamps 0–7 |
| Disable | `hl.monitor({ output = NAME, disabled = true })` | None at compositor level; output leaves the layout and windows migrate | Last-display invariant enforced in the model (never disable the only enabled output); disabled outputs keep appearing in `monitors all` with `disabled: true` so prior settings survive for re-enable |
| Enable | Full `hl.monitor({ output = NAME, mode, position, scale, ... })` without `disabled` | Mode may be unavailable after re-plug | Revalidation against fresh enumeration before apply |
| Mirroring | `mirror = SOURCE` on the target output | Heterogeneous panels may stretch or crop; no compositor letterboxing or re-render for the mirrored image | Use a common advertised mode for matching aspects; preserve each output's current advertised mode for mixed aspects or disjoint mode sets; disclose the compromise before preview |
| Unmirror | Set `mirror = ""` in the target's full rule | Omitting the field can preserve a runtime mirror relationship | Explicit empty mirror on every ordinary/source output; exact before-topology restore |
| Refresh enumeration | Poll `hyprctl monitors all -j` | n/a | Debounce (1 s quiet, 3 s max) plus recovery polling |

## Events

Quickshell's `Hyprland` singleton exposes live monitor state to the shell
(`Hyprland.monitors`, `Hyprland.workspaces` in Omarchy's shell build). Monitor
arrival/departure is observed via monitor-list change signals when present.
Because this surface is not frozen by a stability contract, Monitor Studio
treats it as an optimization only:

- Event signal available: signal triggers the debounced re-enumeration.
- Signal missing or silent: a recovery polling interval plus the manual
  Refresh action re-enumerate.

## Identify overlays

Quickshell instantiates the bar per screen, so an overlay window per active
screen is constructable with trusted static text (`Text.PlainText` only; the
connector label is the only monitor-derived string and it is allowlist
validated). Degraded behavior: if a screen cannot host an overlay, Identify
falls back to highlighting the connected-displays rows in the panel.

## Emergency revert IPC

Omarchy exposes `omarchy shell <target> <method>` for shell IPC. The panel
already owns the `omarchy.monitor` IpcHandler, so a `revert` method can claim
and revert the pending transaction without installing or editing any user
keybinding. Degraded behavior: if the shell is not running, the detached
watchdog still reverts on expiry; `hyprctl reload` remains the final manual
recovery.

## Assumption validation results (Task 1)

1. **Exact mirror and enable/disable via `hyprctl eval`: confirmed** for
   0.56.2 — `disabled`, `mirror`, signed `position`, `mode`, `scale`,
   `transform` are all runtime `hl.monitor` fields.
2. **Identify overlay per screen: confirmed** constructable; must use
   plain-text sinks (see the untrusted-text audit).
3. **IPC revert without keybinding edits: confirmed** via
   `omarchy shell omarchy.monitor revert`.

## Sanitized fixtures

`tests/fixtures/monitors/` contains hyprctl-shaped enumerations used by the
snapshot, matching, and apply tests so no test depends on live hardware:

| Fixture | Covers |
|---|---|
| `internal-external.json` | Laptop plus one docked external, mixed DPI |
| `three-display.json` | Three-output extended arrangement, serialized externals |
| `disabled-external.json` | External physically attached but disabled |
| `mirrored.json` | One output mirroring another |
| `identical-serial-less.json` | Twin monitors with identical weak EDID identity |
| `partial-dock.json` | Transitional mid-dock enumeration with one reduced mode |

Unknown or unsupported capabilities at runtime degrade to observation-only
mode: enumeration continues, no topology command is sent, and the panel reports
why topology editing is unavailable.
