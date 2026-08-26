// Pure state transitions for coalescing monitor hot-plug bursts. QML owns the
// timers and snapshot process; this module keeps their timing deterministic and
// independently testable.

var QUIET_WINDOW_MS = 1000
var MAX_WAIT_MS = 3000

function initialState(hardwareGeneration) {
  return {
    hardwareGeneration: String(hardwareGeneration || ""),
    burstStartedAt: 0,
    lastEventAt: 0,
    refreshAt: 0,
    transitioning: false,
    stableAttempts: 0
  }
}

function noteHardwareEvent(state, now) {
  var timestamp = Number(now)
  if (!isFinite(timestamp) || timestamp < 0)
    return Object.assign(initialState(""), state || {})

  var current = Object.assign(initialState(""), state || {})
  var burstStartedAt = current.transitioning ? current.burstStartedAt : timestamp
  return Object.assign({}, current, {
    burstStartedAt: burstStartedAt,
    lastEventAt: timestamp,
    refreshAt: Math.min(timestamp + QUIET_WINDOW_MS, burstStartedAt + MAX_WAIT_MS),
    transitioning: true
  })
}

function refreshDue(state, now) {
  var timestamp = Number(now)
  return !!state && state.transitioning === true && isFinite(timestamp)
    && timestamp >= Number(state.refreshAt)
}

function settleSnapshot(state, hardwareGeneration) {
  var current = Object.assign(initialState(""), state || {})
  var nextGeneration = String(hardwareGeneration || "")
  var hardwareChanged = current.hardwareGeneration !== ""
    && nextGeneration !== ""
    && current.hardwareGeneration !== nextGeneration

  return {
    hardwareChanged: hardwareChanged,
    state: {
      hardwareGeneration: nextGeneration || current.hardwareGeneration,
      burstStartedAt: 0,
      lastEventAt: 0,
      refreshAt: 0,
      transitioning: false,
      stableAttempts: current.stableAttempts + (current.transitioning ? 1 : 0)
    }
  }
}

function identifyEntries(displays) {
  return (Array.isArray(displays) ? displays : [])
    .filter(function(display) {
      return display && display.enabled !== false && display.name
    })
    .map(function(display) { return String(display.name) })
    .sort()
    .map(function(name, index) { return { name: name, number: index + 1 } })
}

function refreshIntent(reason) {
  var kind = String(reason || "poll")
  return {
    queueIfBusy: true,
    settleTransition: kind === "manual" || kind === "hotplug",
    bypassDebounce: kind === "manual"
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    QUIET_WINDOW_MS: QUIET_WINDOW_MS,
    MAX_WAIT_MS: MAX_WAIT_MS,
    initialState: initialState,
    noteHardwareEvent: noteHardwareEvent,
    refreshDue: refreshDue,
    settleSnapshot: settleSnapshot,
    identifyEntries: identifyEntries,
    refreshIntent: refreshIntent
  }
}
