const assert = require("node:assert/strict")
const Events = require("../DisplayEventModel.js")

// A dock that enumerates two outputs 500 ms apart produces one refresh after
// the 1-second quiet window, rather than matching the partial first snapshot.
let state = Events.initialState("hardware-a")
state = Events.noteHardwareEvent(state, 1000)
assert.equal(state.transitioning, true)
assert.equal(state.refreshAt, 2000)
assert.equal(Events.refreshDue(state, 1999), false)

state = Events.noteHardwareEvent(state, 1500)
assert.equal(state.refreshAt, 2500)
assert.equal(Events.refreshDue(state, 2499), false)
assert.equal(Events.refreshDue(state, 2500), true)

let settled = Events.settleSnapshot(state, "hardware-b")
assert.equal(settled.hardwareChanged, true)
assert.equal(settled.state.transitioning, false)
assert.equal(settled.state.stableAttempts, 1)

// A continuous event storm cannot postpone refresh beyond the 3-second cap.
state = Events.initialState("hardware-a")
state = Events.noteHardwareEvent(state, 1000)
state = Events.noteHardwareEvent(state, 1900)
state = Events.noteHardwareEvent(state, 2800)
state = Events.noteHardwareEvent(state, 3700)
assert.equal(state.refreshAt, 4000)
assert.equal(Events.refreshDue(state, 4000), true)

// The first observed snapshot establishes a baseline and is not treated as a
// hot-plug. Equivalent hardware generations also remain non-cancellations.
settled = Events.settleSnapshot(Events.initialState(""), "hardware-a")
assert.equal(settled.hardwareChanged, false)
settled = Events.settleSnapshot(settled.state, "hardware-a")
assert.equal(settled.hardwareChanged, false)

// Invalid timestamps are ignored instead of creating an unbounded timer.
state = Events.noteHardwareEvent(Events.initialState("hardware-a"), NaN)
assert.equal(state.transitioning, false)

// Identify numbers are connector-stable, ignore transient focus, and exclude
// outputs that are connected but currently disabled.
assert.deepEqual(Events.identifyEntries([
  { name: "eDP-1", enabled: true, focused: true },
  { name: "DP-2", enabled: false },
  { name: "DP-1", enabled: true, focused: false }
]), [
  { name: "DP-1", number: 1 },
  { name: "eDP-1", number: 2 }
])

assert.deepEqual(Events.refreshIntent("manual"), {
  queueIfBusy: true,
  settleTransition: true,
  bypassDebounce: true
})
assert.equal(Events.refreshIntent("poll").queueIfBusy, true)
assert.equal(Events.refreshIntent("poll").bypassDebounce, false)

console.log("display event model tests passed")
