#!/bin/bash

set -euo pipefail

runtime_base="${XDG_RUNTIME_DIR:-/tmp}"
runtime_root="$runtime_base/omarchy-monitor-studio"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/monitor-studio"
layout_file="$state_root/layout.json"
script_path=$(readlink -f "$0")
script_dir=$(cd "$(dirname "$0")" && pwd)
source "$script_dir/monitor-snapshot-lib.sh"
source "$script_dir/profile-store-lib.sh"

validate_id() {
  [[ ${1:-} =~ ^[A-Za-z0-9._-]+$ ]]
}

prepare_runtime_root() {
  local mode

  umask 077
  if [[ ! -d $runtime_base || -L $runtime_base ]]; then
    echo "Runtime base is not a trusted directory" >&2
    return 1
  fi

  # XDG_RUNTIME_DIR is specified as a private, user-owned directory. Enforce
  # that contract because it is the parent trust boundary for restore locks
  # and preview transactions. /tmp is the deliberate compatibility fallback;
  # its child is validated independently below.
  if [[ -n ${XDG_RUNTIME_DIR:-} ]]; then
    [[ -O $runtime_base ]] || {
      echo "Runtime base is not owned by the current user" >&2
      return 1
    }
    mode=$(stat -c '%a' -- "$runtime_base") || return 1
    (( (8#$mode & 077) == 0 )) || {
      echo "Runtime base is accessible by other users" >&2
      return 1
    }
  fi

  if [[ -L $runtime_root ]]; then
    echo "Runtime directory must not be a symbolic link" >&2
    return 1
  elif [[ -e $runtime_root ]]; then
    [[ -d $runtime_root && -O $runtime_root ]] || {
      echo "Runtime directory is not owned by the current user" >&2
      return 1
    }
  else
    mkdir -m 700 -- "$runtime_root" || return 1
  fi

  chmod 700 -- "$runtime_root"
}

validate_payload() {
  jq -e '
    . as $payload |
    type == "array" and length > 0 and
    any(.[]; .enabled != false) and
    all(.[ ];
      (.name | type == "string" and test("^[A-Za-z0-9._:-]+$")) and
      ((.enabled // true) | type == "boolean") and
      ((.mirrorOf // "") | type == "string" and test("^[A-Za-z0-9._:-]*$")) and
      (if .enabled == false then true else
        (.x | type == "number" and floor == . and . >= -100000 and . <= 100000) and
        (.y | type == "number" and floor == . and . >= -100000 and . <= 100000) and
        (.width | type == "number" and floor == . and . > 0 and . <= 32768) and
        (.height | type == "number" and floor == . and . > 0 and . <= 32768) and
        (.refreshRate | type == "number" and . > 0 and . <= 1000) and
        (.scale | type == "number" and . >= 0.5 and . <= 4) and
        ((.transform // 0) | type == "number" and floor == . and . >= 0 and . <= 7)
      end)
    ) and
    all($payload[];
      ((.mirrorOf // "") == "") or
      (. as $target | any($payload[];
        .name != $target.name and .name == $target.mirrorOf and .enabled != false)))
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
  local lua_code="" mirror_code=""
  local statement name x y width height refresh scale transform mirror error

  while IFS= read -r name; do
    statement="hl.monitor({ output = \"$name\", disabled = true })"
    [[ -z $lua_code ]] || lua_code+="; "
    lua_code+="$statement"
  done < <(jq -r '.[] | select(.enabled == false) | .name' <<<"$payload")

  while IFS=$'\t' read -r name x y width height refresh scale transform mirror; do
    statement="hl.monitor({ output = \"$name\", disabled = false, mode = \"${width}x${height}@${refresh}\", position = \"${x}x${y}\", scale = ${scale}, transform = ${transform}"
    [[ -z ${mirror:-} ]] || statement+=", mirror = \"$mirror\""
    statement+=" })"
    if [[ -n ${mirror:-} ]]; then
      [[ -z $mirror_code ]] || mirror_code+="; "
      mirror_code+="$statement"
    else
      [[ -z $lua_code ]] || lua_code+="; "
      lua_code+="$statement"
    fi
  done < <(jq -r '.[] | select(.enabled != false)
                   | [.name, .x, .y, .width, .height, .refreshRate, .scale,
                      (.transform // 0), (.mirrorOf // "")] | @tsv' <<<"$payload")

  # Hyprland must enumerate a mirror source before resolving followers to it.
  # Apply ordinary/source outputs first, then mirrored outputs in a second
  # compositor transaction. Non-mirrored layouts retain their single eval.
  for lua_code in "$lua_code" "$mirror_code"; do
    [[ -n $lua_code ]] || continue
    if ! error=$(hyprctl eval "$lua_code" 2>&1 >/dev/null); then
      jq -cn --arg detail "$error" \
        '[{code: "compositor-rejected", output: "", detail: $detail}]' >&2
      return 1
    fi
  done
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

current_connected_names() {
  monitor_snapshot | jq -c '[.topology[].name] | sort'
}

# Validate a proposed payload against a fresh snapshot. Prints a reasons
# array; returns non-zero when any reason is fatal for the proposal.
validate_proposal() {
  local payload="$1" snapshot="$2" reasons
  reasons=$(jq -cn --argjson payload "$payload" --argjson snapshot "$snapshot" '
    def modes($m): [($m.modes // [])[] | match("^(?<w>[0-9]+)x(?<h>[0-9]+)@(?<r>[0-9]+(\\.[0-9]+)?)Hz?$")
      | {width: (.captures[0].string | tonumber), height: (.captures[1].string | tonumber),
         refreshRate: (.captures[2].string | tonumber)}];
    ($snapshot.topology | map({key: .name, value: .}) | from_entries) as $by_name
    | [$payload[] | . as $p | $by_name[$p.name] as $conn
        | if $conn == null then
            {code: "missing-output", output: $p.name,
             detail: "output is not currently present"}
          elif ($p.enabled != false) then
            (modes($conn) | map(select(.width == $p.width and .height == $p.height
              and ((.refreshRate - $p.refreshRate) | fabs) <= 0.05))) as $match
            | if ($match | length) == 0 then
                {code: "mode-unavailable", output: $p.name,
                 detail: "\($p.width)x\($p.height)@\($p.refreshRate) is not advertised by this output"}
              else empty end
          else empty end]
  ')
  [[ $(jq 'length' <<<"$reasons") -eq 0 ]] && return 0 || {
    printf '%s\n' "$reasons" >&2
    return 1
  }
}

# Compare a proposal with the actual re-enumerated topology. Prints a JSON
# object {payload: confirmed-payload, reasons: [...]} on stdout.
reconcile_actual() {
  local payload="$1" snapshot="$2" previous="${3:-[]}"
  jq -cn --argjson payload "$payload" --argjson snapshot "$snapshot" \
    --argjson previous "$previous" '
    ($snapshot.topology | map({key: .name, value: .}) | from_entries) as $by_name
    | ($previous | map({key: .name, value: .}) | from_entries) as $by_previous
    | [$payload[] | . as $p
        | if ($p.enabled == false) then
            {record: (($by_previous[$p.name] // {}) + $p + {enabled: false}), reasons: []}
          else ($by_name[$p.name] // null) as $a
          | if $a == null then
              {record: null, reasons: [{code: "output-lost", output: $p.name,
                detail: "output disappeared after applying"}]}
            elif ($a.enabled == false) then
              {record: null, reasons: [{code: "output-disabled", output: $p.name,
                detail: "compositor disabled the output after applying"}]}
            else
              (($a.mode // "") | match("^(?<w>[0-9]+)x(?<h>[0-9]+)@(?<r>[0-9]+(\\.[0-9]+)?)$")) as $mode
              | {width: ($mode.captures[0].string | tonumber),
                 height: ($mode.captures[1].string | tonumber),
                 refreshRate: ($mode.captures[2].string | tonumber)} as $mode
              | ($a.mirrorOf // "") as $mirror
              | ($p + {x: ($a.x // $p.x), y: ($a.y // $p.y),
                  width: $mode.width, height: $mode.height,
                  refreshRate: $mode.refreshRate, scale: ($a.scale // $p.scale),
                  transform: ($a.transform // $p.transform)}) as $record
              | (if $mirror != ($p.mirrorOf // "")
                 then $record + {mirrorOf: (if $mirror == "" then null else $mirror end)}
                 else $record end) as $record
              | {
                  record: $record,
                  reasons: (
                    [$record
                      | if .width != $p.width or .height != $p.height
                          or ((.refreshRate - $p.refreshRate) | fabs) > 0.05
                        then {code: "mode-adjusted", output: $p.name,
                          detail: "applied \($record.width)x\($record.height)@\($record.refreshRate) instead of \($p.width)x\($p.height)@\($p.refreshRate)"} else empty end,
                        if .x != $p.x or .y != $p.y
                        then {code: "position-adjusted", output: $p.name,
                          detail: "placed at \($record.x),\($record.y) instead of \($p.x),\($p.y)"} else empty end,
                        if ((.scale - $p.scale) | fabs) > 0.005
                        then {code: "scale-adjusted", output: $p.name,
                          detail: "scale \($record.scale) instead of \($p.scale)"} else empty end,
                        if $mirror != ($p.mirrorOf // "")
                        then {code: "mirror-adjusted", output: $p.name,
                          detail: "mirroring \($mirror)"} else empty end])
                }
            end
        end]
    | {payload: [.[].record | select(. != null)],
       reasons: [.[].reasons[]]}
  '
}

# Return success when a persisted monitor payload already describes the live
# compositor topology. Restore can then refresh workspace ownership without
# forcing another DRM modeset for every per-screen bar widget instance.
topology_matches_snapshot() {
  local payload="$1" snapshot="$2"
  jq -en --argjson payload "$payload" --argjson snapshot "$snapshot" '
    def parsed_mode($value):
      $value
      | capture("^(?<width>[0-9]+)x(?<height>[0-9]+)@(?<refresh>[0-9]+(\\.[0-9]+)?)$")
      | {width: (.width | tonumber), height: (.height | tonumber),
         refreshRate: (.refresh | tonumber)};
    def topology_record_matches($saved; $actual):
      if $actual == null then false
      elif $saved.enabled == false then $actual.enabled == false
      elif $actual.enabled != true then false
      else parsed_mode($actual.mode // "") as $mode
        | $mode.width == $saved.width
        and $mode.height == $saved.height
        and (($mode.refreshRate - $saved.refreshRate) | fabs) <= 0.05
        and $actual.x == $saved.x
        and $actual.y == $saved.y
        and ((($actual.scale // 1) - $saved.scale) | fabs) <= 0.005
        and ($actual.transform // 0) == ($saved.transform // 0)
        and ($actual.mirrorOf // "") == ($saved.mirrorOf // "")
      end;
    ($snapshot.topology | map({key: .name, value: .}) | from_entries) as $live
    | ([$payload[].name] | sort) == ([$snapshot.topology[].name] | sort)
    and ([$payload[] | . as $saved
      | topology_record_matches($saved; $live[$saved.name])] | all)
  ' >/dev/null
}

# Mirror relationships are special: Hyprland can accept a monitor rule before
# its source is resolvable and then report the follower as unmirrored. Never
# present that partial result as a successful preview.
mirror_topology_matches_snapshot() {
  local payload="$1" snapshot="$2"
  jq -en --argjson payload "$payload" --argjson snapshot "$snapshot" '
    ($snapshot.topology | map({key: .name, value: .}) | from_entries) as $live
    | all($payload[];
        if .enabled == false then true
        else (($live[.name].mirrorOf // "") == (.mirrorOf // "")) end)
  ' >/dev/null
}

# Build the safest available form of a transaction's before-topology after a
# hardware change. Settings are restored only when the same connector still
# advertises the prior mode. New, moved, or mode-changed outputs retain their
# freshly enumerated compositor state. If those choices would disable every
# output, the current usable topology wins.
recovery_payload_for_snapshot() {
  local previous="$1" snapshot="$2"
  jq -cn --argjson previous "$previous" --argjson snapshot "$snapshot" '
    def parsedMode($mode):
      ($mode | match("^(?<w>[0-9]+)x(?<h>[0-9]+)@(?<r>[0-9]+(\\.[0-9]+)?)Hz?$")) as $m
      | {width: ($m.captures[0].string | tonumber),
         height: ($m.captures[1].string | tonumber),
         refreshRate: ($m.captures[2].string | tonumber)};
    def actual($entry):
      if $entry.enabled == false or $entry.mode == null then
        {name: $entry.name, enabled: false}
      else (parsedMode($entry.mode)) as $mode
        | {name: $entry.name, x: ($entry.x // 0), y: ($entry.y // 0),
           width: $mode.width, height: $mode.height,
           refreshRate: $mode.refreshRate, scale: ($entry.scale // 1),
           transform: ($entry.transform // 0), mirrorOf: ($entry.mirrorOf // null)}
      end;
    def supports($prior; $entry):
      [($entry.modes // [])[] | parsedMode(.)
        | select(.width == $prior.width and .height == $prior.height
          and ((.refreshRate - $prior.refreshRate) | fabs) <= 0.05)] | length > 0;

    ($previous | map({key: .name, value: .}) | from_entries) as $before
    | ($snapshot.topology | map(actual(.))) as $actual
    | ($snapshot.topology | map(. as $live | ($before[$live.name] // null) as $prior
        | if $prior == null then actual($live)
          elif $prior.enabled == false then {name: $live.name, enabled: false}
          elif supports($prior; $live) then $prior
          else actual($live) end)) as $recovery
    | if any($recovery[]; .enabled != false) then $recovery else $actual end
  '
}

persist_state() {
  local payload="$1"
  local workspaces="${2:-}"
  local choice="${3:-auto}" source_profile_id="${4:-}"
  local anchor="${5:-}"
  local variant="${6:-}"
  local snapshot names identities store status profile_id profile_name now
  [[ -n $workspaces ]] || workspaces='{}'
  [[ $choice =~ ^(auto|update-profile|fork-profile)$ ]] || return 2
  [[ -z $anchor || $anchor =~ ^[A-Za-z0-9._:-]+$ ]] || return 2
  [[ -z $variant || $variant =~ ^(internal|external|extend|duplicate)$ ]] || return 2
  if [[ $choice != auto ]]; then
    validate_id "$source_profile_id" || return 2
  fi

  snapshot=$(monitor_snapshot) || return 1
  names=$(jq -c '[.topology[].name] | sort' <<<"$snapshot")
  identities=$(profile_store_identities "$snapshot") || return 1

  if profile_store_load; then
    store=$(<"$(profile_store_file)")
  else
    store=$(profile_store_empty)
  fi
  now=$(profile_store_iso_now)

  if [[ $choice != auto ]] && ! jq -e --arg id "$source_profile_id" \
      'any(.profiles[]; .id == $id)' <<<"$store" >/dev/null; then
    echo "Selected source profile does not exist" >&2
    return 2
  fi

  status=$(profile_store_status "$store" "$snapshot") || return 1
  if [[ $choice == update-profile ]]; then
    profile_id=$source_profile_id
  elif [[ $choice == fork-profile ]]; then
    profile_id=""
    profile_name=$(jq -r --arg id "$source_profile_id" \
      '.profiles[] | select(.id == $id) | .name + " (moved)"' <<<"$store")
  else
    profile_id=$(jq -r 'select(.status == "exact") | .profileId' <<<"$status")
  fi
  if [[ -n $profile_id ]]; then
    store=$(jq -c --arg id "$profile_id" --argjson monitors "$payload" \
      --argjson workspaces "$workspaces" --argjson names "$names" \
      --argjson identities "$identities" --arg anchor "$anchor" \
      --arg variant "$variant" --arg now "$now" \
      '(.profiles | map(if .id == $id then . as $profile
         | . + {connectedSet: $names,
                   topology: {monitors: $monitors, workspaces: $workspaces, anchor: $anchor,
                     variants: (if $variant == "" then ($profile.topology.variants // {})
                       else ($profile.topology.variants // {}) + {($variant): {
                         monitors: $monitors, workspaces: $workspaces, anchor: $anchor}}
                       end)},
                   matchPolicy: {identities: $identities},
                   updatedAt: $now} else . end))
        as $profiles
        | . + {profiles: $profiles, activeProfileId: $id}' <<<"$store")
  else
    profile_id="layout-$(date +%s%N)"
    [[ -n ${profile_name:-} ]] || profile_name="Current displays"
    store=$(jq -c --arg id "$profile_id" --argjson monitors "$payload" \
      --argjson workspaces "$workspaces" --argjson names "$names" \
      --argjson identities "$identities" --arg name "$profile_name" --arg anchor "$anchor" \
      --arg variant "$variant" --arg now "$now" \
      '. + {profiles: (.profiles + [{
        id: $id,
        name: $name,
        connectedSet: $names,
        topology: { monitors: $monitors, workspaces: $workspaces, anchor: $anchor,
          variants: (if $variant == "" then {} else {($variant): {
            monitors: $monitors, workspaces: $workspaces, anchor: $anchor}} end) },
        matchPolicy: {identities: $identities},
        createdAt: $now,
        updatedAt: $now
      }]), activeProfileId: $id}' <<<"$store")
  fi

  profile_store_save "$store"
  # The v1 backup has now been superseded by a confirmed v2 profile.
  rm -f "$layout_file"
}

apply_profile_topology() {
  local profile="$1" snapshot="${2:-}"
  local monitors workspaces
  monitors=$(jq -c '.topology.monitors' <<<"$profile")
  workspaces=$(jq -c '.topology.workspaces // {}' <<<"$profile")
  validate_payload "$monitors" && validate_workspace_payload "$workspaces" || {
    echo "Invalid saved display profile" >&2
    return 2
  }
  if [[ -z $snapshot ]] || ! topology_matches_snapshot "$monitors" "$snapshot"; then
    apply_payload "$monitors"
  fi
  apply_workspace_payload "$workspaces"
}

restore_layout() {
  local snapshot names store status profile_id profile
  has_pending_transaction && return 0

  snapshot=$(monitor_snapshot) || return 2
  names=$(jq -c '[.topology[].name] | sort' <<<"$snapshot")

  if [[ -e $(profile_store_file) ]]; then
    profile_store_load || {
      echo "Saved display profile store is unreadable; not applied" >&2
      return 3
    }
    store=$(<"$(profile_store_file)")
    status=$(profile_store_status "$store" "$snapshot") || return 3
    profile_id=$(jq -r '.profileId' <<<"$status")
    if [[ $(jq -r '.status' <<<"$status") != exact || -z $profile_id ]]; then
      echo "Saved profile match is $(jq -r '.status' <<<"$status"); confirmation required; not applied" >&2
      return 3
    fi
    profile=$(jq -c --arg id "$profile_id" '.profiles[] | select(.id == $id)' <<<"$store")
    apply_profile_topology "$profile" "$snapshot"
    return
  fi

  if [[ -r $layout_file ]]; then
    if ! store=$(profile_store_import_v1 "$(<"$layout_file")" "$names"); then
      echo "Legacy layout does not match the current displays; not applied" >&2
      return 3
    fi
    profile_store_save "$store"
    profile=$(jq -c '.profiles[0]' <<<"$store")
    apply_profile_topology "$profile" "$snapshot"
    return
  fi
}

# Omarchy renders one bar widget per screen. Their Component.onCompleted hooks
# can all request restore together, so serialize snapshot/check/apply as one
# transaction. Later callers observe the first caller's applied topology and
# take the idempotent path above.
restore_layout_locked() {
  (
    flock -x 9
    restore_layout
  ) 9>"$runtime_root/restore.lock"
}

cleanup_transaction() {
  local transaction_dir="$1"
  rm -f "$transaction_dir/proposed.json" "$transaction_dir/previous.json" \
    "$transaction_dir/workspaces.json" "$transaction_dir/expires-at" \
    "$transaction_dir/scope" "$transaction_dir/version" "$transaction_dir/anchor.json" \
    "$transaction_dir/variant.json" "$transaction_dir/origin-screen" \
    "$transaction_dir/origin-workspace" \
    "$transaction_dir/base-hardware-generation" "$transaction_dir/base-snapshot-generation"
  rmdir "$transaction_dir/claim" 2>/dev/null || true
  rmdir "$transaction_dir" 2>/dev/null || true
}

cleanup_expired_transactions() {
  local transaction_dir expires_at now
  now=$(date +%s)
  for transaction_dir in "$runtime_root"/*; do
    [[ -f $transaction_dir/expires-at ]] || continue
    expires_at=$(<"$transaction_dir/expires-at")
    [[ $expires_at =~ ^[0-9]+$ ]] || continue
    (( expires_at <= now )) && cleanup_transaction "$transaction_dir"
  done
}

transaction_is_pending() {
  local transaction_dir="$1"
  [[ -d $transaction_dir && ! -e $transaction_dir/claim \
    && $(cat "$transaction_dir/version" 2>/dev/null) == 2 \
    && -f $transaction_dir/proposed.json \
    && -f $transaction_dir/previous.json \
    && -f $transaction_dir/workspaces.json \
    && -f $transaction_dir/anchor.json \
    && -f $transaction_dir/base-hardware-generation \
    && -f $transaction_dir/base-snapshot-generation \
    && -f $transaction_dir/expires-at \
    && -f $transaction_dir/scope ]]
}

has_pending_transaction() {
  local transaction_dir
  for transaction_dir in "$runtime_root"/*; do
    transaction_is_pending "$transaction_dir" && return 0
  done
  return 1
}

pending_transaction() {
  local transaction_dir transaction_id expires_at scope origin_workspace now remaining
  local best_id="" best_scope="" best_origin_screen="" best_origin_workspace=0 best_expiry=0

  now=$(date +%s)
  for transaction_dir in "$runtime_root"/*; do
    transaction_is_pending "$transaction_dir" || continue
    transaction_id=${transaction_dir##*/}
    validate_id "$transaction_id" || continue
    expires_at=$(<"$transaction_dir/expires-at")
    scope=$(<"$transaction_dir/scope")
    [[ $expires_at =~ ^[0-9]+$ && $scope =~ ^(layout|settings|topology)$ ]] || continue
    (( expires_at > now && expires_at > best_expiry )) || continue
    best_id=$transaction_id
    best_scope=$scope
    best_origin_screen=$(cat "$transaction_dir/origin-screen" 2>/dev/null || true)
    origin_workspace=$(cat "$transaction_dir/origin-workspace" 2>/dev/null || printf '0')
    [[ $origin_workspace =~ ^[0-9]+$ ]] || origin_workspace=0
    best_origin_workspace=$origin_workspace
    best_expiry=$expires_at
  done

  if [[ -z $best_id ]]; then
    printf '{}\n'
    return
  fi

  remaining=$((best_expiry - now))
  jq -cn --arg id "$best_id" --arg scope "$best_scope" \
    --arg originScreen "$best_origin_screen" \
    --argjson originWorkspace "$best_origin_workspace" \
    --argjson remainingSeconds "$remaining" \
    '{id: $id, scope: $scope, remainingSeconds: $remainingSeconds,
      originScreen: $originScreen, originWorkspace: $originWorkspace}'
}

claim_transaction() {
  mkdir "$1/claim" 2>/dev/null
}

preview_layout() {
  local transaction_id="$1"
  local proposed="$2"
  local previous="$3"
  local workspaces="$4"
  local scope="${5:-layout}"
  local anchor="${6:-}"
  local variant="${7:-}"
  local origin_screen="${8:-}"
  local origin_workspace="${9:-0}"
  local duration="${LAYOUT_CONFIRM_SECONDS:-15}"
  local transaction_dir="$runtime_root/$transaction_id"
  local snapshot

  [[ $scope =~ ^(layout|settings|topology)$ && $duration =~ ^[0-9]+$ ]] || return 2
  [[ -z $anchor || $anchor =~ ^[A-Za-z0-9._:-]+$ ]] || return 2
  [[ -z $variant || $variant =~ ^(internal|external|extend|duplicate)$ ]] || return 2
  [[ -z $origin_screen || $origin_screen =~ ^[A-Za-z0-9._:-]+$ ]] || return 2
  [[ $origin_workspace =~ ^[0-9]+$ ]] || return 2
  validate_payload "$proposed" && validate_payload "$previous" \
    && validate_workspace_payload "$workspaces" || {
    echo "Invalid display layout" >&2
    return 2
  }

  cleanup_expired_transactions
  if has_pending_transaction; then
    echo "A display confirmation is already pending" >&2
    return 3
  fi
  if ! mkdir "$transaction_dir" 2>/dev/null; then
    echo "A display confirmation is already pending" >&2
    return 3
  fi
  trap 'cleanup_transaction "$transaction_dir"' RETURN
  snapshot=$(monitor_snapshot) || return 2
  if ! validate_proposal "$proposed" "$snapshot"; then
    echo "Proposed display layout is not applicable to the current outputs" >&2
    return 7
  fi
  printf '%s\n' "$proposed" >"$transaction_dir/proposed.json"
  printf '%s\n' "$previous" >"$transaction_dir/previous.json"
  printf '%s\n' "$workspaces" >"$transaction_dir/workspaces.json"
  printf '%s\n' '2' >"$transaction_dir/version"
  printf '%s\n' "$anchor" >"$transaction_dir/anchor.json"
  printf '%s\n' "$variant" >"$transaction_dir/variant.json"
  printf '%s' "$snapshot" | jq -r .hardwareGeneration >"$transaction_dir/base-hardware-generation"
  printf '%s' "$snapshot" | jq -r .snapshotGeneration >"$transaction_dir/base-snapshot-generation"
  printf '%s\n' "$(( $(date +%s) + duration ))" >"$transaction_dir/expires-at"
  printf '%s\n' "$scope" >"$transaction_dir/scope"
  printf '%s\n' "$origin_screen" >"$transaction_dir/origin-screen"
  printf '%s\n' "$origin_workspace" >"$transaction_dir/origin-workspace"
  if ! apply_payload "$proposed"; then
    cleanup_transaction "$transaction_dir"
    trap - RETURN
    return 1
  fi
  local applied_snapshot
  if ! applied_snapshot=$(monitor_snapshot) \
      || ! mirror_topology_matches_snapshot "$proposed" "$applied_snapshot"; then
    echo "Compositor did not resolve the requested mirror topology; preview reverted" >&2
    apply_payload "$previous" >/dev/null 2>&1 || hyprctl reload >/dev/null 2>&1 || true
    cleanup_transaction "$transaction_dir"
    trap - RETURN
    return 8
  fi
  trap - RETURN

  if [[ ${LAYOUT_WATCHDOG_DISABLED:-0} != 1 ]]; then
    setsid -f bash "$script_path" watchdog "$transaction_id" "$duration" \
      >/dev/null 2>&1
  fi
}

keep_layout() {
  local transaction_dir="$runtime_root/$1"
  local profile_choice="${2:-auto}" source_profile_id="${3:-}"
  if [[ ! -f $transaction_dir/version ]]; then
    echo "Legacy display confirmation cannot be kept; it remains recoverable by reload" >&2
    return 6
  fi
  [[ -f $transaction_dir/proposed.json && -f $transaction_dir/previous.json ]] || return 4
  claim_transaction "$transaction_dir" || return 5

  local proposed previous workspaces anchor variant base_hardware snapshot confirmed
  proposed=$(<"$transaction_dir/proposed.json")
  previous=$(<"$transaction_dir/previous.json")
  workspaces=$(<"$transaction_dir/workspaces.json")
  anchor=$(<"$transaction_dir/anchor.json")
  variant=$(cat "$transaction_dir/variant.json" 2>/dev/null || true)
  base_hardware=$(<"$transaction_dir/base-hardware-generation")

  snapshot=$(monitor_snapshot)
  if [[ $(jq -r .hardwareGeneration <<<"$snapshot") != "$base_hardware" ]]; then
    echo "Displays changed during confirmation; Keep rejected" >&2
    rmdir "$transaction_dir/claim" 2>/dev/null || true
    return 7
  fi

  # Preview already applied this topology. Persist it without bouncing through
  # the fallback config, which would cause a second DRM modeset and recreate
  # screen-backed shell widgets. If the compositor drifted during confirmation,
  # repair it with the same runtime transaction instead of a full reload.
  if ! topology_matches_snapshot "$proposed" "$snapshot"; then
    if ! apply_payload "$proposed"; then
      rmdir "$transaction_dir/claim" 2>/dev/null || true
      return 1
    fi
  fi
  if ! apply_workspace_payload "$workspaces"; then
    rmdir "$transaction_dir/claim" 2>/dev/null || true
    return 1
  fi

  # Keep persists only the confirmed, re-enumerated result.
  snapshot=$(monitor_snapshot)
  confirmed=$(reconcile_actual "$proposed" "$snapshot" "$previous")
  if [[ $(jq '.reasons | length' <<<"$confirmed") -gt 0 ]]; then
    jq -c '.reasons' <<<"$confirmed" >&2
  fi
  if ! persist_state "$(jq -c .payload <<<"$confirmed")" "$workspaces" \
      "$profile_choice" "$source_profile_id" "$anchor" "$variant"; then
    rmdir "$transaction_dir/claim" 2>/dev/null || true
    return 1
  fi
  cleanup_transaction "$transaction_dir"
}

save_workspace_layout() {
  local monitors="$1"
  local workspaces="$2"
  local anchor="${3:-}"
  validate_payload "$monitors" && validate_workspace_payload "$workspaces" || {
    echo "Invalid workspace layout" >&2
    return 2
  }
  persist_state "$monitors" "$workspaces" auto "" "$anchor"
  hyprctl reload >/dev/null
  apply_payload "$monitors"
  apply_workspace_payload "$workspaces"
}

revert_layout() {
  local transaction_dir="$runtime_root/$1"
  [[ -f $transaction_dir/proposed.json && -f $transaction_dir/previous.json ]] || return 0
  claim_transaction "$transaction_dir" || return 0

  # Legacy transactions (no version file) still recover their previous live
  # geometry; they simply cannot be kept.
  local previous
  previous=$(<"$transaction_dir/previous.json")
  if ! apply_payload "$previous"; then
    rmdir "$transaction_dir/claim" 2>/dev/null || true
    return 1
  fi
  cleanup_transaction "$transaction_dir"
}

revert_pending_layout() {
  local transaction_dir expires_at best_dir="" best_expiry=0
  for transaction_dir in "$runtime_root"/*; do
    transaction_is_pending "$transaction_dir" || continue
    expires_at=$(<"$transaction_dir/expires-at")
    [[ $expires_at =~ ^[0-9]+$ ]] || continue
    if (( expires_at > best_expiry )); then
      best_dir=$transaction_dir
      best_expiry=$expires_at
    fi
  done
  [[ -n $best_dir ]] || return 0
  revert_layout "${best_dir##*/}"
}

cancel_stale_transaction() {
  local transaction_dir="$runtime_root/$1"
  transaction_is_pending "$transaction_dir" || return 4
  claim_transaction "$transaction_dir" || return 5

  local base_hardware snapshot current_hardware previous recovery
  base_hardware=$(<"$transaction_dir/base-hardware-generation")
  snapshot=$(monitor_snapshot) || {
    rmdir "$transaction_dir/claim" 2>/dev/null || true
    return 1
  }
  current_hardware=$(jq -r .hardwareGeneration <<<"$snapshot")
  if [[ $current_hardware == "$base_hardware" ]]; then
    rmdir "$transaction_dir/claim" 2>/dev/null || true
    echo "Displays are unchanged; confirmation remains pending" >&2
    return 7
  fi

  previous=$(<"$transaction_dir/previous.json")
  recovery=$(recovery_payload_for_snapshot "$previous" "$snapshot")
  if ! validate_payload "$recovery" || ! validate_proposal "$recovery" "$snapshot" \
      || ! apply_payload "$recovery"; then
    rmdir "$transaction_dir/claim" 2>/dev/null || true
    echo "Displays changed and safe preview recovery failed; confirmation remains recoverable" >&2
    return 1
  fi

  cleanup_transaction "$transaction_dir"
  echo "Displays changed during confirmation; preview canceled" >&2
}

command=${1:-}

case "$command" in
  preview|keep|revert|revert-pending|cancel-stale|watchdog|restore|pending)
    prepare_runtime_root
    ;;
esac

case "$command" in
  preview)
    (( $# >= 5 && $# <= 10 )) || exit 2
    transaction_id=${2:-}
    validate_id "$transaction_id" || exit 2
    preview_layout "$transaction_id" "$3" "$4" "$5" "${6:-layout}" "${7:-}" "${8:-}" "${9:-}" "${10:-0}"
    ;;
  keep)
    (( $# == 2 || $# == 4 )) || exit 2
    transaction_id=${2:-}
    validate_id "$transaction_id" || exit 2
    [[ $# == 2 || $3 =~ ^(update-profile|fork-profile)$ ]] || exit 2
    [[ $# == 2 ]] || validate_id "$4" || exit 2
    keep_layout "$transaction_id" "${3:-auto}" "${4:-}"
    ;;
  revert)
    (( $# == 2 )) || exit 2
    transaction_id=${2:-}
    validate_id "$transaction_id" || exit 2
    revert_layout "$transaction_id"
    ;;
  revert-pending)
    (( $# == 1 )) || exit 2
    revert_pending_layout
    ;;
  cancel-stale)
    (( $# == 2 )) || exit 2
    transaction_id=${2:-}
    validate_id "$transaction_id" || exit 2
    cancel_stale_transaction "$transaction_id"
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
    restore_layout_locked
    ;;
  pending)
    (( $# == 1 )) || exit 2
    pending_transaction
    ;;
  profile-status)
    (( $# == 1 )) || exit 2
    snapshot=$(monitor_snapshot) || exit 2
    if profile_store_load; then
      profile_store_status "$(<"$(profile_store_file)")" "$snapshot"
    else
      printf '%s\n' '{"status":"new","profileId":"","legacyConnectorOnly":false,"matches":[],"unmatchedSavedNames":[]}'
    fi
    ;;
  profiles)
    (( $# == 1 )) || exit 2
    snapshot=$(monitor_snapshot) || exit 2
    if profile_store_load; then
      store=$(<"$(profile_store_file)")
      status=$(profile_store_status "$store" "$snapshot") || exit 2
      jq -cn --argjson store "$store" --argjson match "$status" '
        {activeProfileId: $store.activeProfileId,
         activeAnchor: ([ $store.profiles[]
           | select(.id == $store.activeProfileId) | .topology.anchor // "" ][0] // ""),
         activeVariants: ([ $store.profiles[]
           | select(.id == $store.activeProfileId) | .topology.variants // {} ][0] // {}),
         profiles: [$store.profiles[] | {id, name, connectedSet}], match: $match}'
    else
      printf '%s\n' '{"activeProfileId":"","activeAnchor":"","activeVariants":{},"profiles":[],"match":{"status":"new","profileId":"","matches":[]}}'
    fi
    ;;
  profile-action)
    (( $# >= 3 )) || exit 2
    action=${2:-}
    profile_id=${3:-}
    validate_id "$profile_id" || exit 2
    case "$action" in
      rename) (( $# == 4 )) || exit 2; profile_store_rename "$profile_id" "$4" ;;
      duplicate) (( $# == 4 )) || exit 2; profile_store_duplicate "$profile_id" "$4" >/dev/null ;;
      select) (( $# == 3 )) || exit 2; profile_store_select "$profile_id" ;;
      delete) (( $# == 4 )) && [[ ${4:-} == confirmed ]] || exit 2; profile_store_delete "$profile_id" confirmed ;;
      *) exit 2 ;;
    esac
    ;;
  save-workspaces)
    (( $# == 3 || $# == 4 )) || exit 2
    save_workspace_layout "$2" "$3" "${4:-}"
    ;;
  *)
    echo "Usage: apply-layout.sh preview ID PROPOSED_JSON PREVIOUS_JSON WORKSPACES_JSON [SCOPE] [ANCHOR] [PRESET] [ORIGIN_SCREEN] [ORIGIN_WORKSPACE] | keep ID [update-profile|fork-profile PROFILE_ID] | revert ID | revert-pending | cancel-stale ID | restore | pending | profiles | profile-action ACTION ID [VALUE] | save-workspaces MONITORS_JSON WORKSPACES_JSON [ANCHOR]" >&2
    exit 2
    ;;
esac
