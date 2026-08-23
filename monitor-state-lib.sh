#!/bin/bash

preferred_resolution_for() {
  local monitor_name=${1:-}
  local sysfs_root=${MONITOR_SYSFS_ROOT:-/sys/class/drm}
  local decoder=${MONITOR_EDID_DECODER:-edid-decode}
  local cache_root=${MONITOR_RECOMMENDATION_CACHE:-${XDG_RUNTIME_DIR:-/tmp}/omarchy-monitor-studio-edid}
  local connector output resolution edid_hash monitor_hash cache_file cached_hash cached_resolution stage

  [[ -n $monitor_name ]] || return 0
  if [[ $decoder == */* ]]; then
    [[ -x $decoder ]] || return 0
  else
    command -v "$decoder" >/dev/null 2>&1 || return 0
  fi
  monitor_hash=$(printf '%s' "$monitor_name" | sha256sum | awk '{ print $1 }')

  for connector in "$sysfs_root"/card*-"$monitor_name"; do
    # Sysfs reports EDID attribute files as zero bytes even when reading them
    # returns the full binary blob, so test readability rather than file size.
    [[ -r $connector/status && -r $connector/edid ]] || continue
    [[ $(<"$connector/status") == connected ]] || continue

    cache_file=""
    edid_hash=$(sha256sum "$connector/edid" 2>/dev/null | awk '{ print $1 }')
    if [[ -n $edid_hash && -n $monitor_hash ]]; then
      cache_file="$cache_root/$monitor_hash"
      if [[ -r $cache_file ]]; then
        read -r cached_hash cached_resolution <"$cache_file" || true
        if [[ $cached_hash == "$edid_hash" && $cached_resolution =~ ^[0-9]+x[0-9]+$ ]]; then
          printf '%s\n' "$cached_resolution"
          return 0
        fi
      fi
    fi

    output=$(LC_ALL=C "$decoder" -s --skip-sha -n "$connector/edid" 2>/dev/null) || continue
    resolution=$(awk '/^Native Video Resolution:$/ { getline; print $1; exit }' <<<"$output")
    if [[ $resolution =~ ^[0-9]+x[0-9]+$ ]]; then
      if [[ -n ${cache_file:-} ]]; then
        umask 077
        mkdir -p "$cache_root"
        stage=$(mktemp "$cache_root/.recommendation.XXXXXX")
        printf '%s %s\n' "$edid_hash" "$resolution" >"$stage"
        mv "$stage" "$cache_file"
      fi
      printf '%s\n' "$resolution"
      return 0
    fi
  done
}
