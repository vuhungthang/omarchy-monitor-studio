#!/bin/bash

# Shared fake hyprctl for shell integration tests. Writes a stateful stub
# into $1/bin/hyprctl that serves $HYPRCTL_MONITORS for `monitors all -j`
# and applies `eval hl.monitor(...)` statements to that state file, so
# re-enumeration after an apply reflects what was applied.
install_fake_hyprctl() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"
  cat >"$bin_dir/hyprctl" <<'FAKE'
#!/bin/bash
if [[ $1 == monitors ]]; then
  if [[ -f $HYPRCTL_MONITORS.pending ]]; then
    remaining=$(<"$HYPRCTL_MONITORS.pending-polls")
    if (( remaining <= 1 )); then
      mv "$HYPRCTL_MONITORS.pending" "$HYPRCTL_MONITORS"
      rm -f "$HYPRCTL_MONITORS.pending-polls"
    else
      printf '%s\n' "$((remaining - 1))" >"$HYPRCTL_MONITORS.pending-polls"
    fi
  fi
  cat "$HYPRCTL_MONITORS"
  exit 0
fi
if [[ $1 == eval ]]; then
  if [[ -n ${HYPRCTL_EVAL_DELAY:-} ]]; then sleep "$HYPRCTL_EVAL_DELAY"; fi
  printf '%s\n' "eval $2" >>"$HYPRCTL_LOG"
  if [[ ${HYPRCTL_FAIL_EVAL:-0} == 1 ]]; then
    echo "bandwidth or resource limit" >&2
    exit 1
  fi
  if [[ ${HYPRCTL_IGNORE_EVAL:-0} == 1 ]]; then exit 0; fi
  before_state=$(mktemp)
  cp "$HYPRCTL_MONITORS" "$before_state"
  printf '%s\n' "$2" | sed 's/; /\n/g' | while IFS= read -r stmt; do
    grep -q '^hl.monitor(' <<<"$stmt" || continue
    out=$(sed -n 's/.*output = "\([^"]*\)".*/\1/p' <<<"$stmt")
    [[ -n $out ]] || continue
    if grep -q 'disabled = true' <<<"$stmt"; then
      jq --arg n "$out" 'map(if .name == $n then .disabled = true else . end)' \
        "$HYPRCTL_MONITORS" >"$HYPRCTL_MONITORS.tmp" && mv "$HYPRCTL_MONITORS.tmp" "$HYPRCTL_MONITORS"
      continue
    fi
    mode=$(sed -n 's/.*mode = "\([0-9]*\)x\([0-9]*\)@\([0-9.]*\)".*/\1 \2 \3/p' <<<"$stmt")
    pos=$(sed -n 's/.*position = "\(-\{0,1\}[0-9]*\)x\(-\{0,1\}[0-9]*\)".*/\1 \2/p' <<<"$stmt")
    scale=$(sed -n 's/.*scale = \([0-9.]*\).*/\1/p' <<<"$stmt")
    transform=$(sed -n 's/.*transform = \([0-9]*\).*/\1/p' <<<"$stmt")
    mirror_provided=false
    grep -Fq 'mirror = "' <<<"$stmt" && mirror_provided=true
    mirror=$(sed -n 's/.*mirror = "\([^"]*\)".*/\1/p' <<<"$stmt")
    if [[ -n $mirror && ${HYPRCTL_IGNORE_MIRROR:-0} == 1 ]]; then
      mirror=""
    fi
    if [[ -n $mirror ]]; then
      mirror=$(jq -r --arg n "$mirror" 'map(select(.name == $n))[0].id // "none"' \
        "$HYPRCTL_MONITORS")
    elif [[ $mirror_provided == true ]]; then
      mirror=none
    fi
    read -r w h r <<<"$mode"
    read -r x y <<<"$pos"
    jq --arg n "$out" --argjson w "${w:-0}" --argjson h "${h:-0}" --argjson r "${r:-60}" \
       --argjson x "${x:-0}" --argjson y "${y:-0}" --argjson s "${scale:-1}" \
       --argjson t "${transform:-0}" --arg m "${mirror:-}" \
       --argjson mirrorProvided "$mirror_provided" \
      'map(if .name == $n then .width=$w | .height=$h | .refreshRate=$r | .x=$x | .y=$y
           | .scale=$s | .transform=$t
           | (if $mirrorProvided then .mirrorOf=$m else . end)
           | .disabled=false else . end)' \
      "$HYPRCTL_MONITORS" >"$HYPRCTL_MONITORS.tmp" && mv "$HYPRCTL_MONITORS.tmp" "$HYPRCTL_MONITORS"
  done
  if [[ ${HYPRCTL_DEFER_UNMIRROR_POLLS:-0} =~ ^[1-9][0-9]*$ ]] \
      && grep -Fq 'mirror = ""' <<<"$2" \
      && jq -e 'any(.[]; (.mirrorOf // "none") != "none")' "$before_state" >/dev/null; then
    mv "$HYPRCTL_MONITORS" "$HYPRCTL_MONITORS.pending"
    cp "$before_state" "$HYPRCTL_MONITORS"
    printf '%s\n' "$HYPRCTL_DEFER_UNMIRROR_POLLS" >"$HYPRCTL_MONITORS.pending-polls"
  fi
  rm -f "$before_state"
  exit 0
fi
printf '%s\n' "$*" >>"$HYPRCTL_LOG"
[[ ${HYPRCTL_FAIL_RELOAD:-0} != 1 || $* != reload ]]
FAKE
  chmod +x "$bin_dir/hyprctl"
}
