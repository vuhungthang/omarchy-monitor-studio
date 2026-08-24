const assert = require("node:assert/strict")
const Matcher = require("../ProfileMatcher.js")

function identity(overrides) {
  return Object.assign({
    name: "", sysfsPath: null, connectorInstance: null, transport: "displayport",
    edidHash: null, serial: null, serialTrusted: false,
    make: null, model: null, physicalWidth: null, physicalHeight: null,
    preferredMode: null, modes: []
  }, overrides)
}

const normalized = Matcher.identitiesFromSnapshot({
  connectors: [{ name: "DP-1", sysfsPath: "/sys/card0-DP-1", instance: 1,
    transport: "displayport" }],
  monitors: [{ name: "DP-1", serial: "SERIAL-1", serialTrusted: true,
    make: "Test", model: "Panel", physicalWidth: 476, physicalHeight: 268,
    edidHash: "hash-a", preferredMode: "1920x1080@60Hz" }],
  topology: [{ name: "DP-1", modes: ["1920x1080@60Hz"] }]
})
assert.deepEqual(normalized, [identity({
  name: "DP-1", sysfsPath: "/sys/card0-DP-1", connectorInstance: 1,
  serial: "SERIAL-1", serialTrusted: true, make: "Test", model: "Panel",
  physicalWidth: 476, physicalHeight: 268, edidHash: "hash-a",
  preferredMode: "1920x1080@60Hz", modes: ["1920x1080@60Hz"]
})])

const cases = [
  {
    name: "exact connector and trusted serial",
    saved: [identity({ name: "DP-1", sysfsPath: "/sys/card0-DP-1",
      serial: "SERIAL-1", serialTrusted: true })],
    current: [identity({ name: "DP-1", sysfsPath: "/sys/card0-DP-1",
      serial: "SERIAL-1", serialTrusted: true })],
    status: "exact"
  },
  {
    name: "trusted monitor moved to another connector",
    saved: [identity({ name: "DP-1", serial: "SERIAL-1", serialTrusted: true })],
    current: [identity({ name: "HDMI-A-1", transport: "hdmi",
      serial: "SERIAL-1", serialTrusted: true })],
    status: "moved",
    revalidate: true
  },
  {
    name: "serial-less monitor with connector context is weak",
    saved: [identity({ name: "DP-1", connectorInstance: 1,
      make: "Test", model: "Panel", physicalWidth: 476, physicalHeight: 268 })],
    current: [identity({ name: "DP-1", connectorInstance: 1,
      make: "Test", model: "Panel", physicalWidth: 476, physicalHeight: 268 })],
    status: "weak"
  },
  {
    name: "unrecognized monitor is new",
    saved: [identity({ name: "DP-1", serial: "SERIAL-1", serialTrusted: true })],
    current: [identity({ name: "DP-2", make: "Different", model: "Panel" })],
    status: "new"
  }
]

for (const testCase of cases) {
  const result = Matcher.matchIdentities(testCase.saved, testCase.current)
  assert.equal(result.matches[0].status, testCase.status, testCase.name)
  if (testCase.revalidate)
    assert.equal(result.matches[0].requiresModeRevalidation, true, testCase.name)
  assert.ok(result.matches[0].reason.length > 0, testCase.name)
}

// Identical serial-less monitors without distinguishing connector evidence tie
// and are surfaced as ambiguous rather than silently exchanging assignments.
const savedTwins = [
  identity({ name: "saved-left", make: "Test", model: "Twin",
    physicalWidth: 476, physicalHeight: 268 }),
  identity({ name: "saved-right", make: "Test", model: "Twin",
    physicalWidth: 476, physicalHeight: 268 })
]
const currentTwins = [
  identity({ name: "DP-3", make: "Test", model: "Twin",
    physicalWidth: 476, physicalHeight: 268 }),
  identity({ name: "DP-4", make: "Test", model: "Twin",
    physicalWidth: 476, physicalHeight: 268 })
]
const twins = Matcher.matchIdentities(savedTwins, currentTwins)
assert.deepEqual(twins.matches.map(match => match.status), ["ambiguous", "ambiguous"])
assert.ok(twins.matches.every(match => match.savedName === null))

// A unique EDID hash is strong evidence even without a serial, but moving it
// still requires transport-dependent mode validation.
const edidMove = Matcher.matchIdentities(
  [identity({ name: "DP-1", edidHash: "hash-a" })],
  [identity({ name: "DP-2", edidHash: "hash-a" })])
assert.equal(edidMove.matches[0].status, "moved")
assert.equal(edidMove.matches[0].requiresModeRevalidation, true)

// Results are deterministic regardless of input enumeration order.
const forward = Matcher.matchIdentities(savedTwins, currentTwins)
const reverse = Matcher.matchIdentities(savedTwins.slice().reverse(), currentTwins.slice().reverse())
assert.deepEqual(reverse, forward)

console.log("profile matching tests passed")
