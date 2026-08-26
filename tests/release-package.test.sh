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
rg -q 'function recoverDisplayConfirmation' Panel.qml
rg -q 'Qt\.callLater\(root\.refitDisplayLayout\)' Panel.qml
rg -Fq 'function revert(): string' Panel.qml
rg -q '"revert-pending"' Panel.qml
rg -q 'pendingTransactionProc\.running = true' Panel.qml
rg -q 'function ownsDisplayIpc' Model.js
rg -q 'enabled: root\.ownsDisplayIpc' Panel.qml
rg -q 'omarchy shell omarchy.monitor revert' README.md

for fixture in tests/fixtures/monitors/*.json; do
  jq -e 'type == "array" and length > 0 and all(.[]; (.name | type == "string" and test("^[A-Za-z0-9._-]+$"))
    and (.availableModes | type == "array"))' "$fixture" >/dev/null \
    || { echo "invalid monitor fixture: $fixture" >&2; exit 1; }
done

test -s docs/hyprland-topology-contract.md
test -s docs/acceptance-matrix.md
test -s ProfileSection.qml
test -s ConnectedDisplaysSection.qml
test -s IdentifyOverlay.qml
test -s DisplayConfirmationOverlay.qml
test -s TopologyPresets.qml
rg -q 'DisplayConfirmationOverlay' Panel.qml
rg -q 'keepRequested' DisplayConfirmationOverlay.qml
rg -q 'revertRequested' DisplayConfirmationOverlay.qml
if rg -q 'keepEnabled' DisplayConfirmationOverlay.qml Panel.qml; then
  echo "display confirmation references removed keepEnabled property" >&2
  exit 1
fi
rg -q 'schema-v2' README.md
rg -q 'Pass \(automated' docs/acceptance-matrix.md

if find . -type l -print -quit | grep -q .; then
  echo "release package must not contain symlinks" >&2
  exit 1
fi

echo "release package tests passed"
