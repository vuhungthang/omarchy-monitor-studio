#!/bin/bash

set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/sys/card2-DP-4" "$test_root/bin"
printf 'connected\n' >"$test_root/sys/card2-DP-4/status"
printf 'fake-edid\n' >"$test_root/sys/card2-DP-4/edid"

cat >"$test_root/bin/edid-decode" <<'SCRIPT'
#!/bin/bash
printf 'called\n' >>"$MONITOR_DECODER_COUNT"
printf '%s\n' 'Native Video Resolution:' '  2560x1440'
SCRIPT
chmod +x "$test_root/bin/edid-decode"

source "$plugin_dir/monitor-state-lib.sh"

actual=$(MONITOR_SYSFS_ROOT="$test_root/sys" \
  MONITOR_EDID_DECODER="$test_root/bin/edid-decode" \
  MONITOR_RECOMMENDATION_CACHE="$test_root/cache" \
  MONITOR_DECODER_COUNT="$test_root/decoder-count" \
  preferred_resolution_for "DP-4")
[[ $actual == "2560x1440" ]]

actual=$(MONITOR_SYSFS_ROOT="$test_root/sys" \
  MONITOR_EDID_DECODER="$test_root/bin/edid-decode" \
  MONITOR_RECOMMENDATION_CACHE="$test_root/cache" \
  MONITOR_DECODER_COUNT="$test_root/decoder-count" \
  preferred_resolution_for "DP-4")
[[ $actual == "2560x1440" ]]
[[ $(wc -l <"$test_root/decoder-count") -eq 1 ]]

printf 'different-edid\n' >"$test_root/sys/card2-DP-4/edid"
actual=$(MONITOR_SYSFS_ROOT="$test_root/sys" \
  MONITOR_EDID_DECODER="$test_root/bin/edid-decode" \
  MONITOR_RECOMMENDATION_CACHE="$test_root/cache" \
  MONITOR_DECODER_COUNT="$test_root/decoder-count" \
  preferred_resolution_for "DP-4")
[[ $actual == "2560x1440" ]]
[[ $(wc -l <"$test_root/decoder-count") -eq 2 ]]

actual=$(MONITOR_SYSFS_ROOT="$test_root/sys" \
  MONITOR_EDID_DECODER="$test_root/bin/edid-decode" \
  MONITOR_RECOMMENDATION_CACHE="$test_root/cache" \
  MONITOR_DECODER_COUNT="$test_root/decoder-count" \
  preferred_resolution_for "DP-9")
[[ -z $actual ]]

# Hyprland reports a mirror source as the source monitor's numeric runtime ID.
# The panel-facing state must expose the stable connector name so leaving
# Duplicate produces a valid rollback payload.
source "$plugin_dir/tests/lib/fake-hyprctl.sh"
install_fake_hyprctl "$test_root/bin"
mkdir -p "$test_root/empty-sysfs" "$test_root/runtime" "$test_root/state"
jq -c '
  map(if .name == "eDP-1" then .id = 0
      elif .name == "HDMI-A-1" then .id = 4 | .mirrorOf = "0"
      else . end)
' "$plugin_dir/tests/fixtures/monitors/mirrored.json" >"$test_root/monitors.json"
printf '#!/bin/bash\nprintf "unavailable\\n"\n' >"$test_root/bin/omarchy-brightness-display"
printf '#!/bin/bash\nprintf "1\\n"\n' >"$test_root/bin/omarchy-hyprland-monitor-scaling"
chmod +x "$test_root/bin/omarchy-brightness-display" \
  "$test_root/bin/omarchy-hyprland-monitor-scaling"

panel_state=$(PATH="$test_root/bin:$PATH" \
  XDG_RUNTIME_DIR="$test_root/runtime" XDG_STATE_HOME="$test_root/state" \
  MONITOR_SYSFS_ROOT="$test_root/empty-sysfs" \
  HYPRCTL_MONITORS="$test_root/monitors.json" HYPRCTL_LOG="$test_root/hyprctl.log" \
  bash "$plugin_dir/state.sh")
displays=$(sed -n '8p' <<<"$panel_state")
jq -e '
  .[] | select(.name == "HDMI-A-1") | .mirrorOf == "eDP-1"
' <<<"$displays" >/dev/null

printf '%s\n' "monitor state tests passed"
