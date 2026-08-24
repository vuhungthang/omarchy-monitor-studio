# Changelog

All notable user-visible changes to Monitor Studio will be documented here.

## [Unreleased]

### Added

- Public release documentation, security boundary, and aggregate verification.
- Per-display rotation controls for landscape, portrait, and inverted orientations.
- Per-display refresh-rate selection, filtered to modes supported at the chosen resolution.

### Fixed

- Keep the 15-second display confirmation and applied geometry visible when a
  display change recreates the shell's per-screen monitor panel.

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
