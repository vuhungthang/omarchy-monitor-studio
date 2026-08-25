const assert = require("node:assert/strict")
const Topology = require("../TopologyModel.js")

const displays = [
  { name: "eDP-1", enabled: true, x: 1920, y: 180, width: 2880, height: 1800,
    refreshRate: 60, scale: 2, transform: 0 },
  { name: "DP-1", enabled: true, x: 3360, y: 0, width: 1920, height: 1080,
    refreshRate: 60, scale: 1, transform: 0 },
  { name: "DP-2", enabled: false, x: 1440, y: 0, width: 1920, height: 1080,
    refreshRate: 144, scale: 1, transform: 1 }
]

// Disabling a display produces a full topology with an enabled:false record.
const disable = Topology.prepareTogglePreview(displays, {}, "DP-1")
assert.equal(disable.changed, true)
assert.equal(disable.valid, true)
assert.deepEqual(
  disable.proposed.find(record => record.name === "DP-1"),
  { name: "DP-1", enabled: false, x: 3360, y: 0, width: 1920, height: 1080,
    refreshRate: 60, scale: 1, transform: 0 })
const eDP = disable.proposed.find(record => record.name === "eDP-1")
// DP-1 is disabled in the proposal, so eDP-1 alone anchors the layout.
assert.equal(eDP.x, 0)
assert.equal(eDP.y, 0)
assert.equal(eDP.width, 2880)

// The previous payload describes the current state, including still-disabled
// outputs, so rollback restores the exact prior topology.
assert.equal(disable.previous.find(r => r.name === "DP-1").enabled, undefined)
assert.equal(disable.previous.find(r => r.name === "DP-2").enabled, false)

// Re-enabling restores the remembered settings unchanged.
const disabledDisplays = [
  Object.assign({}, displays[0]),
  Object.assign({}, displays[1], { enabled: false }),
  Object.assign({}, displays[2])
]
const reenable = Topology.prepareTogglePreview(disabledDisplays, {}, "DP-1")
assert.equal(reenable.changed, true)
assert.equal(reenable.valid, true)
const restored = reenable.proposed.find(record => record.name === "DP-1")
assert.deepEqual(
  { width: restored.width, height: restored.height, refreshRate: restored.refreshRate,
    scale: restored.scale, transform: restored.transform },
  { width: 1920, height: 1080, refreshRate: 60, scale: 1, transform: 0 })

// A disable/keep/refresh/enable round trip retains enough settings to build
// a valid proposal even when the compositor reports the output as disabled.
const roundTrip = Topology.prepareTogglePreview(disable.proposed, {}, "DP-1")
assert.equal(roundTrip.changed, true)
assert.equal(roundTrip.valid, true)
assert.equal(roundTrip.proposed.find(record => record.name === "DP-1").enabled, undefined)

// Hyprland may report a disabled output at 0,0. Re-enabling it must choose a
// safe adjacent position instead of rejecting the action as an overlap.
const overlappingDisabled = [
  { name: "eDP-1", enabled: true, x: 0, y: 0, width: 2880, height: 1800,
    refreshRate: 60, scale: 2, transform: 0 },
  { name: "DP-5", enabled: true, x: -1920, y: -180, width: 1920, height: 1080,
    refreshRate: 75, scale: 1, transform: 0 },
  { name: "DP-4", enabled: false, x: 0, y: 0, width: 1920, height: 1080,
    refreshRate: 60, scale: 1, transform: 0 }
]
const autoPlaced = Topology.prepareTogglePreview(overlappingDisabled, {}, "DP-4")
assert.equal(autoPlaced.valid, true)
assert.deepEqual(
  { x: autoPlaced.proposed.find(record => record.name === "DP-4").x,
    y: autoPlaced.proposed.find(record => record.name === "DP-4").y },
  { x: 3360, y: 180 })

// Disabling the last enabled display is rejected by the model.
const single = [{ name: "eDP-1", enabled: true, x: 0, y: 0, width: 1920,
  height: 1080, refreshRate: 60, scale: 1, transform: 0 }]
const lastDisplay = Topology.prepareTogglePreview(single, {}, "eDP-1")
assert.equal(lastDisplay.changed, true)
assert.equal(lastDisplay.valid, false)
assert.match(lastDisplay.reason, /at least one display/)
assert.equal(
  Topology.validateTopologyPayload([{ name: "a", enabled: false }]).valid, false)

// Overlapping enabled placements are rejected; rotated logical sizes count.
const overlap = [
  { name: "a", x: 0, y: 0, width: 1920, height: 1080, refreshRate: 60, scale: 1, transform: 0 },
  { name: "b", x: 1000, y: 0, width: 1920, height: 1080, refreshRate: 60, scale: 1, transform: 0 }
]
assert.equal(Topology.validateTopologyPayload(overlap).valid, false)
assert.match(Topology.validateTopologyPayload(overlap).reason, /overlap/)

// Touching edges and mixed-DPI/rotation placements stay valid.
const touching = [
  { name: "a", x: 0, y: 0, width: 1920, height: 1080, refreshRate: 60, scale: 1, transform: 0 },
  { name: "b", x: 1920, y: 0, width: 1920, height: 1080, refreshRate: 60, scale: 1, transform: 0 }
]
assert.equal(Topology.validateTopologyPayload(touching).valid, true)

const rotated = [
  { name: "a", x: 0, y: 0, width: 2880, height: 1800, refreshRate: 60, scale: 2, transform: 0 },
  { name: "b", x: 1440, y: 0, width: 1920, height: 1080, refreshRate: 60, scale: 1, transform: 1 }
]
assert.equal(Topology.validateTopologyPayload(rotated).valid, true)
assert.equal(Topology.logicalSize(1920, 1080, 1, 1).width, 1080)
assert.equal(Topology.logicalSize(1920, 1080, 1, 1).height, 1920)

// Duplicate names are rejected.
assert.equal(
  Topology.validateTopologyPayload([
    { name: "a", x: 0, y: 0, width: 100, height: 100, refreshRate: 60, scale: 1 },
    { name: "a", x: 200, y: 0, width: 100, height: 100, refreshRate: 60, scale: 1 }
  ]).valid, false)

// Toggling a display that is already in the requested state is a no-op.
assert.equal(Topology.prepareTogglePreview(displays, {}, "eDP-1").changed, true)
assert.equal(
  Topology.prepareTogglePreview(displays, { "DP-2": { enabled: true } }, "DP-2").changed, false)

// Anchor-relative coordinates preserve displays left of and above a selected
// anchor instead of normalizing everything to the top-left display.
const anchored = Topology.relativeToAnchor([
  { name: "left", x: 0, y: 100, width: 1920, height: 1080, refreshRate: 60, scale: 1 },
  { name: "right", x: 1920, y: 0, width: 2560, height: 1440, refreshRate: 60, scale: 1 }
], "right")
assert.deepEqual(
  anchored.map(record => ({ name: record.name, x: record.x, y: record.y })),
  [{ name: "left", x: -1920, y: 100 }, { name: "right", x: 0, y: 0 }])

// Focus is transient metadata and never affects anchor normalization.
const focusChanged = Topology.relativeToAnchor([
  Object.assign({}, anchored[0], { focused: true }),
  Object.assign({}, anchored[1], { focused: false })
], "right")
assert.deepEqual(
  focusChanged.map(record => ({ name: record.name, x: record.x, y: record.y })),
  anchored.map(record => ({ name: record.name, x: record.x, y: record.y })))

assert.equal(Topology.validAnchor(anchored, "right"), "right")
assert.equal(Topology.validAnchor(anchored, "missing"), "left")

assert.equal(Topology.presetAvailable(displays, "internal"), true)
assert.equal(Topology.presetAvailable(displays, "external"), true)
assert.equal(Topology.presetAvailable(displays, "extend"), true)
assert.equal(Topology.presetAvailable([
  Object.assign({}, displays[0])
], "external"), false)
assert.equal(Topology.currentPreset(displays), "extend")
assert.equal(Topology.currentPreset([]), "")

const internalOnly = Topology.preparePresetPreview(displays, {}, "internal", null)
assert.equal(internalOnly.valid, true)
assert.deepEqual(internalOnly.proposed.map(record => [record.name, record.enabled !== false]), [
  ["eDP-1", true], ["DP-1", false], ["DP-2", false]
])
assert.equal(Topology.currentPreset(internalOnly.proposed), "internal")
assert.deepEqual(Topology.workspacePayloadForPreset(
  { "1": "DP-1", "2": "eDP-1" }, internalOnly.proposed, "eDP-1"),
{ "1": "eDP-1", "2": "eDP-1" })

const externalOnly = Topology.preparePresetPreview(displays, {}, "external", null)
assert.equal(externalOnly.valid, true)
assert.equal(externalOnly.proposed.find(record => record.name === "eDP-1").enabled, false)
assert.equal(externalOnly.proposed.find(record => record.name === "DP-2").enabled, undefined)
assert.equal(Topology.validateTopologyPayload(externalOnly.proposed).valid, true)

const savedInternal = {
  monitors: [
    { name: "eDP-1", x: 0, y: 0, width: 2880, height: 1800,
      refreshRate: 60, scale: 2, transform: 1 },
    { name: "DP-1", enabled: false },
    { name: "DP-2", enabled: false }
  ],
  anchor: "eDP-1"
}
const restoredInternal = Topology.preparePresetPreview(
  displays, {}, "internal", savedInternal)
assert.equal(restoredInternal.restored, true)
assert.equal(restoredInternal.proposed[0].transform, 1)

const incompatibleVariant = Topology.preparePresetPreview(displays, {}, "extend", {
  monitors: [{ name: "missing", x: 0, y: 0, width: 100, height: 100,
    refreshRate: 60, scale: 1, transform: 0 }]
})
assert.equal(incompatibleVariant.restored, false)
assert.equal(incompatibleVariant.valid, true)

const modeChangedDisplays = displays.map(display => Object.assign({}, display, {
  availableModes: [display.width + "x" + display.height + "@" + display.refreshRate + "Hz"]
}))
const unavailableModeVariant = Topology.preparePresetPreview(
  modeChangedDisplays, {}, "internal", Object.assign({}, savedInternal, {
    monitors: savedInternal.monitors.map(record => record.name === "eDP-1"
      ? Object.assign({}, record, { width: 1920 }) : record)
  }))
assert.equal(unavailableModeVariant.restored, false)

const duplicateDisplays = [
  Object.assign({}, displays[0], {
    recommendedResolution: "1920x1080",
    availableModes: ["2880x1800@60.00Hz", "1920x1080@60.00Hz", "1280x720@60.00Hz"]
  }),
  Object.assign({}, displays[1], {
    recommendedResolution: "1920x1080",
    availableModes: ["2560x1440@59.95Hz", "1920x1080@60.00Hz", "1280x720@60.00Hz"]
  })
]
const commonModes = Topology.commonAdvertisedModes(duplicateDisplays)
assert.deepEqual(commonModes.map(mode => [mode.width, mode.height, mode.refreshRate]), [
  [1920, 1080, 60], [1280, 720, 60]
])

const duplicate = Topology.prepareDuplicatePreview(duplicateDisplays, {}, "eDP-1")
assert.equal(duplicate.valid, true)
assert.equal(duplicate.source, "eDP-1")
assert.match(duplicate.summary, /1920 × 1080.*60/)
assert.deepEqual(duplicate.proposed.map(record => [record.name, record.mirrorOf || ""]), [
  ["eDP-1", ""], ["DP-1", "eDP-1"]
])
assert.equal(Topology.validateTopologyPayload(duplicate.proposed).valid, true)
assert.equal(Topology.isDuplicateTopology(duplicate.proposed), true)
assert.equal(Topology.buildTopologyPayload(duplicate.proposed, {})[1].mirrorOf, "eDP-1")

const mismatchedAspectDisplays = duplicateDisplays.map(function(display, index) {
  return Object.assign({}, display, {
    recommendedResolution: index === 0 ? "2880x1800" : "1920x1080"
  })
})
const mismatchedAspectDuplicate = Topology.prepareDuplicatePreview(
  mismatchedAspectDisplays, {}, "eDP-1")
assert.equal(mismatchedAspectDuplicate.valid, false)
assert.match(mismatchedAspectDuplicate.reason, /different aspect ratios.*stretch/i)

// Every non-Duplicate preset must remove live mirror relationships, regardless
// of which display was the Duplicate source.
for (const source of ["eDP-1", "DP-1"]) {
  const mirrored = Topology.prepareDuplicatePreview(duplicateDisplays, {}, source)
  for (const preset of ["extend", "internal", "external"]) {
    const transition = Topology.preparePresetPreview(mirrored.proposed, {}, preset, null)
    assert.equal(transition.valid, true)
    assert.equal(Topology.isDuplicateTopology(transition.proposed), false)
    assert.equal(transition.proposed.some(record => record.mirrorOf), false)
  }
}

// Do not restore an Extend variant contaminated by the old transition bug.
const mirroredExtendVariant = {
  monitors: duplicate.proposed,
  anchor: "eDP-1",
  workspaces: {}
}
const repairedExtend = Topology.preparePresetPreview(
  duplicate.proposed, {}, "extend", mirroredExtendVariant)
assert.equal(repairedExtend.restored, false)
assert.equal(repairedExtend.proposed.some(record => record.mirrorOf), false)

const noCommonMode = Topology.prepareDuplicatePreview([
  Object.assign({}, duplicateDisplays[0], { availableModes: ["2880x1800@60.00Hz"] }),
  Object.assign({}, duplicateDisplays[1], { availableModes: ["1920x1080@60.00Hz"] })
], {}, "eDP-1")
assert.equal(noCommonMode.valid, false)
assert.match(noCommonMode.reason, /common advertised mode/)

assert.equal(Topology.transportLabel("displayport"), "DisplayPort")
assert.equal(Topology.transportLabel("internal"), "Built-in")
assert.match(Topology.constraintReason({ code: "mode-unavailable", output: "DP-1" }),
  /DP-1.*advertised mode.*Refresh/)
assert.match(Topology.explainBackendReport(
  '[{"code":"position-adjusted","output":"DP-1","detail":"placed elsewhere"}]\n'),
  /DP-1.*position.*saved/)
assert.match(Topology.explainBackendReport(
  '[{"code":"resource-conflict","output":"DP-1","detail":"bandwidth"}]\n'),
  /resource limit.*bandwidth/)
assert.match(Topology.constraintReason({ code: "compositor-rejected", detail: "bandwidth" }),
  /lower resolution or refresh rate.*bandwidth/)

console.log("topology model tests passed")
