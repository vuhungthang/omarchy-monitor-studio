#!/bin/bash

set -euo pipefail

runtime_root="${XDG_RUNTIME_DIR:-/tmp}/omarchy-monitor-studio"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/monitor-studio"
layout_file="$state_root/layout.json"
script_path=$(readlink -f "$0")

validate_id() {
  [[ ${1:-} =~ ^[A-Za-z0-9._-]+$ ]]
}

validate_payload() {
  jq -e '
    type == "array" and length > 0 and
    all(.[ ];
      (.name | type == "string" and test("^[A-Za-z0-9._:-]+$")) and
      (.x | type == "number" and floor == . and . >= 0 and . <= 100000) and
      (.y | type == "number" and floor == . and . >= 0 and . <= 100000) and
      (.width | type == "number" and floor == . and . > 0 and . <= 32768) and
      (.height | type == "number" and floor == . and . > 0 and . <= 32768) and
      (.refreshRate | type == "number" and . > 0 and . <= 1000) and
      (.scale | type == "number" and . >= 0.5 and . <= 4)
    )
  ' >/dev/null <<<"$1"
}

validate_workspace_payload() {
  jq -e '
    type == "object" and
    all(to_entries[];
      (.key | test("^([1-9]|10)$")) and
      (.value | type == "string" and test("^[A-Za-z0-9._:-]+$"))
    )
  ' >/dev/null <<<"$1"
}

apply_payload() {
  local payload="$1"
  local lua_code=""
  local statement name x y width height refresh scale

  while IFS=$'\t' read -r name x y width height refresh scale; do
    statement="hl.monitor({ output = \"$name\", mode = \"${width}x${height}@${refresh}\", position = \"${x}x${y}\", scale = ${scale} })"
    [[ -z $lua_code ]] || lua_code+="; "
    lua_code+="$statement"
  done < <(jq -r '.[] | [.name, .x, .y, .width, .height, .refreshRate, .scale] | @tsv' <<<"$payload")

  hyprctl eval "$lua_code" >/dev/null
}

apply_workspace_payload() {
  local workspaces="$1"
  local lua_code=""
  local statement workspace monitor is_default
  declare -A default_written=()

  while IFS=$'\t' read -r workspace monitor; do
    [[ -n $workspace && -n $monitor ]] || continue
    is_default=false
    if [[ -z ${default_written[$monitor]:-} ]]; then
      is_default=true
      default_written[$monitor]=1
    fi
    statement="hl.workspace_rule({ workspace = \"$workspace\", monitor = \"$monitor\", default = $is_default, persistent = true })"
    [[ -z $lua_code ]] || lua_code+="; "
    lua_code+="$statement"
  done < <(jq -r 'to_entries | sort_by(.key | tonumber) | .[] | [.key, .value] | @tsv' <<<"$workspaces")

  [[ -z $lua_code ]] || hyprctl eval "$lua_code" >/dev/null
}

persist_state() {
  local payload="$1"
  local workspaces="${2:-}"
  local stage
  [[ -n $workspaces ]] || workspaces='{}'

  umask 077
  mkdir -p "$state_root"
  stage=$(mktemp "$state_root/.layout.XXXXXX")
  trap 'rm -f "$stage"' RETURN
  jq -n --argjson monitors "$payload" --argjson workspaces "$workspaces" \
    '{monitors: $monitors, workspaces: $workspaces}' >"$stage"
  mv "$stage" "$layout_file"
  trap - RETURN
}

restore_layout() {
  local saved monitors workspaces
  [[ -r $layout_file ]] || return 0
  saved=$(<"$layout_file")
  monitors=$(jq -c '.monitors' <<<"$saved") || return 2
  workspaces=$(jq -c '.workspaces // {}' <<<"$saved") || return 2
  validate_payload "$monitors" && validate_workspace_payload "$workspaces" || {
    echo "Invalid saved display layout" >&2
    return 2
  }
  apply_payload "$monitors"
  apply_workspace_payload "$workspaces"
}

cleanup_transaction() {
  local transaction_dir="$1"
  rm -f "$transaction_dir/proposed.json" "$transaction_dir/previous.json" \
    "$transaction_dir/workspaces.json"
  rmdir "$transaction_dir/claim" 2>/dev/null || true
  rmdir "$transaction_dir" 2>/dev/null || true
}

claim_transaction() {
  mkdir "$1/claim" 2>/dev/null
}

preview_layout() {
  local transaction_id="$1"
  local proposed="$2"
  local previous="$3"
  local workspaces="$4"
  local transaction_dir="$runtime_root/$transaction_id"

  validate_payload "$proposed" && validate_payload "$previous" \
    && validate_workspace_payload "$workspaces" || {
    echo "Invalid display layout" >&2
    return 2
  }

  umask 077
  mkdir -p "$runtime_root"
  if ! mkdir "$transaction_dir" 2>/dev/null; then
    echo "A display confirmation is already pending" >&2
    return 3
  fi
  trap 'cleanup_transaction "$transaction_dir"' RETURN
  printf '%s\n' "$proposed" >"$transaction_dir/proposed.json"
  printf '%s\n' "$previous" >"$transaction_dir/previous.json"
  printf '%s\n' "$workspaces" >"$transaction_dir/workspaces.json"
  apply_payload "$proposed"
  trap - RETURN

  if [[ ${LAYOUT_WATCHDOG_DISABLED:-0} != 1 ]]; then
    setsid -f bash "$script_path" watchdog "$transaction_id" "${LAYOUT_CONFIRM_SECONDS:-15}" \
      >/dev/null 2>&1
  fi
}

keep_layout() {
  local transaction_dir="$runtime_root/$1"
  [[ -f $transaction_dir/proposed.json && -f $transaction_dir/previous.json ]] || return 4
  claim_transaction "$transaction_dir" || return 5

  local proposed workspaces
  proposed=$(<"$transaction_dir/proposed.json")
  workspaces=$(<"$transaction_dir/workspaces.json")
  if ! hyprctl reload >/dev/null; then
    rmdir "$transaction_dir/claim" 2>/dev/null || true
    return 1
  fi
  if ! apply_payload "$proposed" || ! apply_workspace_payload "$workspaces"; then
    rmdir "$transaction_dir/claim" 2>/dev/null || true
    return 1
  fi
  if ! persist_state "$proposed" "$workspaces"; then
    rmdir "$transaction_dir/claim" 2>/dev/null || true
    return 1
  fi
  cleanup_transaction "$transaction_dir"
}

save_workspace_layout() {
  local monitors="$1"
  local workspaces="$2"
  validate_payload "$monitors" && validate_workspace_payload "$workspaces" || {
    echo "Invalid workspace layout" >&2
    return 2
  }
  persist_state "$monitors" "$workspaces"
  hyprctl reload >/dev/null
  apply_payload "$monitors"
  apply_workspace_payload "$workspaces"
}

revert_layout() {
  local transaction_dir="$runtime_root/$1"
  [[ -f $transaction_dir/proposed.json && -f $transaction_dir/previous.json ]] || return 0
  claim_transaction "$transaction_dir" || return 0

  if ! apply_payload "$(<"$transaction_dir/previous.json")"; then
    rmdir "$transaction_dir/claim" 2>/dev/null || true
    return 1
  fi
  cleanup_transaction "$transaction_dir"
}

command=${1:-}

case "$command" in
  preview)
    (( $# == 5 )) || exit 2
    transaction_id=${2:-}
    validate_id "$transaction_id" || exit 2
    preview_layout "$transaction_id" "$3" "$4" "$5"
    ;;
  keep)
    (( $# == 2 )) || exit 2
    transaction_id=${2:-}
    validate_id "$transaction_id" || exit 2
    keep_layout "$transaction_id"
    ;;
  revert)
    (( $# == 2 )) || exit 2
    transaction_id=${2:-}
    validate_id "$transaction_id" || exit 2
    revert_layout "$transaction_id"
    ;;
  watchdog)
    (( $# == 3 )) || exit 2
    transaction_id=${2:-}
    validate_id "$transaction_id" || exit 2
    [[ $3 =~ ^[0-9]+$ ]] || exit 2
    sleep "$3"
    revert_layout "$transaction_id"
    ;;
  restore)
    (( $# == 1 )) || exit 2
    restore_layout
    ;;
  save-workspaces)
    (( $# == 3 )) || exit 2
    save_workspace_layout "$2" "$3"
    ;;
  *)
    echo "Usage: apply-layout.sh preview ID PROPOSED_JSON PREVIOUS_JSON WORKSPACES_JSON | keep ID | revert ID | restore | save-workspaces MONITORS_JSON WORKSPACES_JSON" >&2
    exit 2
    ;;
esac
