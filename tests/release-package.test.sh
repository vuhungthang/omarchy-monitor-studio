#!/bin/bash

set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")/.." && pwd)
cd "$plugin_dir"

jq -e '
  .schemaVersion == 1 and
  .id == "io.github.vuhungthang.monitor-studio" and
  .name == "Monitor Studio" and
  .version == "1.0.0" and
  .author == "vuhungthang" and
  .barWidget.displayName == "Monitor Studio" and
  .omarchy.clonedFrom == "omarchy.monitor"
' manifest.json >/dev/null

test -s README.md
test -s LICENSE
test -s CHANGELOG.md
test -s SECURITY.md
test -s THIRD_PARTY_NOTICES.md
test -x scripts/verify-release

rg -qi 'omarchy plugin add' README.md
rg -qi 'omarchy plugin remove' README.md
rg -qi 'unsandboxed' README.md
rg -q '\.local/state/omarchy/monitor-studio/layout\.json' README.md
rg -q 'Copyright \(c\) David Heinemeier Hansson' LICENSE

# A screen mode change can recreate the per-screen panel. Recovering only the
# countdown would leave its new layoutPreview empty, so recovery must also
# rebuild the geometry from the applied Hyprland monitor state.
rg -Uq 'layoutConfirmationTimer\.restart\(\)\n    Qt\.callLater\(root\.refitDisplayLayout\)\n  \}' Panel.qml

if find . -type l -print -quit | grep -q .; then
  echo "release package must not contain symlinks" >&2
  exit 1
fi

echo "release package tests passed"
