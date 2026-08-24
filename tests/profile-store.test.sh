#!/bin/bash

set -euo pipefail

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/state" "$test_root/runtime" "$test_root/config/hypr" \
  "$test_root/empty-sysfs"
source "$(dirname "$0")/lib/fake-hyprctl.sh"
install_fake_hyprctl "$test_root/bin"

script="$(dirname "$0")/../apply-layout.sh"
state_dir="$test_root/state/omarchy/monitor-studio"
monitors_json='[{"name":"DP-1","serial":"SN1","width":1920,"height":1080,"refreshRate":60,"x":0,"y":0,"scale":1,"availableModes":["1920x1080@60.00Hz"]},{"name":"eDP-1","serial":"SN2","width":2880,"height":1800,"refreshRate":60,"x":1920,"y":0,"scale":2,"availableModes":["2880x1800@60.00Hz"]}]'
v1_layout='{"monitors":[{"name":"DP-1","x":1440,"y":0,"width":1920,"height":1080,"refreshRate":60,"scale":1,"transform":0},{"name":"eDP-1","x":0,"y":0,"width":2880,"height":1800,"refreshRate":60,"scale":2,"transform":0}],"workspaces":{"2":"eDP-1","5":"DP-1"}}'

run_layout() {
  PATH="$test_root/bin:$PATH" \
  XDG_CONFIG_HOME="$test_root/config" \
  XDG_RUNTIME_DIR="$test_root/runtime" \
  XDG_STATE_HOME="$test_root/state" \
  HYPRCTL_LOG="$test_root/hyprctl.log" \
  HYPRCTL_MONITORS="$test_root/monitors.json" \
  MONITOR_SYSFS_ROOT="$test_root/empty-sysfs" \
  LAYOUT_WATCHDOG_DISABLED=1 \
    bash "$script" "$@"
}

printf '%s' "$monitors_json" >"$test_root/monitors.json"
umask 077
mkdir -p "$state_dir"
printf '%s\n' "$v1_layout" >"$state_dir/layout.json"

# Matching v1 state migrates atomically, restores topology and workspaces,
# and keeps the v1 backup until a v2 confirmation.
: >"$test_root/hyprctl.log"
run_layout restore
grep -F -- 'eval hl.monitor({ output = "DP-1", disabled = false, mode = "1920x1080@60", position = "1440x0", scale = 1, transform = 0 }); hl.monitor({ output = "eDP-1", disabled = false, mode = "2880x1800@60", position = "0x0", scale = 2, transform = 0 })' "$test_root/hyprctl.log"
grep -F 'workspace = "2", monitor = "eDP-1"' "$test_root/hyprctl.log"
test -f "$state_dir/profiles.json"
test -f "$state_dir/layout.json"
jq -e '
  .schemaVersion == 2 and
  .activeProfileId == "imported" and
  (.profiles | length == 1) and
  .profiles[0].id == "imported" and
  .profiles[0].name == "Migrated layout" and
  (.profiles[0].connectedSet == ["DP-1", "eDP-1"]) and
  .profiles[0].topology.workspaces == {"2":"eDP-1","5":"DP-1"}
' "$state_dir/profiles.json" >/dev/null

# Migration is idempotent: a second restore sees that the v2 profile already
# matches the live topology, so it neither modesets again nor touches state.
: >"$test_root/hyprctl.log"
run_layout restore
restore_eval_count=$(grep -c '^eval hl.monitor' "$test_root/hyprctl.log" || true)
test "$restore_eval_count" -eq 0
jq -e '(.profiles | length == 1) and .activeProfileId == "imported"' "$state_dir/profiles.json" >/dev/null
test -f "$state_dir/layout.json"

# Per-screen widgets can request restore concurrently. The backend serializes
# the snapshot/check/apply transaction so only the first caller modesets; the
# later callers observe the applied topology and take the idempotent path.
printf '%s' "$monitors_json" >"$test_root/monitors.json"
: >"$test_root/hyprctl.log"
export HYPRCTL_EVAL_DELAY=0.2
run_layout restore & restore_pid_1=$!
run_layout restore & restore_pid_2=$!
run_layout restore & restore_pid_3=$!
wait "$restore_pid_1" "$restore_pid_2" "$restore_pid_3"
unset HYPRCTL_EVAL_DELAY
restore_eval_count=$(grep -c '^eval hl.monitor' "$test_root/hyprctl.log" || true)
test "$restore_eval_count" -eq 1

# Keep confirms the v2 store; only then is the v1 backup removed.
proposed='[{"name":"DP-1","x":0,"y":120,"width":1920,"height":1080,"refreshRate":60,"scale":1,"transform":0},{"name":"eDP-1","x":1080,"y":0,"width":2880,"height":1800,"refreshRate":60,"scale":2,"transform":0}]'
run_layout preview confirm-migration "$proposed" "$proposed" '{}'
run_layout keep confirm-migration
jq -e --argjson monitors "$proposed" '
  .profiles[0].topology.monitors == $monitors and .activeProfileId == "imported" and
  (.profiles[0].matchPolicy.identities | length == 2) and
  all(.profiles[0].matchPolicy.identities[]; .serialTrusted == true)
' "$state_dir/profiles.json" >/dev/null
test ! -e "$state_dir/layout.json"

# A rightmost anchor is persisted independently of focus, and its relative
# coordinate space retains the negative position of displays to its left.
anchored='[{"name":"DP-1","x":-1920,"y":100,"width":1920,"height":1080,"refreshRate":60,"scale":1,"transform":0},{"name":"eDP-1","x":0,"y":0,"width":2880,"height":1800,"refreshRate":60,"scale":2,"transform":1}]'
run_layout preview anchored-right "$anchored" "$proposed" '{}' layout eDP-1
run_layout keep anchored-right
jq -e --argjson monitors "$anchored" '
  .profiles[0].topology.anchor == "eDP-1" and
  .profiles[0].topology.monitors == $monitors and
  (.profiles[0].topology.monitors[] | select(.name == "DP-1") | .x) == -1920 and
  (.profiles[0].topology.monitors[] | select(.name == "eDP-1") | .transform) == 1
' "$state_dir/profiles.json" >/dev/null

profiles_state=$(run_layout profiles)
jq -e '.activeAnchor == "eDP-1"' <<<"$profiles_state" >/dev/null

# Confirmed preset topologies are remembered as compatible variants of the
# connected-set profile, without replacing the main topology contract.
internal_variant='[{"name":"DP-1","enabled":false},{"name":"eDP-1","x":0,"y":0,"width":2880,"height":1800,"refreshRate":60,"scale":2,"transform":0}]'
internal_confirmed='[{"name":"DP-1","x":-1920,"y":100,"width":1920,"height":1080,"refreshRate":60,"scale":1,"transform":0,"enabled":false},{"name":"eDP-1","x":0,"y":0,"width":2880,"height":1800,"refreshRate":60,"scale":2,"transform":0}]'
run_layout preview preset-internal "$internal_variant" "$anchored" '{}' topology eDP-1 internal
run_layout keep preset-internal
jq -e --argjson monitors "$internal_confirmed" '
  .profiles[0].topology.variants.internal.monitors == $monitors and
  .profiles[0].topology.variants.internal.anchor == "eDP-1"
' "$state_dir/profiles.json" >/dev/null
jq -e '.activeVariants.internal.anchor == "eDP-1"' <<<"$(run_layout profiles)" >/dev/null

# A profile with strong identities that already matches live state is accepted
# without another monitor transaction.
: >"$test_root/hyprctl.log"
run_layout restore
restore_eval_count=$(grep -c '^eval hl.monitor' "$test_root/hyprctl.log" || true)
test "$restore_eval_count" -eq 0

# Reusing the same connector names with different monitor identities is not an
# exact match and must never restore the old profile automatically.
printf '%s' "$(jq -c 'map(if .name == "DP-1" then .serial = "SWAPPED" else . end)' \
  <<<"$monitors_json")" >"$test_root/monitors.json"
: >"$test_root/hyprctl.log"
if run_layout restore 2>"$test_root/swapped.err"; then
  echo "profile restored after monitor identity changed on the same connector" >&2
  exit 1
fi
! grep -F -- 'eval hl.monitor' "$test_root/hyprctl.log"

# A strongly identified monitor on another connector is surfaced as a moved
# profile candidate for confirmation, but restore remains observation-only.
printf '%s' "$(jq -c 'map(if .name == "DP-1" then .name = "HDMI-A-1" else . end)' \
  <<<"$monitors_json")" >"$test_root/monitors.json"
status=$(run_layout profile-status)
jq -e '.status == "moved" and .profileId == "imported" and
  any(.matches[]; .currentName == "HDMI-A-1" and .status == "moved" and
    .requiresModeRevalidation == true)' <<<"$status" >/dev/null
: >"$test_root/hyprctl.log"
if run_layout restore 2>"$test_root/moved.err"; then
  echo "moved profile restored without confirmation" >&2
  exit 1
fi
! grep -F -- 'eval hl.monitor' "$test_root/hyprctl.log"

# A confirmed moved layout requires an explicit choice. Fork preserves the
# source profile; update deliberately retargets only the selected profile.
moved_proposed=$(jq -c 'map(if .name == "DP-1" then .name = "HDMI-A-1" else . end)' \
  <<<"$proposed")
run_layout preview moved-fork "$moved_proposed" "$moved_proposed" '{}'
run_layout keep moved-fork fork-profile imported
jq -e '
  . as $store | (.profiles | length == 2) and
  any(.profiles[]; .id == "imported" and (.connectedSet | index("DP-1")) != null) and
  any(.profiles[]; .id == $store.activeProfileId and (.connectedSet | index("HDMI-A-1")) != null)
' "$state_dir/profiles.json" >/dev/null

run_layout preview moved-update "$moved_proposed" "$moved_proposed" '{}'
run_layout keep moved-update update-profile imported
jq -e '
  (.profiles | length == 2) and
  (.profiles[] | select(.id == "imported") |
    (.connectedSet | index("HDMI-A-1")) != null and
    (.matchPolicy.identities | map(.name) | index("HDMI-A-1")) != null)
' "$state_dir/profiles.json" >/dev/null
printf '%s' "$monitors_json" >"$test_root/monitors.json"

# --- Fresh root: mismatched v1 state is never applied or migrated. ---
mismatch_root=$(mktemp -d)
printf '%s' '[{"name":"eDP-1","serial":"","width":2880,"height":1800,"refreshRate":60,"x":0,"y":0,"scale":2,"availableModes":["2880x1800@60.00Hz"]}]' >"$test_root/monitors-mismatch.json"
mkdir -p "$mismatch_root/state/omarchy/monitor-studio"
printf '%s\n' "$v1_layout" >"$mismatch_root/state/omarchy/monitor-studio/layout.json"
: >"$test_root/hyprctl.log"
if PATH="$test_root/bin:$PATH" XDG_CONFIG_HOME="$test_root/config" \
   XDG_RUNTIME_DIR="$mismatch_root/runtime" XDG_STATE_HOME="$mismatch_root/state" \
   HYPRCTL_LOG="$test_root/hyprctl.log" HYPRCTL_MONITORS="$test_root/monitors-mismatch.json" \
   LAYOUT_WATCHDOG_DISABLED=1 bash "$script" restore 2>"$test_root/mismatch.err"; then
  echo "mismatched v1 state was applied" >&2
  exit 1
fi
! grep -F -- 'eval hl.monitor' "$test_root/hyprctl.log"
grep -F 'does not match' "$test_root/mismatch.err"
test -f "$mismatch_root/state/omarchy/monitor-studio/layout.json"
test ! -e "$mismatch_root/state/omarchy/monitor-studio/profiles.json"

# --- Malformed v1 state: no eval, recoverable. ---
malformed_root=$(mktemp -d)
mkdir -p "$malformed_root/state/omarchy/monitor-studio"
printf '%s\n' '{"monitors": "not-an-array"}' >"$malformed_root/state/omarchy/monitor-studio/layout.json"
: >"$test_root/hyprctl.log"
if PATH="$test_root/bin:$PATH" XDG_CONFIG_HOME="$test_root/config" \
   XDG_RUNTIME_DIR="$malformed_root/runtime" XDG_STATE_HOME="$malformed_root/state" \
   HYPRCTL_LOG="$test_root/hyprctl.log" HYPRCTL_MONITORS="$test_root/monitors.json" \
   LAYOUT_WATCHDOG_DISABLED=1 bash "$script" restore 2>/dev/null; then
  echo "malformed v1 state was accepted" >&2
  exit 1
fi
! grep -F -- 'eval hl.monitor' "$test_root/hyprctl.log"
test -f "$malformed_root/state/omarchy/monitor-studio/layout.json"

# --- Malformed v2 store: no eval, recoverable, backup untouched. ---
malformed_v2_root=$(mktemp -d)
mkdir -p "$malformed_v2_root/state/omarchy/monitor-studio"
printf '%s\n' '{"schemaVersion": 3, "profiles": []}' >"$malformed_v2_root/state/omarchy/monitor-studio/profiles.json"
printf '%s\n' "$v1_layout" >"$malformed_v2_root/state/omarchy/monitor-studio/layout.json"
: >"$test_root/hyprctl.log"
if PATH="$test_root/bin:$PATH" XDG_CONFIG_HOME="$test_root/config" \
   XDG_RUNTIME_DIR="$malformed_v2_root/runtime" XDG_STATE_HOME="$malformed_v2_root/state" \
   HYPRCTL_LOG="$test_root/hyprctl.log" HYPRCTL_MONITORS="$test_root/monitors.json" \
   LAYOUT_WATCHDOG_DISABLED=1 bash "$script" restore 2>/dev/null; then
  echo "malformed v2 store was accepted" >&2
  exit 1
fi
! grep -F -- 'eval hl.monitor' "$test_root/hyprctl.log"
test -f "$malformed_v2_root/state/omarchy/monitor-studio/layout.json"

echo "profile store tests passed"
