#!/bin/bash

set -euo pipefail

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
state_root="$test_root/state"
source "$(dirname "$0")/../profile-store-lib.sh"

mkdir -p "$state_root"
store='{"schemaVersion":2,"activeProfileId":"office","profiles":[{"id":"office","name":"Office","connectedSet":["DP-1"],"topology":{},"matchPolicy":{},"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"},{"id":"home","name":"Home","connectedSet":["eDP-1"],"topology":{},"matchPolicy":{},"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}]}'
profile_store_save "$store"

profile_store_rename office "Office Dock"
jq -e '.profiles[] | select(.id == "office") | .name == "Office Dock"' \
  "$(profile_store_file)" >/dev/null

duplicate_id=$(profile_store_duplicate office "Travel Dock")
jq -e --arg id "$duplicate_id" '
  any(.profiles[]; .id == $id and .name == "Travel Dock") and
  .activeProfileId == $id and (.profiles | length == 3)
' "$(profile_store_file)" >/dev/null

profile_store_select home
jq -e '.activeProfileId == "home"' "$(profile_store_file)" >/dev/null

if profile_store_delete home; then
  echo "profile deletion succeeded without confirmation" >&2
  exit 1
fi
jq -e 'any(.profiles[]; .id == "home")' "$(profile_store_file)" >/dev/null

profile_store_delete home confirmed
jq -e '(.profiles | length == 2) and
  (all(.profiles[]; .id != "home")) and .activeProfileId != "home"' \
  "$(profile_store_file)" >/dev/null

if profile_store_rename office $'bad\nname'; then
  echo "profile name with a newline was accepted" >&2
  exit 1
fi

# The command surface used by QML delegates only to profile-store mutations;
# selecting and deleting a profile never invoke Hyprland or alter live state.
cli_state="$test_root/xdg/omarchy/monitor-studio"
mkdir -p "$cli_state"
cp "$(profile_store_file)" "$cli_state/profiles.json"
XDG_STATE_HOME="$test_root/xdg" bash "$(dirname "$0")/../apply-layout.sh" \
  profile-action select office
XDG_STATE_HOME="$test_root/xdg" bash "$(dirname "$0")/../apply-layout.sh" \
  profile-action delete office confirmed
jq -e 'all(.profiles[]; .id != "office")' "$cli_state/profiles.json" >/dev/null

echo "profile management tests passed"
