# Monitor Studio

Monitor Studio is an Omarchy Quattro bar plugin for arranging displays without
editing monitor coordinates by hand. Select a display in the visual layout to
change its resolution, rotation, or scale, drag displays to match the physical
desk, and assign numbered workspaces to a monitor.

The plugin is derived from Omarchy's built-in `omarchy.monitor` panel and keeps
its brightness, text-size, mirroring, and display-toggle controls.

## Features

- Responsive drag-and-drop arrangement for one, two, three, or many displays
- Full-screen arrangement editor for large and mixed-DPI layouts
- Friendly display names from monitor make/model information
- Per-display resolution, rotation, and scale controls with EDID-based
  recommendations
- Workspace 1–10 assignment, with workspace 10 displayed as `0`
- A 15-second Apply/Keep/Revert preview before display changes are saved
- Automatic restoration of the last kept layout when the plugin starts

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
2. Select a display in the arrangement diagram.
3. Drag it, choose a resolution, rotation, or scale, or assign workspaces.
4. Select **Apply** to preview display changes.
5. Select **Keep** within 15 seconds. Select **Revert**, close the panel, or
   wait for the timer to restore the previous live layout.

Workspace-only changes are saved immediately when their section's Apply action
is selected. Display arrangement, resolution, rotation, and scale changes
always use the confirmation timer.

## Persistence and recovery

Kept monitor and workspace settings are stored as validated JSON at:

```text
~/.local/state/omarchy/monitor-studio/layout.json
```

The plugin reapplies this file when its widget loads. It does not edit
`~/.config/hypr/monitors.lua` or replace unrelated monitor rules. During Keep,
Hyprland is reloaded and the saved state is reapplied, which clears superseded
runtime workspace rules without requiring a permanent loader in Hyprland
configuration.

If a saved layout causes trouble, reload Hyprland before reopening the plugin:

```bash
hyprctl reload
```

To discard only Monitor Studio's saved state, remove the state file above,
then run `hyprctl reload`. Your own `monitors.lua` remains the fallback.

## Remove

```bash
omarchy plugin remove io.github.vuhungthang.monitor-studio
hyprctl reload
```

Removal does not delete the optional state file. Delete
`~/.local/state/omarchy/monitor-studio/layout.json` if you do not want to keep
it for a future installation.

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
layout transaction behavior, EDID cache behavior, and layout model logic.

## Security

Monitor Studio launches local system commands and changes the live Hyprland
display configuration. It performs no network downloads and does not use
`sudo` or `pkexec`. Monitor names and JSON payloads are validated before they
are translated into Hyprland Lua statements. See [SECURITY.md](SECURITY.md) and
[docs/security-and-operations.md](docs/security-and-operations.md) for the
complete boundary and recovery model.

## License and attribution

Monitor Studio is available under the MIT License. It is derived from the
Omarchy monitor plugin; the upstream copyright notice is retained in
[LICENSE](LICENSE), with derivative details in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
