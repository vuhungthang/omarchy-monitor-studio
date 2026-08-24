#!/bin/bash

# Normalized connector/monitor/topology snapshot producer. See
# docs/hyprland-topology-contract.md for the capability contract this relies on.
#
# monitor_snapshot [JSON]  - emit the normalized snapshot on stdout
#
# Inputs are injectable for tests: the optional argument (or MONITORS_JSON)
# overrides `hyprctl monitors all -j` and MONITOR_SYSFS_ROOT overrides
# /sys/class/drm. Missing EDID, serial, physical size, or sysfs paths become
# explicit null fields; the output is never dropped. Generations are local
# optimistic-concurrency tokens, stable across input ordering.

connector_metadata_json() {
  local sysfs_root=${MONITOR_SYSFS_ROOT:-/sys/class/drm}
  local path base name card instance status edid_hash driver transport
  local first=1

  printf '['
  for path in "$sysfs_root"/card*-*; do
    [[ -d $path ]] || continue
    base=${path##*/}
    name=${base#*-}
    card=${base%%-*}
    [[ $name =~ ^[A-Za-z0-9._-]+$ ]] || continue
    instance=${name##*-}
    [[ $instance =~ ^[0-9]+$ ]] || instance=0

    status="unknown"
    [[ -r $path/status ]] && status=$(<"$path/status")
    edid_hash=""
    [[ -r $path/edid ]] && edid_hash=$(sha256sum "$path/edid" 2>/dev/null | awk '{ print $1 }')
    driver=""
    [[ -e $path/device/driver ]] \
      && driver=$(basename "$(readlink -f "$path/device/driver" 2>/dev/null)" 2>/dev/null)

    (( first )) || printf ','
    first=0
    jq -cn --arg name "$name" --arg sysfsPath "$path" --arg card "$card" \
      --argjson instance "$instance" --arg status "$status" \
      --arg edidHash "$edid_hash" --arg driver "$driver" \
      '{name: $name, sysfsPath: $sysfsPath, card: $card, instance: $instance,
        availability: $status, edidHash: (if $edidHash == "" then null else $edidHash end),
        driver: (if $driver == "" then null else $driver end)}'
  done
  printf ']'
}

snapshot_body_json() {
  local monitors_json="$1"
  local connectors
  connectors=$(connector_metadata_json)

  jq -cn --argjson monitors "$monitors_json" --argjson sysfs "$connectors" '
    def transport($name):
      $name
      | if test("^(eDP|LVDS|DSI)-") then "internal"
        elif test("^DP-") then "displayport"
        elif test("^HDMI-") then "hdmi"
        elif test("^VGA-") then "vga"
        else "unknown" end;

    def sysfs($name):
      ($sysfs | map(select(.name == $name))[0] // {
        sysfsPath: null, card: null, instance: null,
        availability: "unknown", edidHash: null, driver: null
      });

    ($monitors | map(select((.name // "") | test("^[A-Za-z0-9._-]+$")))) as $monitors
    | ($monitors | map(select(.id != null)
        | {key: (.id | tostring), value: .name}) | from_entries) as $name_by_runtime_id
    | ($monitors | map(select((.serial // "") != "")) | group_by(.serial)
        | map(select(length == 1) | .[0].serial)) as $trusted_serials

    | {
        connectors: ($monitors | map(. as $m | sysfs($m.name)
            | . + { name: $m.name, runtimeId: ($m.id // null), transport: transport($m.name) })),
        monitors: ($monitors | map(. as $m | sysfs($m.name) | {
            name: $m.name,
            edidHash: .edidHash,
            serial: (if ($m.serial // "") == "" then null else $m.serial end),
            serialTrusted: (($m.serial // "") != ""
              and ($trusted_serials | index($m.serial)) != null),
            make: (if ($m.make // "") == "" then null else $m.make end),
            model: (if ($m.model // "") == "" then null else $m.model end),
            physicalWidth: ($m.physicalWidth // null),
            physicalHeight: ($m.physicalHeight // null),
            preferredMode: ($m.availableModes // [])[0:1][0] // null
          })),
        topology: ($monitors | map({
            name: .name,
            enabled: (.disabled != true),
            mode: (if ((.width // 0) > 0 and (.height // 0) > 0 and (.refreshRate // 0) > 0)
                    then "\(.width)x\(.height)@\(.refreshRate)" else null end),
            modes: (.availableModes // []),
            x: (.x // null),
            y: (.y // null),
            scale: (.scale // null),
            transform: (.transform // 0),
            mirrorOf: (if (.mirrorOf // "none") == "none" then null
              else ($name_by_runtime_id[(.mirrorOf | tostring)] // .mirrorOf) end),
            focused: (.focused == true)
          }))
      }
  '
}

hardware_generation() {
  jq -r '(
      ([.connectors[] | {name, sysfsPath, availability, edidHash}] | sort_by(.name)),
      ([.monitors[] | {name, serial, edidHash, make, model, physicalWidth, physicalHeight}] | sort_by(.name))
    ) | tostring' | sha256sum | awk '{ print $1 }'
}

snapshot_generation() {
  jq -r '[.connectors, .monitors, .topology] | map(sort_by(.name)) | tostring' \
    | sha256sum | awk '{ print $1 }'
}

monitor_snapshot() {
  local monitors_json="${1:-${MONITORS_JSON:-}}"
  local body hw sg

  if [[ -z $monitors_json ]]; then
    monitors_json=$(hyprctl monitors all -j) || return 1
  fi
  body=$(snapshot_body_json "$monitors_json") || return 1
  hw=$(printf '%s' "$body" | hardware_generation)
  sg=$(printf '%s' "$body" | snapshot_generation)
  jq -cn --argjson body "$body" --arg hw "$hw" --arg sg "$sg" \
    '$body + {hardwareGeneration: $hw, snapshotGeneration: $sg}'
}
