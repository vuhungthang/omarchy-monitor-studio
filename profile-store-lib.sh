#!/bin/bash

# Versioned profile store (schema v2). See docs/security-and-operations.md for
# the persistence contract. State root is inherited from the caller
# ($state_root); nothing here runs hyprctl. A stale or uncertain profile is
# never applied automatically: restoration requires an exact connected-set
# match, decided by the caller using a fresh snapshot.

profile_store_file() {
  printf '%s\n' "$state_root/profiles.json"
}

profile_store_empty() {
  printf '%s\n' '{"schemaVersion":2,"activeProfileId":"","profiles":[]}'
}

profile_store_matcher() {
  printf '%s/ProfileMatcher.js\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
}

profile_store_identities() {
  node "$(profile_store_matcher)" identities "$1"
}

profile_store_status() {
  node "$(profile_store_matcher)" profile-status "$1" "$2"
}

profile_store_load() {
  local file
  file=$(profile_store_file)
  [[ -r $file ]] || return 1
  jq -e '
    .schemaVersion == 2 and
    (.activeProfileId | type == "string") and
    (.profiles | type == "array") and
    all(.profiles[];
      (.id | type == "string" and test("^[A-Za-z0-9._-]+$")) and
      (.name | type == "string" and length > 0 and length <= 64) and
      (.connectedSet | type == "array"
        and all(.[]; type == "string" and test("^[A-Za-z0-9._-]+$"))) and
      (.topology | type == "object") and
      (((.topology.anchor // "") | type == "string") and
        ((.topology.anchor // "") | test("^[A-Za-z0-9._:-]*$"))) and
      (((.topology.variants // {}) | type == "object") and
        all((.topology.variants // {}) | to_entries[];
          (.key | test("^(internal|external|extend|duplicate)$")) and
          (.value | type == "object") and
          (.value.monitors | type == "array") and
          ((.value.anchor // "") | type == "string" and test("^[A-Za-z0-9._:-]*$")))) and
      ((.matchPolicy // {}) | type == "object") and
      (((.matchPolicy // {}).identities // []) | type == "array") and
      (.createdAt | type == "string") and
      (.updatedAt | type == "string"))
  ' "$file" >/dev/null
}

profile_store_save() {
  local store="$1"
  local stage
  umask 077
  mkdir -p "$state_root"
  stage=$(mktemp "$state_root/.profiles.XXXXXX")
  printf '%s\n' "$store" >"$stage"
  mv "$stage" "$(profile_store_file)"
}

profile_store_connected_names() {
  jq -c 'if (.monitors? | type) == "array"
         then [.monitors[].name | select(. != null)]
         elif (.topology? | type) == "array"
         then [.topology[].name | select(. != null)]
         else null end' <<<"$1" | jq -c 'if type == "array" then sort else . end'
}

profile_store_exact_profile_index() {
  # $1 store, $2 sorted names array JSON -> index of first exact match or -1
  jq -r --argjson names "$2" '
    [.profiles[] | (.connectedSet | sort)]
      | to_entries
      | map(select(.value == $names))
      | (.[0].key // -1)
  ' <<<"$1"
}

profile_store_active_profile() {
  jq -r --arg active "$2" '
    [.profiles[] | select(.id == $active)][0] // empty
  ' <<<"$1"
}

profile_store_iso_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

profile_store_valid_name() {
  jq -en --arg name "$1" '$name | (length > 0 and length <= 64 and
    (test("[\u0000-\u001F\u007F]") | not))' >/dev/null
}

profile_store_has_id() {
  jq -e --arg id "$2" 'any(.profiles[]; .id == $id)' <<<"$1" >/dev/null
}

profile_store_rename() {
  local id="$1" name="$2" store now
  [[ $id =~ ^[A-Za-z0-9._-]+$ ]] && profile_store_valid_name "$name" || return 2
  profile_store_load || return 1
  store=$(<"$(profile_store_file)")
  profile_store_has_id "$store" "$id" || return 2
  now=$(profile_store_iso_now)
  store=$(jq -c --arg id "$id" --arg name "$name" --arg now "$now" '
    .profiles |= map(if .id == $id then . + {name: $name, updatedAt: $now} else . end)
  ' <<<"$store")
  profile_store_save "$store"
}

profile_store_select() {
  local id="$1" store
  [[ $id =~ ^[A-Za-z0-9._-]+$ ]] || return 2
  profile_store_load || return 1
  store=$(<"$(profile_store_file)")
  profile_store_has_id "$store" "$id" || return 2
  profile_store_save "$(jq -c --arg id "$id" '.activeProfileId = $id' <<<"$store")"
}

profile_store_duplicate() {
  local source_id="$1" name="$2" store new_id now
  [[ $source_id =~ ^[A-Za-z0-9._-]+$ ]] && profile_store_valid_name "$name" || return 2
  profile_store_load || return 1
  store=$(<"$(profile_store_file)")
  profile_store_has_id "$store" "$source_id" || return 2
  new_id="profile-$(date +%s%N)"
  now=$(profile_store_iso_now)
  store=$(jq -c --arg source "$source_id" --arg id "$new_id" --arg name "$name" --arg now "$now" '
    ([.profiles[] | select(.id == $source)][0]
      + {id: $id, name: $name, createdAt: $now, updatedAt: $now}) as $copy
    | .profiles += [$copy] | .activeProfileId = $id
  ' <<<"$store")
  profile_store_save "$store"
  printf '%s\n' "$new_id"
}

profile_store_delete() {
  local id="$1" confirmation="${2:-}" store
  [[ $confirmation == confirmed && $id =~ ^[A-Za-z0-9._-]+$ ]] || return 2
  profile_store_load || return 1
  store=$(<"$(profile_store_file)")
  profile_store_has_id "$store" "$id" || return 2
  store=$(jq -c --arg id "$id" '
    .profiles |= map(select(.id != $id))
    | if .activeProfileId == $id then .activeProfileId = (.profiles[0].id // "") else . end
  ' <<<"$store")
  profile_store_save "$store"
}

# Import a v1 layout as a legacy profile only when its monitor set exactly
# matches the current connected set. Prints the new store, or returns 1 without
# printing when the import is not safe to perform.
profile_store_import_v1() {
  local v1_json="$1"
  local names="$2"
  local now monitors workspaces v1_names

  v1_names=$(profile_store_connected_names "$v1_json")
  [[ -n $v1_names && $v1_names != null ]] || return 1
  [[ $v1_names == "$names" ]] || return 1
  monitors=$(jq -c '.monitors' <<<"$v1_json") || return 1
  workspaces=$(jq -c '.workspaces // {}' <<<"$v1_json") || return 1
  now=$(profile_store_iso_now)

  jq -cn --argjson monitors "$monitors" --argjson workspaces "$workspaces" \
    --argjson names "$names" --arg now "$now" \
    '{
      schemaVersion: 2,
      activeProfileId: "imported",
      profiles: [{
        id: "imported",
        name: "Migrated layout",
        connectedSet: $names,
        topology: { monitors: $monitors, workspaces: $workspaces },
        matchPolicy: {legacyConnectorOnly: true},
        createdAt: $now,
        updatedAt: $now
      }]
    }'
}
