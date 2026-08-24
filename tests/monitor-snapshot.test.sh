#!/bin/bash

set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

source "$plugin_dir/monitor-snapshot-lib.sh"

fixture="$plugin_dir/tests/fixtures/monitors/internal-external.json"

# Connector records carry sysfs metadata; missing sysfs degrades to explicit
# unknowns without dropping the output.
snapshot=$(MONITOR_SYSFS_ROOT="$test_root/empty-sysfs" monitor_snapshot "$(<"$fixture")")

jq -e '
  .connectors | length == 2 and
  ([.[] | select(.name == "eDP-1" and .transport == "internal")] | length == 1) and
  ([.[] | select(.name == "DP-1" and .transport == "displayport")] | length == 1) and
  all(.[]; .sysfsPath == null and .availability == "unknown" and .edidHash == null)
' <<<"$snapshot" >/dev/null

jq -e '
  .monitors | length == 2 and
  (.[] | select(.name == "DP-1") |
    .serial == "CN0TEST1" and .serialTrusted == true and
    .preferredMode == "3840x2160@59.99Hz") and
  (.[] | select(.name == "eDP-1") | .serial == null and .serialTrusted == false)
' <<<"$snapshot" >/dev/null

jq -e '
  .topology | length == 2 and
  (.[] | select(.name == "DP-1") |
    .enabled == true and .mode == "3840x2160@59.997" and
    .mirrorOf == null and .transform == 0)
' <<<"$snapshot" >/dev/null

# Hardware and snapshot generations are present and hex-stable.
jq -e '.hardwareGeneration != null and .snapshotGeneration != null' <<<"$snapshot" >/dev/null
[[ $(jq -r .hardwareGeneration <<<"$snapshot") =~ ^[0-9a-f]{64}$ ]]
[[ $(jq -r .snapshotGeneration <<<"$snapshot") =~ ^[0-9a-f]{64}$ ]]

# Generations are stable for equivalent monitor ordering.
reordered=$(MONITOR_SYSFS_ROOT="$test_root/empty-sysfs" monitor_snapshot "$(jq -c 'reverse' "$fixture")")
jq -en --argjson a "$snapshot" --argjson b "$reordered" \
  '$a.hardwareGeneration == $b.hardwareGeneration and $a.snapshotGeneration == $b.snapshotGeneration' \
  >/dev/null

# A topology-only change keeps the hardware generation but changes the snapshot.
moved=$(MONITOR_SYSFS_ROOT="$test_root/empty-sysfs" \
  monitor_snapshot "$(jq -c 'map(if .name == "eDP-1" then .x = 400 else . end)' "$fixture")")
jq -en --argjson a "$snapshot" --argjson b "$moved" \
  '$a.hardwareGeneration == $b.hardwareGeneration and $a.snapshotGeneration != $b.snapshotGeneration' \
  >/dev/null

# A hardware identity change (different serial) changes both generations.
swapped=$(MONITOR_SYSFS_ROOT="$test_root/empty-sysfs" \
  monitor_snapshot "$(jq -c 'map(if .name == "DP-1" then .serial = "CN0OTHER" else . end)' "$fixture")")
jq -en --argjson a "$snapshot" --argjson b "$swapped" \
  '$a.hardwareGeneration != $b.hardwareGeneration and $a.snapshotGeneration != $b.snapshotGeneration' \
  >/dev/null

# Sysfs metadata enriches connector records with card, instance, EDID hash.
mkdir -p "$test_root/sys/card0-DP-1/device"
printf 'connected\n' >"$test_root/sys/card0-DP-1/status"
printf 'fake-edid-blob\n' >"$test_root/sys/card0-DP-1/edid"
ln -sf /sys/devices/pci0000:00 "$test_root/sys/card0-DP-1/device" 2>/dev/null || true

enriched=$(MONITOR_SYSFS_ROOT="$test_root/sys" monitor_snapshot "$(<"$fixture")")
jq -e '
  .connectors[] | select(.name == "DP-1") |
  .sysfsPath != null and .card == "card0" and .instance == 1 and
  .availability == "connected" and .edidHash != null
' <<<"$enriched" >/dev/null
jq -e '.monitors[] | select(.name == "DP-1") | .edidHash != null' <<<"$enriched" >/dev/null

# Disabled outputs stay visible with enabled false and no mode requirement.
disabled_fixture="$plugin_dir/tests/fixtures/monitors/disabled-external.json"
disabled=$(MONITOR_SYSFS_ROOT="$test_root/empty-sysfs" monitor_snapshot "$(<"$disabled_fixture")")
jq -e '.topology[] | select(.name == "HDMI-A-1") | .enabled == false' <<<"$disabled" >/dev/null

# Mirrored outputs record their mirror source.
mirrored=$(MONITOR_SYSFS_ROOT="$test_root/empty-sysfs" \
  monitor_snapshot "$(<"$plugin_dir/tests/fixtures/monitors/mirrored.json")")
jq -e '.topology[] | select(.name == "HDMI-A-1") | .mirrorOf == "eDP-1"' <<<"$mirrored" >/dev/null

# Hyprland reports mirrorOf as the source monitor's numeric runtime ID. The
# normalized contract exposes stable connector names to every consumer.
numeric_mirror_input=$(jq -c '
  map(if .name == "eDP-1" then .id = 0
      elif .name == "HDMI-A-1" then .id = 4 | .mirrorOf = "0"
      else . end)
' "$plugin_dir/tests/fixtures/monitors/mirrored.json")
numeric_mirror=$(MONITOR_SYSFS_ROOT="$test_root/empty-sysfs" \
  monitor_snapshot "$numeric_mirror_input")
jq -e '.topology[] | select(.name == "HDMI-A-1") | .mirrorOf == "eDP-1"' \
  <<<"$numeric_mirror" >/dev/null

# Duplicated serials are marked untrusted rather than silently trusted.
dup_serial=$(MONITOR_SYSFS_ROOT="$test_root/empty-sysfs" monitor_snapshot "$(jq -c 'map(if .name == "DP-4" then .serial = "TST0000002" else . end)' \
  "$plugin_dir/tests/fixtures/monitors/three-display.json")")
jq -e '[.monitors[] | select(.serialTrusted == true)] | length == 0' <<<"$dup_serial" >/dev/null

# Driver-reported wireless, virtual, and indirect outputs are not guessed from
# transport naming; once enumerated, an unknown connector remains arrangeable.
virtual_input=$(jq -c '[.[0] | .name = "Virtual-1" | .description = "Virtual display"]' "$fixture")
virtual=$(MONITOR_SYSFS_ROOT="$test_root/empty-sysfs" monitor_snapshot "$virtual_input")
jq -e '
  (.connectors[0].name == "Virtual-1" and .connectors[0].transport == "unknown") and
  (.topology[0].name == "Virtual-1" and .topology[0].enabled == true)
' <<<"$virtual" >/dev/null

echo "monitor snapshot tests passed"
