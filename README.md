# Monitor Studio

Monitor Studio is an Omarchy Quattro bar plugin for arranging displays without
editing monitor coordinates by hand. Select a display in the visual layout to
change its resolution, refresh rate, rotation, or scale, drag displays to match
the physical desk, and assign numbered workspaces to a monitor.

The plugin is derived from Omarchy's built-in `omarchy.monitor` panel and keeps
its brightness, text-size, mirroring, and display-toggle controls.

## Features

- Responsive drag-and-drop arrangement for one, two, three, or many displays
- Full-screen arrangement editor for large and mixed-DPI layouts
- Friendly display names from monitor make/model information
- Per-display resolution, refresh-rate, rotation, and scale controls with
  EDID-based recommendations and refresh rates filtered for the selected
  resolution
- Workspace 1–10 assignment, with workspace 10 displayed as `0`
- A 15-second Apply/Keep/Revert preview before display changes are saved
- Identity-aware connected-set profiles with explicit match confidence
- Persistent anchor displays and signed coordinates
- Identify overlays, read-only Refresh, and transitional/disabled status
- Internal only, External only, Extend, and compatibility-checked Duplicate
  presets with remembered variants
- Automatic restoration only for an exact safe connected-set match

## Install

The public repository must exist before this command will work:

```bash
omarchy plugin add https://github.com/vuhungthang/omarchy-monitor-studio.git --enable
```

Omarchy installs third-party plugins disabled unless `--enable` is provided.
Review the repository before enabling it: shell plugins run unsandboxed with
your user permissions.

Because this plugin declares `omarchy.clonedFrom: "omarchy.monitor"`, enabling
it replaces the built-in monitor widget. Removing it restores the built-in
source and bar placement.

## Use

1. Open the display icon in the Omarchy bar.
2. Use **Identify** when connector labels are unclear, and **Refresh** after a
   dock, KVM, wireless, or virtual display changes.
3. Select a display, then arrange it, configure its mode, or assign workspaces;
   alternatively choose a topology preset.
4. Review the compatibility summary before duplicating unlike panels.
5. Select **Apply** to preview staged changes. Presets preview immediately.
6. Select **Keep** within 15 seconds. Select **Revert**, close the panel, or
   wait for the timer to restore the previous live layout.

If a preview makes the panel unreachable, invoke the independent shell IPC
from a terminal or launcher:

```bash
omarchy shell omarchy.monitor revert
```

For a keyboard escape hatch, add this binding yourself to your Hyprland user
configuration (Monitor Studio does not install or edit key bindings):

```text
bindd = SUPER SHIFT, BackSpace, Emergency display revert, exec, omarchy shell omarchy.monitor revert
```

Workspace-only changes are saved immediately when their section's Apply action
is selected. Arrangement, mode, rotation, scale, anchor, enable/disable, and
topology-preset changes use the confirmation timer.

## Profiles and matching

The schema-v2 store keeps a separate topology for each connected display set,
including identity evidence, modes, arrangement, workspaces, anchor, and
confirmed preset variants. Exact matches may restore automatically. A known
monitor that moved connectors must be explicitly updated or saved as a new
profile. Weak or ambiguous matches never overwrite a profile; use **Identify**
and verify connector assignments first.

Naming, selecting, and duplicating profiles do not apply a topology. Deleting
a profile requires confirmation and does not alter the live desktop.

## Persistence and recovery

Kept monitor and workspace settings are stored as validated JSON at:

```text
~/.local/state/omarchy/monitor-studio/profiles.json
```

The plugin reapplies the active profile when its widget loads only after an
exact connected-set match. It does not edit `~/.config/hypr/monitors.lua` or
replace unrelated monitor rules. During Keep, Hyprland is reloaded and the
confirmed state is reapplied, clearing superseded runtime workspace rules
without a permanent loader in Hyprland configuration.

Older schema-v1 state at
`~/.local/state/omarchy/monitor-studio/layout.json` is retained as a backup and
imported only when its connector set exactly matches. Migration is atomic and
idempotent; the legacy backup is removed only after the first successful
schema-v2 Keep.

If a saved layout causes trouble, reload Hyprland before reopening the plugin:

```bash
hyprctl reload
```

To discard only Monitor Studio's saved profiles, remove `profiles.json`, then
run `hyprctl reload`. Your own `monitors.lua` remains the fallback. Before the
first confirmed migration, preserve `layout.json` as the recovery copy.

## Troubleshooting

- **A display is missing:** select **Refresh** after the connection settles.
  Check the cable, dock/KVM, and `hyprctl monitors all -j` if it remains absent.
- **A profile is moved, weak, or ambiguous:** use **Identify**. Update or fork a
  moved profile deliberately; uncertain profiles cannot be kept automatically.
- **A mode or Duplicate is unavailable:** choose a mode advertised by every
  affected display. Lower resolution or refresh rate may avoid link/GPU limits.
  Duplicate is intentionally unavailable when physical aspect ratios differ,
  because Hyprland would stretch or squash the mirrored image.
- **The compositor adjusted a result:** Monitor Studio saves the re-enumerated
  result and explains which mode, position, scale, or mirror grouping changed.
- **The panel became unreachable:** use emergency IPC or wait for the detached
  watchdog. `hyprctl reload` remains the final fallback.

## Remove

```bash
omarchy plugin remove io.github.vuhungthang.monitor-studio
hyprctl reload
```

Removal does not delete saved profiles. Delete
`~/.local/state/omarchy/monitor-studio/profiles.json` if you do not want to keep
them for a future installation; a pre-confirmation `layout.json` may also exist
as the schema-v1 recovery backup.

## Migrating from the development clone

Early development builds wrote
`~/.config/hypr/monitor-layout.generated.lua` and required a loader block in
`~/.config/hypr/monitors.lua`. The public plugin does not use either one.
After confirming the public plugin restores its own saved state, remove that
old generated file and its clearly labelled loader block manually. Preserve
all other content in `monitors.lua`.

## Dependencies

Required dependencies are provided by a normal Omarchy Quattro installation:

- Bash, `jq`, GNU coreutils, and util-linux (`setsid`)
- Hyprland's `hyprctl`
- Omarchy display helpers for brightness, scaling, and text size
- Quickshell and the Omarchy shell QML modules

`edid-decode` is optional. When available, it provides the monitor's native
resolution recommendation; otherwise the highest advertised mode is used.

## Verify a checkout

```bash
./scripts/verify-release
```

The command validates the manifest, shell scripts, QML, package structure,
layout transaction behavior, EDID cache behavior, and layout model logic. The
14-scenario evidence map and manual-hardware boundary are recorded in
[docs/acceptance-matrix.md](docs/acceptance-matrix.md).

## Security

Monitor Studio launches local system commands and changes the live Hyprland
display configuration. It performs no network downloads and does not use
`sudo` or `pkexec`. Monitor names and JSON payloads are validated before they
are translated into Hyprland Lua statements. EDID make, model, description,
serial, and connector text is treated as untrusted and rendered as plain text;
profile state stays in the local user state directory. See [SECURITY.md](SECURITY.md) and
[docs/security-and-operations.md](docs/security-and-operations.md) for the
complete boundary and recovery model.

## License and attribution

Monitor Studio is available under the MIT License. It is derived from the
Omarchy monitor plugin; the upstream copyright notice is retained in
[LICENSE](LICENSE), with derivative details in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
