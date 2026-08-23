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

printf '%s\n' "monitor state tests passed"
