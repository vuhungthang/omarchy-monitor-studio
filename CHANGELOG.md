# Changelog

All notable user-visible changes to Monitor Studio will be documented here.

## [Unreleased]

### Added

- Public release documentation, security boundary, and aggregate verification.
- Per-display rotation controls for landscape, portrait, and inverted orientations.
- Per-display refresh-rate selection, filtered to modes supported at the chosen resolution.
- Coalesced display hot-plug refreshes with automatic cancellation and safe
  recovery when hardware changes during a layout confirmation.
- Identity-aware connected-set profiles: exact sets restore automatically,
  moved monitors require confirmation, and confirmed moves can update or fork
  a profile explicitly.
- Profile management for naming, selecting, duplicating, and confirmed deletion,
  with plain-language exact, moved, weak, ambiguous, and new-set guidance.
- Persistent anchor-display selection with signed, anchor-relative profile
  coordinates that remain independent of transient keyboard or pointer focus.
- Keyboard-accessible display identification overlays, an immediate read-only
  Refresh action, and explicit active, disabled, and transitioning status.
- Internal only, External only, and Extend presets using the same guarded
  preview transaction, with remembered per-profile topology variants.
- Duplicate mode with advertised-mode intersection, an up-front compatibility
  summary, and exact rollback to the previous extended or mirrored grouping.
- Connector transport and structured constraint explanations, including saved
  compositor adjustments, plus an independent emergency-revert IPC command.

### Fixed

- Show profile update and save-as-new actions directly in the display
  confirmation overlay when known monitors move connectors, and explain when
  uncertain matches must be identified instead of silently disabling Keep.
- Keep the 15-second display confirmation and applied geometry visible when a
  display change recreates the shell's per-screen monitor panel.
- Clear Duplicate mirroring when switching to Extend, Internal only, or
  External only, including recovery from previously saved mirrored variants.

### Security

- Render monitor-provided make, model, description, and connector labels as
  plain text, and exclude them from tooltips that use automatic text parsing.

## [1.0.0] - Unreleased

### Added

- Responsive drag-and-drop monitor arrangement with a full-screen editor.
- Friendly monitor labels and recommended per-display resolutions.
- Per-display resolution and scale previews with a 15-second safety rollback.
- Workspace-to-monitor assignment for workspaces 1–10.
- Self-contained persistence that does not edit Hyprland user configuration.
