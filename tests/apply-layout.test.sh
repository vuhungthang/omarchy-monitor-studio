#!/bin/bash

set -euo pipefail

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/config/hypr" "$test_root/runtime" "$test_root/state"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >>"$HYPRCTL_LOG"\n[[ ${HYPRCTL_FAIL_RELOAD:-0} != 1 || $* != reload ]]\n' >"$test_root/bin/hyprctl"
chmod +x "$test_root/bin/hyprctl"

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
  LAYOUT_WATCHDOG_DISABLED=1 \
    bash "$script" "$@"
}

# Preview changes the live layout but does not persist it.
run_layout preview keep-test "$proposed" "$previous" "$workspaces" settings
grep -F -- 'eval hl.monitor({ output = "DP-1", mode = "1920x1080@59.95", position = "0x120", scale = 1, transform = 1 }); hl.monitor({ output = "eDP-1", mode = "2880x1800@60", position = "1080x0", scale = 2, transform = 0 })' "$test_root/hyprctl.log"
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
  (.remainingSeconds | type == "number") and
  .remainingSeconds >= 0 and .remainingSeconds <= 15
' <<<"$pending" >/dev/null

# Recreating the widget also invokes restore. It must not overwrite a live
# preview with the previously kept layout while confirmation is pending.
eval_count_before_restore=$(grep -c '^eval ' "$test_root/hyprctl.log")
run_layout restore
eval_count_after_restore=$(grep -c '^eval ' "$test_root/hyprctl.log")
test "$eval_count_before_restore" -eq "$eval_count_after_restore"

# Keep persists the proposed layout without requiring edits to Hyprland config.
run_layout keep keep-test
state_file="$test_root/state/omarchy/monitor-studio/layout.json"
jq -e --argjson monitors "$proposed" --argjson workspaces "$workspaces" \
  '.monitors == $monitors and .workspaces == $workspaces' "$state_file" >/dev/null
test ! -e "$test_root/config/hypr/monitor-layout.generated.lua"
grep -Fx 'reload' "$test_root/hyprctl.log"
grep -F 'eval hl.workspace_rule({ workspace = "1", monitor = "DP-1", default = true, persistent = true }); hl.workspace_rule({ workspace = "2", monitor = "DP-1", default = false, persistent = true }); hl.workspace_rule({ workspace = "4", monitor = "eDP-1", default = true, persistent = true })' "$test_root/hyprctl.log"
test ! -d "$test_root/runtime/omarchy-monitor-studio/keep-test"

# Restore reapplies the saved state on a clean install with no monitors.lua loader.
: >"$test_root/hyprctl.log"
run_layout restore
grep -F -- 'eval hl.monitor({ output = "DP-1", mode = "1920x1080@59.95", position = "0x120", scale = 1, transform = 1 }); hl.monitor({ output = "eDP-1", mode = "2880x1800@60", position = "1080x0", scale = 2, transform = 0 })' "$test_root/hyprctl.log"
grep -F 'eval hl.workspace_rule({ workspace = "1", monitor = "DP-1", default = true, persistent = true }); hl.workspace_rule({ workspace = "2", monitor = "DP-1", default = false, persistent = true }); hl.workspace_rule({ workspace = "4", monitor = "eDP-1", default = true, persistent = true })' "$test_root/hyprctl.log"

# A failed Keep must not replace the last known-good persistent state.
failed_proposed='[{"name":"DP-1","x":0,"y":0,"width":1280,"height":720,"refreshRate":60,"scale":1}]'
run_layout preview failed-keep "$failed_proposed" "$previous" '{}'
if HYPRCTL_FAIL_RELOAD=1 run_layout keep failed-keep; then
  echo "Keep succeeded after a failed Hyprland reload" >&2
  exit 1
fi
jq -e --argjson monitors "$proposed" '.monitors == $monitors' "$state_file" >/dev/null
run_layout revert failed-keep

# Revert restores the previous live geometry without replacing persistence.
run_layout preview revert-test "$proposed" "$previous" "$workspaces"
run_layout revert revert-test
grep -F -- 'eval hl.monitor({ output = "DP-1", mode = "1920x1080@59.95", position = "1440x0", scale = 1, transform = 0 }); hl.monitor({ output = "eDP-1", mode = "2880x1800@60", position = "0x0", scale = 2, transform = 0 })' "$test_root/hyprctl.log"
test ! -d "$test_root/runtime/omarchy-monitor-studio/revert-test"

# The watchdog uses the same revert path when confirmation expires.
run_layout preview timeout-test "$proposed" "$previous" "$workspaces"
run_layout watchdog timeout-test 0
test ! -d "$test_root/runtime/omarchy-monitor-studio/timeout-test"

# Workspace-only saves keep the current monitor payload and reload immediately.
run_layout save-workspaces "$previous" '{"3":"eDP-1","8":"DP-1"}'
jq -e '.workspaces == {"3":"eDP-1","8":"DP-1"}' "$state_file" >/dev/null
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

echo "apply layout transaction tests passed"
