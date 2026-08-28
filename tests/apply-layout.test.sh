#!/bin/bash

set -euo pipefail

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/config/hypr" "$test_root/runtime" "$test_root/state" \
  "$test_root/empty-sysfs"
chmod 700 "$test_root/runtime"
source "$(dirname "$0")/lib/fake-hyprctl.sh"
install_fake_hyprctl "$test_root/bin"

monitors_json='[{"id":0,"name":"DP-1","make":"Test","model":"T1","serial":"SN1","width":1920,"height":1080,"refreshRate":59.95,"x":0,"y":0,"scale":1,"transform":0,"focused":true,"disabled":false,"mirrorOf":"none","availableModes":["1920x1080@59.95Hz"]},{"id":1,"name":"eDP-1","make":"Test","model":"T2","serial":"SN2","width":2880,"height":1800,"refreshRate":60,"x":1920,"y":0,"scale":2,"transform":0,"focused":false,"disabled":false,"mirrorOf":"none","availableModes":["2880x1800@60.00Hz","1920x1080@59.95Hz"]}]'

script="$(dirname "$0")/../apply-layout.sh"
proposed='[{"name":"DP-1","x":0,"y":120,"width":1920,"height":1080,"refreshRate":59.95,"scale":1,"transform":1},{"name":"eDP-1","x":1080,"y":0,"width":2880,"height":1800,"refreshRate":60,"scale":2,"transform":0}]'
previous='[{"name":"DP-1","x":1440,"y":0,"width":1920,"height":1080,"refreshRate":59.95,"scale":1,"transform":0},{"name":"eDP-1","x":0,"y":0,"width":2880,"height":1800,"refreshRate":60,"scale":2,"transform":0}]'
workspaces='{"1":"DP-1","2":"DP-1","4":"eDP-1"}'

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

# Runtime transaction state requires a private XDG parent and must never
# traverse a pre-existing symlink. This also guards the /tmp fallback against
# another local user redirecting restore locks or transaction files.
mkdir -p "$test_root/public-runtime"
chmod 755 "$test_root/public-runtime"
if XDG_RUNTIME_DIR="$test_root/public-runtime" \
    XDG_STATE_HOME="$test_root/state" bash "$script" pending; then
  echo "public XDG runtime directory was accepted" >&2
  exit 1
fi

mkdir -p "$test_root/unsafe-runtime" "$test_root/attacker-controlled"
chmod 700 "$test_root/unsafe-runtime"
ln -s "$test_root/attacker-controlled" \
  "$test_root/unsafe-runtime/omarchy-monitor-studio"
if XDG_RUNTIME_DIR="$test_root/unsafe-runtime" \
    XDG_STATE_HOME="$test_root/state" bash "$script" pending; then
  echo "symlinked runtime directory was accepted" >&2
  exit 1
fi

# Preview changes the live layout but does not persist it.
run_layout preview keep-test "$proposed" "$previous" "$workspaces" settings "" "" DP-1 5
test "$(stat -c '%a' "$test_root/runtime/omarchy-monitor-studio")" = 700
grep -F -- 'eval hl.monitor({ output = "DP-1", disabled = false, mode = "1920x1080@59.95", position = "0x120", scale = 1, transform = 1 }); hl.monitor({ output = "eDP-1", disabled = false, mode = "2880x1800@60", position = "1080x0", scale = 2, transform = 0 })' "$test_root/hyprctl.log"
! grep -F -- 'keyword monitor' "$test_root/hyprctl.log"
test ! -e "$test_root/config/hypr/monitor-layout.generated.lua"
test -f "$test_root/runtime/omarchy-monitor-studio/keep-test/proposed.json"
test -f "$test_root/runtime/omarchy-monitor-studio/keep-test/previous.json"

# A replacement panel can recover the pending confirmation after an output
# mode change recreates Quickshell's per-screen bar instance.
pending=$(run_layout pending)
jq -e '
  .id == "keep-test" and
  .scope == "settings" and
  .originScreen == "DP-1" and
  .originWorkspace == 5 and
  (.remainingSeconds | type == "number") and
  .remainingSeconds >= 0 and .remainingSeconds <= 15
' <<<"$pending" >/dev/null

# Recreating the widget also invokes restore. It must not overwrite a live
# preview with the previously kept layout while confirmation is pending.
eval_count_before_restore=$(grep -c '^eval ' "$test_root/hyprctl.log")
run_layout restore
eval_count_after_restore=$(grep -c '^eval ' "$test_root/hyprctl.log")
test "$eval_count_before_restore" -eq "$eval_count_after_restore"

# Keep persists the proposed layout into the versioned profile store without
# requiring edits to Hyprland config.
run_layout keep keep-test
state_file="$test_root/state/omarchy/monitor-studio/profiles.json"
jq -e --argjson monitors "$proposed" --argjson workspaces "$workspaces" '
  .schemaVersion == 2 and
  .activeProfileId == (.profiles[0].id) and
  .profiles[0].topology.monitors == $monitors and
  .profiles[0].topology.workspaces == $workspaces and
  (.profiles[0].connectedSet == ["DP-1", "eDP-1"])
' "$state_file" >/dev/null
test ! -e "$test_root/config/hypr/monitor-layout.generated.lua"
! grep -Fx 'reload' "$test_root/hyprctl.log"
grep -F 'eval hl.workspace_rule({ workspace = "1", monitor = "DP-1", default = true, persistent = true }); hl.workspace_rule({ workspace = "2", monitor = "DP-1", default = false, persistent = true }); hl.workspace_rule({ workspace = "4", monitor = "eDP-1", default = true, persistent = true })' "$test_root/hyprctl.log"
test ! -d "$test_root/runtime/omarchy-monitor-studio/keep-test"

# Restore is a no-op for monitor state when the saved v2 profile already
# matches the exact live topology.
: >"$test_root/hyprctl.log"
run_layout restore
restore_eval_count=$(grep -c '^eval hl.monitor' "$test_root/hyprctl.log" || true)
test "$restore_eval_count" -eq 0
grep -F 'eval hl.workspace_rule({ workspace = "1", monitor = "DP-1", default = true, persistent = true }); hl.workspace_rule({ workspace = "2", monitor = "DP-1", default = false, persistent = true }); hl.workspace_rule({ workspace = "4", monitor = "eDP-1", default = true, persistent = true })' "$test_root/hyprctl.log"

# Restore refuses to apply a profile saved for a different connected set.
: >"$test_root/hyprctl.log"
printf '%s' '[{"name":"eDP-1","width":2880,"height":1800,"refreshRate":60,"x":0,"y":0,"scale":2,"availableModes":["2880x1800@60.00Hz"]}]' >"$test_root/monitors.json"
if run_layout restore; then
  echo "restore applied a profile for a different display set" >&2
  exit 1
fi
! grep -F -- 'eval hl.monitor' "$test_root/hyprctl.log"
printf '%s' "$monitors_json" >"$test_root/monitors.json"

# A compositor drift during confirmation is repaired without a full reload.
drift_proposed='[{"name":"DP-1","x":0,"y":0,"width":1920,"height":1080,"refreshRate":59.95,"scale":1,"transform":0}]'
run_layout preview drift-keep "$drift_proposed" "$previous" '{}'
# Force live topology away from the preview so Keep must use its recovery
# reapply path. A failed full reload must be irrelevant to display Keep.
printf '%s' "$monitors_json" >"$test_root/monitors.json"
: >"$test_root/hyprctl.log"
HYPRCTL_FAIL_RELOAD=1 run_layout keep drift-keep
! grep -Fx 'reload' "$test_root/hyprctl.log"
grep -F -- 'eval hl.monitor' "$test_root/hyprctl.log" >/dev/null
test ! -d "$test_root/runtime/omarchy-monitor-studio/drift-keep"
jq -e --argjson monitors "$drift_proposed" '.profiles[0].topology.monitors == $monitors' "$state_file" >/dev/null

# Revert restores the previous live geometry without replacing persistence.
run_layout preview revert-test "$proposed" "$previous" "$workspaces"
run_layout revert revert-test
grep -F -- 'eval hl.monitor({ output = "DP-1", disabled = false, mode = "1920x1080@59.95", position = "1440x0", scale = 1, transform = 0 }); hl.monitor({ output = "eDP-1", disabled = false, mode = "2880x1800@60", position = "0x0", scale = 2, transform = 0 })' "$test_root/hyprctl.log"
test ! -d "$test_root/runtime/omarchy-monitor-studio/revert-test"

# The watchdog uses the same revert path when confirmation expires.
run_layout preview timeout-test "$proposed" "$previous" "$workspaces"
run_layout watchdog timeout-test 0
test ! -d "$test_root/runtime/omarchy-monitor-studio/timeout-test"

# Workspace-only saves keep the current monitor payload and reload immediately.
run_layout save-workspaces "$previous" '{"3":"eDP-1","8":"DP-1"}'
jq -e '.profiles[0].topology.workspaces == {"3":"eDP-1","8":"DP-1"}' "$state_file" >/dev/null
grep -F 'eval hl.workspace_rule({ workspace = "3", monitor = "eDP-1", default = true, persistent = true }); hl.workspace_rule({ workspace = "8", monitor = "DP-1", default = true, persistent = true })' "$test_root/hyprctl.log"

if run_layout preview invalid-test \
  '[{"name":"bad;command","x":0,"y":0,"width":1,"height":1,"refreshRate":60,"scale":1}]' \
  "$previous" '{}'; then
  echo "invalid monitor name was accepted" >&2
  exit 1
fi

if run_layout preview invalid-transform \
  '[{"name":"DP-1","x":0,"y":0,"width":1920,"height":1080,"refreshRate":60,"scale":1,"transform":8}]' \
  "$previous" '{}'; then
  echo "invalid monitor transform was accepted" >&2
  exit 1
fi

# Layouts saved before transform support remain valid and default to normal.
: >"$test_root/hyprctl.log"
legacy='[{"name":"DP-1","x":0,"y":0,"width":1920,"height":1080,"refreshRate":60,"scale":1}]'
run_layout preview legacy-transform "$legacy" "$legacy" '{}'
grep -F -- 'transform = 0' "$test_root/hyprctl.log"
run_layout revert legacy-transform


if run_layout save-workspaces "$previous" '{"1":"bad\"monitor"}'; then
  echo "invalid workspace monitor was accepted" >&2
  exit 1
fi

# Duplicate previews apply a common mode, and Revert restores the exact prior
# extended grouping rather than leaving either output mirrored.
: >"$test_root/hyprctl.log"
topology='[{"name":"DP-1","x":0,"y":0,"width":1920,"height":1080,"refreshRate":59.95,"scale":1,"transform":0},{"name":"eDP-1","x":0,"y":0,"width":1920,"height":1080,"refreshRate":59.95,"scale":1,"transform":0,"mirrorOf":"DP-1"}]'
run_layout preview topology-roundtrip "$topology" "$previous" '{}'
grep -Fx -- 'eval hl.monitor({ output = "DP-1", disabled = false, mode = "1920x1080@59.95", position = "0x0", scale = 1, transform = 0 })' "$test_root/hyprctl.log"
grep -Fx -- 'eval hl.monitor({ output = "eDP-1", disabled = false, mode = "1920x1080@59.95", position = "0x0", scale = 1, transform = 0, mirror = "DP-1" })' "$test_root/hyprctl.log"
test -f "$test_root/runtime/omarchy-monitor-studio/topology-roundtrip/version"
test -f "$test_root/runtime/omarchy-monitor-studio/topology-roundtrip/base-hardware-generation"
test -f "$test_root/runtime/omarchy-monitor-studio/topology-roundtrip/base-snapshot-generation"
run_layout revert topology-roundtrip
tail -n 1 "$test_root/hyprctl.log" | grep -F -- 'output = "DP-1"' | grep -F -- 'output = "eDP-1"'
! tail -n 1 "$test_root/hyprctl.log" | grep -F -- 'mirror ='

# Keeping a Duplicate preview recognizes Hyprland's numeric mirror ID as the
# proposed connector name and does not reload or reapply the live topology.
: >"$test_root/hyprctl.log"
run_layout preview duplicate-keep "$topology" "$previous" '{}' settings '' duplicate
duplicate_eval_count=$(grep -c '^eval hl.monitor' "$test_root/hyprctl.log")
run_layout keep duplicate-keep
test "$duplicate_eval_count" -eq "$(grep -c '^eval hl.monitor' "$test_root/hyprctl.log")"
! grep -Fx 'reload' "$test_root/hyprctl.log"
jq -e '
  .profiles[0].topology.variants.duplicate.monitors[]
  | select(.name == "eDP-1") | .mirrorOf == "DP-1"
' "$state_file" >/dev/null

# If Hyprland cannot resolve a requested mirror source, Preview fails and
# restores the previous extended topology instead of offering a false Keep.
: >"$test_root/hyprctl.log"
printf '%s' "$monitors_json" >"$test_root/monitors.json"
if HYPRCTL_IGNORE_MIRROR=1 run_layout preview unresolved-mirror "$topology" "$previous" '{}'; then
  echo "unresolved mirror preview was accepted" >&2
  exit 1
fi
test ! -d "$test_root/runtime/omarchy-monitor-studio/unresolved-mirror"
jq -e '
  all(.[]; .mirrorOf == "none") and
  (map(select(.name == "DP-1"))[0].x == 1440) and
  (map(select(.name == "eDP-1"))[0].width == 2880)
' "$test_root/monitors.json" >/dev/null

# The no-ID emergency path is independent of panel state and idempotent.
run_layout preview emergency-revert "$proposed" "$previous" '{}'
run_layout revert-pending
test ! -d "$test_root/runtime/omarchy-monitor-studio/emergency-revert"
emergency_eval_count=$(grep -c '^eval hl.monitor' "$test_root/hyprctl.log")
run_layout revert-pending
test "$emergency_eval_count" -eq "$(grep -c '^eval hl.monitor' "$test_root/hyprctl.log")"

# Keep, emergency Revert, and watchdog all use the same atomic claim. Revert
# writes once when it wins; an idempotent Keep writes no topology at all.
for race_number in 1 2 3; do
  race_id="claim-race-$race_number"
  run_layout preview "$race_id" "$proposed" "$previous" '{}'
  before_race=$(grep -c '^eval hl.monitor' "$test_root/hyprctl.log")
  (run_layout keep "$race_id" >/dev/null 2>&1 || true) & keep_pid=$!
  (run_layout revert-pending >/dev/null 2>&1 || true) & revert_pid=$!
  (run_layout watchdog "$race_id" 0 >/dev/null 2>&1 || true) & watchdog_pid=$!
  wait "$keep_pid" "$revert_pid" "$watchdog_pid"
  test ! -d "$test_root/runtime/omarchy-monitor-studio/$race_id"
  after_race=$(grep -c '^eval hl.monitor' "$test_root/hyprctl.log")
  test "$after_race" -ge "$before_race"
  test "$after_race" -le "$((before_race + 1))"
done

# Only one confirmation may exist globally, regardless of transaction ID.
run_layout preview global-lock-a "$proposed" "$previous" '{}'
if run_layout preview global-lock-b "$proposed" "$previous" '{}'; then
  echo "second preview was allowed while a confirmation was pending" >&2
  exit 1
fi
run_layout revert global-lock-a

# An expired transaction is cleaned up instead of blocking new previews.
mkdir -p "$test_root/runtime/omarchy-monitor-studio/stale-id"
printf '2\n' >"$test_root/runtime/omarchy-monitor-studio/stale-id/version"
printf '%s\n' "$proposed" >"$test_root/runtime/omarchy-monitor-studio/stale-id/proposed.json"
printf '%s\n' "$previous" >"$test_root/runtime/omarchy-monitor-studio/stale-id/previous.json"
printf '%s\n' '{}' >"$test_root/runtime/omarchy-monitor-studio/stale-id/workspaces.json"
printf '%s\n' '' >"$test_root/runtime/omarchy-monitor-studio/stale-id/anchor.json"
printf '%s\n' 'deadbeef' >"$test_root/runtime/omarchy-monitor-studio/stale-id/base-hardware-generation"
printf '%s\n' 'deadbeef' >"$test_root/runtime/omarchy-monitor-studio/stale-id/base-snapshot-generation"
printf '%s\n' '1' >"$test_root/runtime/omarchy-monitor-studio/stale-id/expires-at"
printf '%s\n' 'layout' >"$test_root/runtime/omarchy-monitor-studio/stale-id/scope"
run_layout preview stale-cleanup "$proposed" "$previous" '{}'
test ! -d "$test_root/runtime/omarchy-monitor-studio/stale-id"
run_layout revert stale-cleanup

# Legacy pending transactions (no version) fail Keep safely and are not
# surfaced as pending, but remain recoverable through Revert/reload.
mkdir -p "$test_root/runtime/omarchy-monitor-studio/legacy-txn"
printf '%s\n' "$proposed" >"$test_root/runtime/omarchy-monitor-studio/legacy-txn/proposed.json"
printf '%s\n' "$previous" >"$test_root/runtime/omarchy-monitor-studio/legacy-txn/previous.json"
printf '%s\n' '{}' >"$test_root/runtime/omarchy-monitor-studio/legacy-txn/workspaces.json"
printf '%s\n' "$(( $(date +%s) + 60 ))" >"$test_root/runtime/omarchy-monitor-studio/legacy-txn/expires-at"
printf '%s\n' 'layout' >"$test_root/runtime/omarchy-monitor-studio/legacy-txn/scope"
pending=$(run_layout pending)
jq -e '.id == null or .id == ""' <<<"$pending" >/dev/null
if run_layout keep legacy-txn; then
  echo "legacy transaction was kept" >&2
  exit 1
fi
test -f "$test_root/runtime/omarchy-monitor-studio/legacy-txn/previous.json"
: >"$test_root/hyprctl.log"
run_layout revert legacy-txn
grep -F -- 'eval hl.monitor' "$test_root/hyprctl.log" >/dev/null
test ! -d "$test_root/runtime/omarchy-monitor-studio/legacy-txn"

# --- Generation validation and post-apply reconciliation ---

# A proposal referencing an output that is not present fails before any eval.
: >"$test_root/hyprctl.log"
if run_layout preview missing-out \
  '[{"name":"DP-9","x":0,"y":0,"width":1920,"height":1080,"refreshRate":60,"scale":1}]' \
  "$previous" '{}'; then
  echo "missing output was accepted" >&2
  exit 1
fi
! grep -F -- 'eval hl.monitor' "$test_root/hyprctl.log"

# A mode the connector does not advertise fails before any eval.
if run_layout preview bad-mode \
  '[{"name":"DP-1","x":0,"y":0,"width":4096,"height":2160,"refreshRate":60,"scale":1}]' \
  "$previous" '{}'; then
  echo "unavailable mode was accepted" >&2
  exit 1
fi
! grep -F -- 'eval hl.monitor' "$test_root/hyprctl.log"

# Runtime-only link/GPU limits become a structured, actionable rejection and
# never leave a pending transaction behind.
if HYPRCTL_FAIL_EVAL=1 run_layout preview resource-limit "$proposed" "$previous" '{}' \
    2>"$test_root/resource-limit.err"; then
  echo "compositor resource rejection was accepted" >&2
  exit 1
fi
grep -F '"code":"compositor-rejected"' "$test_root/resource-limit.err"
grep -F 'bandwidth or resource limit' "$test_root/resource-limit.err"
test ! -d "$test_root/runtime/omarchy-monitor-studio/resource-limit"

# Hardware identity changing during confirmation rejects Keep and leaves the
# transaction recoverable for Revert.
run_layout preview stale-gen "$proposed" "$previous" '{}'
printf '%s' "$(jq -c 'map(if .name == "DP-1" then .serial = "SWAPPED" else . end)' <<<"$monitors_json")" \
  >"$test_root/monitors.json"
if run_layout keep stale-gen; then
  echo "Keep accepted after hardware changed during confirmation" >&2
  exit 1
fi
test -f "$test_root/runtime/omarchy-monitor-studio/stale-gen/proposed.json"
run_layout revert stale-gen
printf '%s' "$monitors_json" >"$test_root/monitors.json"

# A compositor-adjusted apply is detected: Keep persists the confirmed actual
# geometry and reports the adjustment instead of the unapplied proposal.
run_layout preview adjusted-apply "$proposed" "$previous" '{}'
printf '%s' "$(jq -c 'map(if .name == "DP-1" then .x = 7 else . end)' <<<"$monitors_json")" \
  >"$test_root/monitors.json"
HYPRCTL_IGNORE_EVAL=1 run_layout keep adjusted-apply 2>"$test_root/adjusted.err"
grep -F 'instead of 0,120' "$test_root/adjusted.err"
jq -e '.profiles[0].topology.monitors
  | map(select(.name == "DP-1"))[0].x == 7' "$state_file" >/dev/null
printf '%s' "$monitors_json" >"$test_root/monitors.json"

# Enable/disable is a staged topology transaction with exact rollback.
: >"$test_root/hyprctl.log"
disable_payload='[{"name":"DP-1","enabled":false},{"name":"eDP-1","x":0,"y":0,"width":2880,"height":1800,"refreshRate":60,"scale":2,"transform":0}]'
run_layout preview staged-disable "$disable_payload" "$proposed" '{}'
grep -F -- 'eval hl.monitor({ output = "DP-1", disabled = true }); hl.monitor({ output = "eDP-1", disabled = false, mode = "2880x1800@60", position = "0x0", scale = 2, transform = 0 })' "$test_root/hyprctl.log"
jq -e 'any(.[]; .enabled == false)' \
  "$test_root/runtime/omarchy-monitor-studio/staged-disable/proposed.json" >/dev/null
run_layout revert staged-disable
grep -c -- 'mode = "1920x1080@59.95"' "$test_root/hyprctl.log" >/dev/null

# Keeping a staged disable persists it, including the last-known settings of
# the disabled output.
run_layout preview keep-disable "$disable_payload" "$proposed" '{}'
run_layout keep keep-disable
jq -e '.profiles[0].topology.monitors
  | map(select(.name == "DP-1"))[0]
  | (.enabled == false and .width == 1920 and .height == 1080
     and .refreshRate == 59.95 and .scale == 1)' "$state_file" >/dev/null

# A topology with no active display is rejected before any eval.
: >"$test_root/hyprctl.log"
if run_layout preview all-off \
  '[{"name":"DP-1","enabled":false},{"name":"eDP-1","enabled":false}]' \
  "$previous" '{}'; then
  echo "topology with no active display was accepted" >&2
  exit 1
fi
! grep -F -- 'eval hl.monitor' "$test_root/hyprctl.log"

# A hardware-generation change during confirmation cancels the preview. The
# recovery topology is derived from the fresh enumeration, excludes the lost
# connector, retains an available enabled display, and does not persist the
# transitional snapshot.
printf '%s' "$monitors_json" >"$test_root/monitors.json"
run_layout preview hotplug-cancel "$proposed" "$previous" '{}'
state_before_cancel=$(sha256sum "$state_file" | awk '{print $1}')
printf '%s' "$(jq -c 'map(select(.name == "eDP-1"))' <<<"$monitors_json")" \
  >"$test_root/monitors.json"
run_layout cancel-stale hotplug-cancel
test ! -d "$test_root/runtime/omarchy-monitor-studio/hotplug-cancel"
test "$state_before_cancel" = "$(sha256sum "$state_file" | awk '{print $1}')"
jq -e 'any(.[]; .disabled != true)' "$test_root/monitors.json" >/dev/null
! tail -n 1 "$test_root/hyprctl.log" | grep -F 'output = "DP-1"'

# Cancellation is generation-guarded: an unchanged connected set leaves the
# recoverable transaction pending.
printf '%s' "$monitors_json" >"$test_root/monitors.json"
run_layout preview unchanged-cancel "$proposed" "$previous" '{}'
if run_layout cancel-stale unchanged-cancel; then
  echo "unchanged hardware canceled a valid preview" >&2
  exit 1
fi
test -f "$test_root/runtime/omarchy-monitor-studio/unchanged-cancel/proposed.json"
run_layout revert unchanged-cancel

# Cross-layer regression test: Duplicate proposal generated from TopologyModel
# feeds directly into apply-layer mode validation.
# 1. Mixed-aspect displays with a shared advertised mode generate a valid proposal
#    that passes apply boundary validation.
: >"$test_root/hyprctl.log"
printf '%s' "$monitors_json" >"$test_root/monitors.json"
generated_duplicate=$(node -e '
  const Topology = require("./TopologyModel.js");
  const displays = JSON.parse(process.argv[1]);
  const plan = Topology.prepareDuplicatePreview(displays, {}, "DP-1");
  if (!plan.valid) { process.exit(1); }
  process.stdout.write(JSON.stringify(plan.proposed));
' "$monitors_json")
run_layout preview cross-layer-duplicate "$generated_duplicate" "$previous" '{}'
grep -Fx -- 'eval hl.monitor({ output = "DP-1", disabled = false, mode = "1920x1080@59.95", position = "0x0", scale = 1, transform = 0 })' "$test_root/hyprctl.log"
grep -Fx -- 'eval hl.monitor({ output = "eDP-1", disabled = false, mode = "1920x1080@59.95", position = "0x0", scale = 1, transform = 0, mirror = "DP-1" })' "$test_root/hyprctl.log"
run_layout revert cross-layer-duplicate

# 2. Displays with NO common advertised mode: TopologyModel rejects duplicate
#    planning without generating an unadvertised fallback, and the apply layer
#    rejects any unadvertised mode proposal.
disjoint_monitors='[{"id":0,"name":"DP-1","make":"Test","model":"T1","serial":"SN1","width":1920,"height":1080,"refreshRate":59.95,"x":0,"y":0,"scale":1,"transform":0,"focused":true,"disabled":false,"mirrorOf":"none","availableModes":["1920x1080@59.95Hz"]},{"id":1,"name":"eDP-1","make":"Test","model":"T2","serial":"SN2","width":2880,"height":1800,"refreshRate":60,"x":1920,"y":0,"scale":2,"transform":0,"focused":false,"disabled":false,"mirrorOf":"none","availableModes":["2880x1800@60.00Hz"]}]'
printf '%s' "$disjoint_monitors" >"$test_root/monitors.json"
disjoint_plan_valid=$(node -e '
  const Topology = require("./TopologyModel.js");
  const displays = JSON.parse(process.argv[1]);
  const plan = Topology.prepareDuplicatePreview(displays, {}, "DP-1");
  process.stdout.write(plan.valid ? "true" : "false");
' "$disjoint_monitors")
test "$disjoint_plan_valid" = "false"

unadvertised_fallback='[{"name":"DP-1","x":0,"y":0,"width":1920,"height":1080,"refreshRate":59.95,"scale":1,"transform":0},{"name":"eDP-1","x":0,"y":0,"width":1920,"height":1080,"refreshRate":59.95,"scale":1,"transform":0,"mirrorOf":"DP-1"}]'
if run_layout preview cross-layer-unadvertised "$unadvertised_fallback" "$previous" '{}' 2>"$test_root/unadvertised.err"; then
  echo "unadvertised fallback proposal was accepted by apply boundary" >&2
  exit 1
fi
grep -F '"code":"mode-unavailable"' "$test_root/unadvertised.err"
grep -F 'eDP-1' "$test_root/unadvertised.err"
printf '%s' "$monitors_json" >"$test_root/monitors.json"

echo "apply layout transaction tests passed"
