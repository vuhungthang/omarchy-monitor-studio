const assert = require("node:assert/strict")
const Model = require("../Model.js")

function display(overrides) {
  return Object.assign({
    name: "DP-1",
    enabled: true,
    focused: false,
    width: 1920,
    height: 1080,
    refreshRate: 60,
    scale: 1,
    x: 0,
    y: 0
  }, overrides || {})
}

{
  assert.equal(Model.nextExpandedSection("", "workspaces"), "workspaces")
  assert.equal(Model.nextExpandedSection("workspaces", "display"), "display")
  assert.equal(Model.nextExpandedSection("display", "display"), "")
}

{
  const assignments = Model.workspaceAssignments(
    [display({ name: "DP-4" }), display({ name: "DP-6" }), display({ name: "eDP-1" })],
    [
      { id: 1, name: "1", monitor: "eDP-1" },
      { id: 2, name: "2", monitor: "DP-4" },
      { id: 4, name: "4", monitor: "DP-6" }
    ],
    [
      { workspaceString: "2", monitor: "DP-6" },
      { workspaceString: "3", enabled: true },
      { workspaceString: "special:scratchpad", monitor: "DP-4" }
    ],
    10
  )

  assert.deepEqual(assignments, {
    "1": "eDP-1",
    "2": "DP-6",
    "4": "DP-6"
  })
  assert.deepEqual(Model.workspacesForMonitor(assignments, "DP-6"), [2, 4])
  assert.deepEqual(Model.toggleWorkspaceAssignment(assignments, 1, "DP-4"), {
    "1": "DP-4",
    "2": "DP-6",
    "4": "DP-6"
  })
  assert.deepEqual(Model.toggleWorkspaceAssignment(assignments, 2, "DP-6"), {
    "1": "eDP-1",
    "4": "DP-6"
  })
  assert.equal(Model.workspaceAssignmentsEqual(assignments, {
    "4": "DP-6",
    "2": "DP-6",
    "1": "eDP-1"
  }), true)
}

{
  const resolutions = Model.availableResolutions([
    "1920x1080@60.00Hz",
    "1920x1080@74.97Hz",
    "1600x900@60.00Hz",
    "not-a-mode"
  ], "1600x900")

  assert.deepEqual(resolutions, [
    { value: "1600x900@60", label: "1600 × 900 (Recommended)", width: 1600, height: 900, refreshRate: 60, recommended: true },
    { value: "1920x1080@60", label: "1920 × 1080", width: 1920, height: 1080, refreshRate: 60, recommended: false }
  ])
  assert.equal(Model.matchingResolutionValue(resolutions, 1920, 1080), "1920x1080@60")
  assert.equal(Model.matchingResolutionValue(resolutions, 1280, 720), "")
}

{
  const resolutions = Model.availableResolutions([
    "2560x1440@60.00Hz",
    "1920x1080@60.00Hz"
  ], "")

  assert.equal(resolutions[0].label, "2560 × 1440 (Recommended)")
  assert.equal(resolutions[0].recommended, true)
}

{
  assert.deepEqual(Model.parseDisplayMode("2560x1440@143.97Hz"), {
    width: 2560,
    height: 1440,
    refreshRate: 143.97,
    value: "2560x1440@143.97"
  })
  assert.equal(Model.parseDisplayMode("preferred"), null)
}

{
  const displays = [
    display({ name: "DP-4", x: -1920, y: 0 }),
    display({ name: "eDP-1", width: 2880, height: 1800, scale: 2, x: 0, y: 180 }),
    display({ name: "DP-9", enabled: false, x: 4000 })
  ]

  assert.deepEqual(Model.buildMonitorSettingPayload(displays, "DP-4", {
    width: 1600,
    height: 900,
    refreshRate: 60,
    scale: 1
  }), [
    { name: "DP-4", x: 0, y: 0, width: 1600, height: 900, refreshRate: 60, scale: 1 },
    { name: "eDP-1", x: 1920, y: 180, width: 2880, height: 1800, refreshRate: 60, scale: 2 }
  ])
}

{
  const displays = [
    display({ name: "DP-4", x: -1920, y: 0 }),
    display({ name: "eDP-1", width: 2880, height: 1800, scale: 2, x: 0, y: 180 })
  ]

  assert.deepEqual(Model.prepareDisplaySettingPreview(displays, {}, "DP-4", {
    width: 1600,
    height: 900,
    refreshRate: 60,
    scale: 1
  }), {
    changed: true,
    stagedSettings: { "DP-4": { width: 1600, height: 900 } },
    previous: [
      { name: "DP-4", x: 0, y: 0, width: 1920, height: 1080, refreshRate: 60, scale: 1 },
      { name: "eDP-1", x: 1920, y: 180, width: 2880, height: 1800, refreshRate: 60, scale: 2 }
    ],
    proposed: [
      { name: "DP-4", x: 0, y: 0, width: 1600, height: 900, refreshRate: 60, scale: 1 },
      { name: "eDP-1", x: 1920, y: 180, width: 2880, height: 1800, refreshRate: 60, scale: 2 }
    ]
  })

  assert.deepEqual(Model.prepareDisplaySettingPreview(displays, {}, "DP-4", {
    width: 1920,
    height: 1080,
    refreshRate: 60,
    scale: 1
  }), {
    changed: false,
    stagedSettings: {},
    previous: [],
    proposed: []
  })
}

{
  const displays = [
    display({ name: "DP-4", width: 1920, height: 1080, refreshRate: 60, scale: 1 }),
    display({ name: "eDP-1", width: 2880, height: 1800, refreshRate: 60, scale: 2 })
  ]
  const staged = Model.stageDisplaySettings(displays, {}, "DP-4", {
    width: 1600,
    height: 900,
    refreshRate: 60,
    scale: 1
  })

  assert.deepEqual(staged, {
    "DP-4": { width: 1600, height: 900 }
  })
  assert.deepEqual(Model.displaysWithSettings(displays, staged).map(item => ({
    name: item.name,
    width: item.width,
    height: item.height
  })), [
    { name: "DP-4", width: 1600, height: 900 },
    { name: "eDP-1", width: 2880, height: 1800 }
  ])
  assert.deepEqual(Model.stageDisplaySettings(displays, staged, "DP-4", {
    width: 1920,
    height: 1080,
    refreshRate: 60,
    scale: 1
  }), {})
  assert.deepEqual(Model.retainDisplaySettings([
    display({ name: "DP-4", enabled: false }),
    display({ name: "eDP-1", enabled: true })
  ], {
    "DP-4": { width: 1600 },
    "eDP-1": { scale: 1.6 }
  }), {
    "eDP-1": { scale: 1.6 }
  })
}

{
  const displays = [
    display({ name: "DP-4", x: 0, y: 0 }),
    display({ name: "eDP-1", width: 2880, height: 1800, scale: 2, x: 1920, y: 180 })
  ]
  const preview = [
    { name: "DP-4", logicalX: 0, logicalY: 0 },
    { name: "eDP-1", logicalX: 1920, logicalY: 180 }
  ]

  assert.deepEqual(Model.buildDisplayLayoutPayload(displays, preview, {
    "DP-4": { width: 1600, height: 900, scale: 1.25 }
  }), [
    { name: "DP-4", x: 0, y: 0, width: 1600, height: 900, refreshRate: 60, scale: 1.25 },
    { name: "eDP-1", x: 1920, y: 180, width: 2880, height: 1800, refreshRate: 60, scale: 2 }
  ])
}

{
  const two = Model.responsiveDisplayUtilization(2)
  const four = Model.responsiveDisplayUtilization(4)
  const eight = Model.responsiveDisplayUtilization(8)
  const sixteen = Model.responsiveDisplayUtilization(16)

  assert.ok(two > four)
  assert.ok(four > eight)
  assert.ok(eight > sixteen)
  assert.ok(1 / (four * four) > 4)
  assert.ok(1 / (eight * eight) > 8)
  assert.ok(sixteen >= 0.1)
}

{
  const displays = Array.from({ length: 8 }, (_, index) =>
    display({ name: "DP-" + (index + 1), x: 0, y: 0 }))
  const fitted = Model.fitDisplayLayout(
    displays, 1400, 800, 24,
    Model.responsiveDisplayUtilization(displays.length)
  )
  const workspaceWidth = (1400 - 48) / fitted.scale
  const workspaceHeight = (800 - 48) / fitted.scale
  const columns = Math.floor(workspaceWidth / 1920)
  const rows = Math.floor(workspaceHeight / 1080)

  assert.ok(columns * rows >= displays.length)
}

{
  const displays = [
    display({ name: "DP-1", x: 0, y: 0 }),
    display({ name: "DP-2", x: 0, y: 0 })
  ]
  const fitted = Model.fitDisplayLayout(
    displays, 1400, 800, 24,
    Model.responsiveDisplayUtilization(displays.length)
  )
  const anchor = fitted.items[0]
  const moved = Model.moveDisplayInCanvas(
    fitted.items, "DP-2", anchor.x + anchor.width, anchor.y,
    fitted.scale, 24, 1400, 800, 12
  )
  const placed = moved.find(item => item.name === "DP-2")

  assert.equal(placed.logicalX, anchor.logicalX + anchor.logicalWidth)
}

{
  assert.equal(Model.cycleDisplayIndex(0, 6, -1), 5)
  assert.equal(Model.cycleDisplayIndex(5, 6, 1), 0)
  assert.equal(Model.cycleDisplayIndex(-1, 6, 1), 0)
}

{
  assert.equal(Model.displayLabel(display({
    name: "eDP-1",
    make: "Apple Inc.",
    model: "Color LCD"
  })), "Built-in Display")
}

{
  assert.equal(Model.displayLabel(display({
    name: "DP-4",
    make: "Samsung Electric Company",
    model: "LF24T35"
  })), "Samsung LF24T35")
}

{
  assert.equal(Model.displayLabel(display({
    name: "HDMI-A-1",
    make: "",
    model: "",
    description: ""
  })), "HDMI-A-1")
}

{
  const fitted = Model.fitDisplayLayout([
    display({ name: "DP-1" }),
    display({ name: "eDP-1", width: 2880, height: 1800, scale: 2, x: 1920 })
  ], 320, 160, 10)

  assert.equal(fitted.items.length, 2)
  assert.equal(fitted.items[0].label, "DP-1")
  assert.equal(fitted.items[1].label, "Built-in Display")
  assert.equal(fitted.items[0].logicalWidth, 1920)
  assert.equal(fitted.items[1].logicalWidth, 1440)
  assert.equal(fitted.items[1].logicalHeight, 900)
  assert.ok(fitted.items[1].x > fitted.items[0].x + fitted.items[0].width - 0.01)
}

{
  const displays = [
    display({ name: "DP-1", x: 0, y: 0 }),
    display({ name: "eDP-1", width: 2880, height: 1800, scale: 2, x: 1920, y: 180 }),
    display({ name: "DP-3", x: 0, y: 180 })
  ]
  const compact = Model.fitDisplayLayout(displays, 320, 170, 10)
  const moved = Model.moveDisplayInCanvas(
    compact.items, "DP-3", compact.items[2].x, compact.items[2].y + 12,
    compact.scale, 10, 320, 170, 0
  )
  const expanded = Model.refitDisplayLayout(displays, moved, 1400, 800, 24, 0.4)
  const right = expanded.items.find(item => item.name === "eDP-1")
  const placedRight = Model.moveDisplayInCanvas(
    expanded.items, "DP-3", right.x + right.width, right.y,
    expanded.scale, 24, 1400, 800, 12
  )
  const third = placedRight.find(item => item.name === "DP-3")

  assert.deepEqual(
    Model.normalizeDisplayLayout(expanded.items),
    Model.normalizeDisplayLayout(moved)
  )
  assert.ok(expanded.items[0].width > compact.items[0].width * 1.5)
  for (const item of expanded.items) {
    assert.ok(item.x >= 24)
    assert.ok(item.y >= 24)
    assert.ok(item.x + item.width <= 1400 - 24)
    assert.ok(item.y + item.height <= 800 - 24)
  }
  assert.equal(third.logicalX, right.logicalX + right.logicalWidth)
}

{
  const normalized = Model.normalizeDisplayLayout([
    { name: "left", logicalX: -1920, logicalY: 120 },
    { name: "right", logicalX: 0, logicalY: 0 }
  ])

  assert.deepEqual(normalized, [
    { name: "left", x: 0, y: 120 },
    { name: "right", x: 1920, y: 0 }
  ])
}

{
  const snapped = Model.snapDisplayPosition(
    { name: "moving", logicalX: 1912, logicalY: 7, logicalWidth: 1440, logicalHeight: 900 },
    [{ name: "anchor", logicalX: 0, logicalY: 0, logicalWidth: 1920, logicalHeight: 1080 }],
    12
  )

  assert.deepEqual(snapped, { x: 1920, y: 0 })
}

{
  const items = [
    { name: "anchor", logicalX: 0, logicalY: 0, logicalWidth: 1920, logicalHeight: 1080, width: 160, height: 90, x: 10, y: 10 },
    { name: "moving", logicalX: 1920, logicalY: 0, logicalWidth: 1440, logicalHeight: 900, width: 120, height: 75, x: 170, y: 10 }
  ]
  const moved = Model.moveDisplayInCanvas(items, "moving", 168, 16, 1 / 12, 10, 320, 160, 12)
  const moving = moved.find(item => item.name === "moving")

  assert.equal(moving.logicalX, 1920)
  assert.equal(moving.logicalY, 0)
  assert.equal(moving.x, 170)
  assert.equal(moving.y, 10)
}

{
  const fitted = Model.fitDisplayLayout([
    display({ name: "eDP-1", width: 2880, height: 1800, scale: 2, x: 0 }),
    display({ name: "DP-4", width: 1920, height: 1080, scale: 1, x: 1440 })
  ], 320, 160, 10)
  const original = fitted.items.find(item => item.name === "DP-4")
  const moved = Model.moveDisplayInCanvas(
    fitted.items, "DP-4", original.x + 30, original.y + 20,
    fitted.scale, 10, 320, 160, 12
  )
  const dropped = moved.find(item => item.name === "DP-4")

  assert.ok(dropped.logicalX > original.logicalX)
  assert.ok(dropped.logicalY > original.logicalY)

  const leftOriginal = fitted.items.find(item => item.name === "eDP-1")
  const movedLeft = Model.moveDisplayInCanvas(
    fitted.items, "eDP-1", leftOriginal.x - 30, leftOriginal.y - 20,
    fitted.scale, 10, 320, 160, 12
  )
  const droppedLeft = movedLeft.find(item => item.name === "eDP-1")

  assert.ok(droppedLeft.logicalX < leftOriginal.logicalX)
  assert.ok(droppedLeft.logicalY < leftOriginal.logicalY)
}

{
  const displays = [
    display({ name: "DP-1", x: -1920, scale: 1.25, refreshRate: 59.95 }),
    display({ name: "eDP-1", width: 2880, height: 1800, x: 0, scale: 2 })
  ]
  const preview = [
    { name: "DP-1", logicalX: -1919.6, logicalY: 0 },
    { name: "eDP-1", logicalX: 0, logicalY: 80.4 }
  ]

  assert.deepEqual(Model.buildDisplayLayoutPayload(displays, preview), [
    { name: "DP-1", x: 0, y: 0, width: 1920, height: 1080, refreshRate: 59.95, scale: 1.25 },
    { name: "eDP-1", x: 1920, y: 80, width: 2880, height: 1800, refreshRate: 60, scale: 2 }
  ])
}

{
  assert.deepEqual(Model.advanceDisplayConfirmation(15), { remaining: 14, expired: false })
  assert.deepEqual(Model.advanceDisplayConfirmation(1), { remaining: 0, expired: true })
  assert.deepEqual(Model.advanceDisplayConfirmation(0), { remaining: 0, expired: true })
}

{
  assert.equal(Model.shouldAutoResetDisplayLayout({
    dirty: false,
    dragging: false,
    confirmationPending: false,
    applying: false
  }), true)
  assert.equal(Model.shouldAutoResetDisplayLayout({
    dirty: true,
    dragging: false,
    confirmationPending: false,
    applying: false
  }), false)
  assert.equal(Model.shouldAutoResetDisplayLayout({
    dirty: false,
    dragging: true,
    confirmationPending: false,
    applying: false
  }), false)
  assert.equal(Model.shouldAutoResetDisplayLayout({
    dirty: false,
    dragging: false,
    confirmationPending: true,
    applying: false
  }), false)
  assert.equal(Model.shouldAutoResetDisplayLayout({
    dirty: false,
    dragging: false,
    confirmationPending: false,
    applying: true
  }), false)
}

console.log("layout model tests passed")
