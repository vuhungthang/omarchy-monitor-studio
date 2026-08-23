#!/bin/bash

script_dir=$(cd "$(dirname "$0")" && pwd)
source "$script_dir/monitor-state-lib.sh"

monitors_json=$(hyprctl monitors all -j)
focused_monitor=$(printf '%s\n' "$monitors_json" | jq -r '[.[] | select(.focused == true)][0].name // ""')
preferred_resolutions='{}'

while IFS= read -r monitor_name; do
  preferred_resolution=$(preferred_resolution_for "$monitor_name")
  [[ -n $preferred_resolution ]] || continue
  preferred_resolutions=$(jq -c --arg name "$monitor_name" --arg resolution "$preferred_resolution" \
    '. + {($name): $resolution}' <<<"$preferred_resolutions")
done < <(jq -r '.[].name' <<<"$monitors_json")

{ omarchy-brightness-display --monitor "$focused_monitor" 2>/dev/null; echo; } | head -n 1

printf '%s\n' "$monitors_json" | jq -r '
  def internal: test("^(eDP|LVDS|DSI)-");
  ([.[] | select(.name | internal)][0].name // ""),
  ([.[] | select((.name | internal) | not)][0].name // ""),
  ([.[] | select((.name | internal) and .disabled != true)][0].name // ""),
  ([.[] | select(.mirrorOf != "none") | if (.name | internal) then .mirrorOf else .name end][0] // "")
'

printf '%s\n' "$focused_monitor"
omarchy-hyprland-monitor-scaling 2>/dev/null || echo

printf '%s\n' "$monitors_json" | jq -c --argjson preferred "$preferred_resolutions" '
  [.[] | {
    name,
    enabled:(.disabled != true),
    focused:(.focused == true),
    width,
    height,
    refreshRate,
    scale,
    x,
    y,
    description,
    make,
    model,
    serial,
    availableModes,
    recommendedResolution: ($preferred[.name] // "")
  }]
'

hyprctl workspaces -j 2>/dev/null | jq -c '.' || printf '%s\n' '[]'
hyprctl workspacerules -j 2>/dev/null | jq -c '.' || printf '%s\n' '[]'
