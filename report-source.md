# Monitor Studio: Adjacent Use-Case Research Report

**Date:** 2026-08-23
**Audience:** Monitor Studio maintainer
**Scope:** Additional use cases for the existing Omarchy/Hyprland monitor-layout plugin.

## Executive answer

Monitor Studio should expand from a layout editor into a small, safe **display-mode manager** for Omarchy. The highest-value next use cases are:

1. **Saved profiles for recurring environments** — desk, laptop-only, meeting/projector, presentation, and travel layouts.
2. **Identity-aware hotplug restoration** — restore a monitor by stable make/model/EDID identity when docks or connector names change.
3. **A diagnostic and recovery center** — explain why a layout is not sticking, show the effective state, export a support bundle, and offer a one-click safe reset.
4. **Fast “show mode” controls** — mirror, external-only, internal-only, or extend, with the existing Apply/Keep/Revert safety window.
5. **Advanced per-monitor quality controls** — build on the existing refresh-rate and rotation controls with VRR, 8/10-bit, color-management, and ICC options.

The profile and recovery foundation is the differentiator. A basic monitor editor already exists in the ecosystem: nwg-displays provides GUI output configuration and workspace-to-output assignment for Hyprland, Sway, and Niri, while way-displays handles automatic changes for supported wlroots compositors. Monitor Studio’s opportunity is tighter Omarchy integration, safer transactions, and user-facing workflows for switching contexts.

## What the project already does

The current project supports drag-and-drop arrangement, resolution, refresh-rate, rotation, and scale selection, workspace 1–10 assignment, display toggling, compatibility-checked mirroring, EDID-based preferred-resolution recommendations, connected-set profiles, and a 15-second Apply/Keep/Revert transaction. Refresh rates are filtered to modes supported at the selected resolution, mirroring intersects advertised modes before preview, and rotation covers landscape, portrait, and inverted orientations. That means the next features should avoid merely adding more raw fields to the existing panel.

The current implementation also writes runtime state rather than editing `monitors.lua`, validates monitor payloads, and uses a private transaction directory. Those are strong foundations for profiles and recovery.

## Evidence and market signals

### The underlying problem is recurring, not one-time setup

Omarchy’s monitor documentation explicitly covers scaling, mirroring, lid behavior, multi-monitor arrangement, and workspace binding, but still directs users to edit `monitors.lua` or use Hyprmon for positioning. It also notes that mirroring is especially useful for projectors and that closing the lid turns off the internal display when an external screen is connected. [Omarchy monitor manual](https://github.com/basecamp/omarchy/blob/quattro/manual/33-monitors.md)

Recent Omarchy discussions and issues describe users wanting mode/refresh selection, placement, identify overlays, and a revert countdown; another feature request asks for quick switching among mirror, extend, and single-display modes. [Display widget discussion](https://github.com/basecamp/omarchy/discussions/7038), [layout switch request](https://github.com/basecamp/omarchy/discussions/4996)

### Stable monitor identity matters in real setups

An Omarchy issue reports that laptop users with two external monitors lose their known positions when reconnecting and suggests identifying displays by serial number or another stable identity. Separate issues show that connector names and `desc:` rules can interact badly with Omarchy’s clamshell and scaling helpers. [Monitor position issue](https://github.com/basecamp/omarchy/issues/4484), [clamshell `desc:` issue](https://github.com/basecamp/omarchy/issues/7084)

This supports an identity layer based on the strongest available match: connector when stable, then make/model/description, then EDID hash when available. The plugin should show when a match is approximate rather than silently applying it.

### Hyprland exposes a larger feature surface than the current UI

Current Hyprland monitor rules support resolution/mode, position, scale, disabled state, rotation/flip transform, mirroring, bit depth, color management, HDR-related controls, ICC paths, and VRR. [Hyprland monitor documentation](https://wiki.hypr.land/Configuring/Basics/Monitors/)

These features create legitimate use cases, but they also create risk. Disabling a monitor moves windows out of the layout, mirroring can stretch content when aspect ratios differ, and a bad monitor change can remove the screen containing the controls. This favors staged transactions and explicit warnings for advanced controls.

### Existing tools validate demand but leave room for differentiation

nwg-displays positions itself as an intuitive GUI that applies settings, saves output configuration, and saves workspace-to-output assignments. It supports Sway, Hyprland, and Niri, including the newer Hyprland Lua configuration path. [nwg-displays README](https://github.com/nwg-piotr/nwg-displays)

way-displays supports automatic resolution, arrangement, DPI scaling, plug/unplug changes, and lid changes, but explicitly says Hyprland already provides the relevant features and that Hyprland is unsupported for that daemon. [way-displays README](https://github.com/alex-courtis/way-displays)

Omarchy’s plugin system provides a direct distribution path and allows third-party plugins to replace or extend first-party shell widgets. [Omarchy shell plugins manual](https://github.com/basecamp/omarchy/blob/quattro/manual/32-shell-plugins.md)

## Prioritized use cases

| Priority | Use case | User outcome | Why it fits Monitor Studio | Suggested scope |
| --- | --- | --- | --- | --- |
| P0 | Saved display profiles | Switch between “Desk”, “Laptop only”, “Projector”, and “Presentation” in one action | Builds directly on the existing persisted JSON and transaction flow | Profile CRUD, preview, Keep/Revert, per-profile workspace assignments |
| P0 | Identity-aware hotplug restore | Reconnect a dock and get the known physical layout back | Directly addresses reported lost-position pain | Stable identity records, matching confidence, unmatched-monitor review |
| P0 | Safe show modes | Quickly choose mirror, extend, internal-only, or external-only | Explicitly requested in Omarchy discussions; existing mirror/toggle primitives reduce effort | Preset generator plus 15-second rollback |
| P1 | Diagnostics and recovery | Understand “why did my scale/position revert?” and recover without a terminal | Current Omarchy issues show rule conflicts and helper overwrites | Effective-vs-saved diff, recent transaction status, reset-to-live, export bundle |
| P1 | Identify/test screens | Put a numbered label on each physical display before arranging | Removes guesswork for DP-1/DP-2; proposed in Omarchy discussion | Temporary per-screen overlay, timeout, no persistence |
| P1 | Mode and refresh profiles | Reuse a preferred resolution and refresh rate per context | Builds on the existing refresh-rate picker; high user value for gaming/presentation | Persist mode choices in profiles with the existing safety checks |
| P1 | Rotation and vertical-monitor workflows | Reuse portrait and inverted layouts without hand-writing transforms | Builds on the existing rotation control and geometry recalculation | Persist rotation choices in profiles and presets |
| P2 | VRR and color quality | Toggle VRR, 10-bit, HDR/color preset, or ICC per profile | Hyprland supports these; valuable for gaming/photo/video users | Capability detection, advanced disclosure, strong warnings |
| P2 | Accessibility/comfort modes | Apply readable scaling, text size, brightness, and low-motion layouts together | Existing brightness/text-size controls can become a coherent context | “Reading”, “Night”, and “Presentation” presets; avoid medical claims |
| P2 | Shareable/importable layouts | Recreate a known setup after reinstall or on another Omarchy machine | Plugin distribution and JSON persistence make this natural | Sanitized export/import, monitor identity remapping, preview before apply |

## Recommended product shape

### 1. Treat a profile as a complete context

A profile should contain:

- monitor identity and enabled/disabled state;
- mode, position, scale, transform, mirror, and optional quality settings;
- workspace-to-monitor assignments;
- optional Omarchy comfort settings such as text size and brightness;
- a human name and last-used timestamp.

Do not make profiles blindly overwrite every field. Each profile should declare whether it owns display geometry, workspaces, and comfort controls. This allows a user to switch monitor geometry without unexpectedly changing brightness or workspace routing.

### 2. Match monitors conservatively

Use a matching ladder:

1. exact connector plus compatible identity;
2. EDID hash, if available;
3. exact make/model/description;
4. user-confirmed fuzzy match.

If a profile cannot match confidently, show an “unmatched display” state and let the user map it. Never silently assign a saved configuration to a different monitor merely because it has the same resolution.

### 3. Make every profile switch transactional

Reuse the current preview transaction. A profile switch should show a compact summary such as “DP-2 will move left, eDP-1 will be disabled, workspace 1 will move to DP-2.” Keep, Revert, timeout, panel close, and failed-apply behavior should use the same recovery path as the current editor.

The profile system must also handle the case where the screen containing the panel disappears: offer a keyboard shortcut or external `omarchy monitor-studio revert` command as a recovery path.

### 4. Separate everyday presets from advanced controls

The main surface should expose profiles, common modes, and the existing rotation control. VRR, bit depth, HDR, ICC, reserved areas, and raw identity overrides should live behind an Advanced section with capability detection and warnings. This keeps the common path comprehensible and reduces accidental compositor instability.

## Suggested roadmap

### Release A: Profiles and show modes

- Refactor the current saved state into a versioned profile store.
- Add built-in presets: current layout, laptop-only, external-only, mirror, extend.
- Add profile preview with a diff summary.
- Persist workspace assignments with each profile.
- Add a keyboard-accessible profile switcher.

### Release B: Identity and recovery

- Store connector, make, model, description, and EDID hash when available.
- Show match confidence and unresolved displays.
- Add “restore current live state” and “forget saved profiles.”
- Add diagnostics showing live Hyprland state, saved profile state, and pending transaction.
- Add a sanitized export bundle suitable for bug reports.

### Release C: Advanced quality and accessibility

- Add identify overlays.
- Add coordinated comfort presets for brightness, text size, and scale.
- Add VRR/bit-depth/color controls only where Hyprland reports support or the user explicitly enables Advanced mode.

### Release D: Sharing and automation

- Import/export profiles with identity remapping.
- Optional hotplug auto-apply with a confirmation policy: never, ask, or apply only high-confidence matches.
- Optional CLI entry point for scripts and keybinds.

## What not to prioritize yet

- A general cross-compositor display manager: nwg-displays already occupies that space, and Monitor Studio’s Omarchy integration is a stronger differentiator.
- A background daemon that continuously fights Omarchy’s own clamshell and scaling helpers: current issues show that competing writers can cause flicker and revert loops.
- Full HDR calibration or color-management authoring: the Hyprland surface is broad and hardware-dependent; start with profile-level selection of known-good settings.
- Window-layout restoration as part of the first profile release: it is valuable, but it requires a separate, reliable model of window identity and launch timing.

## Implementation risks

- **Configuration drift:** Hyprland 0.55+ uses Lua-style monitor rules, and ecosystem tools may still target generated config files. Keep Monitor Studio’s runtime state self-contained and avoid parsing user config unless needed for diagnostics.
- **Competing writers:** Omarchy’s clamshell and scaling helpers may reapply settings. Diagnostics should detect repeated live-state changes and identify when the saved profile is not the active authority.
- **Monitor identity changes:** Docks can change connector names; EDID may be absent or unstable. Make matching explainable and reversible.
- **Screen loss during apply:** Keep the current 15-second transaction, add keyboard/CLI recovery, and test with the panel’s display disabled.
- **State migration:** Version the profile file and preserve the current single-layout file as an importable legacy format.

## Bottom line

The best next feature is not “more monitor knobs.” It is **one-click, reversible switching among known display contexts**. Profiles naturally bundle the project’s existing arrangement, resolution, scale, workspace, mirroring, brightness, and text-size capabilities; they also create a clean home for hotplug restoration, diagnostics, and later advanced display quality controls.

## Sources consulted

- [Omarchy monitor manual](https://github.com/basecamp/omarchy/blob/quattro/manual/33-monitors.md) — current user workflows for scaling, mirroring, lid behavior, workspace binding, and brightness.
- [Omarchy shell plugins manual](https://github.com/basecamp/omarchy/blob/quattro/manual/32-shell-plugins.md) — plugin distribution and replacement model.
- [Hyprland monitor documentation](https://wiki.hypr.land/Configuring/Basics/Monitors/) — current Lua monitor fields and behavior.
- [Hyprland workspace rules](https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/) — monitor-bound workspaces and defaults.
- [nwg-displays](https://github.com/nwg-piotr/nwg-displays) — competing GUI output/workspace manager and feature baseline.
- [way-displays](https://github.com/alex-courtis/way-displays) — automatic hotplug/lid profile behavior and Hyprland compatibility boundary.
- [Omarchy monitor position issue](https://github.com/basecamp/omarchy/issues/4484) — reported loss of remembered positions after reconnecting displays.
- [Omarchy layout switch request](https://github.com/basecamp/omarchy/discussions/4996) — request for mirror/extend/single-display quick switching.
- [Omarchy display widget discussion](https://github.com/basecamp/omarchy/discussions/7038) — demand for mode, placement, identify, and safe revert behavior.
- [Omarchy clamshell `desc:` issue](https://github.com/basecamp/omarchy/issues/7084) — evidence of identity/configuration conflicts during hotplug and scaling.

## Limitations and stopping point

This is a product-opportunity report, not a user survey or quantitative market-sizing study. Public issue/discussion activity is directional evidence, not a measure of feature demand across all Omarchy users. Research stopped after primary Omarchy/Hyprland documentation, current ecosystem tool documentation, and multiple directly relevant issue/discussion signals converged on the same four themes: profiles, hotplug identity, safe switching, and recovery.
