function clampBrightness(value) {
  var n = Number(value)
  if (!isFinite(n)) return 1
  return Math.max(1, Math.min(100, Math.round(n)))
}

function normalizeScale(scale) {
  var n = parseFloat(String(scale || ""))
  if (!isFinite(n)) return ""
  return String(Math.round(n * 100) / 100)
}

function gcd(a, b) {
  while (b) {
    var remainder = a % b
    a = b
    b = remainder
  }
  return a
}

function cleanScale(scale, width, height) {
  var requested = Number(scale)
  var modeWidth = Number(width)
  var modeHeight = Number(height)
  if (!isFinite(requested) || !isFinite(modeWidth) || !isFinite(modeHeight)
      || requested <= 0 || modeWidth <= 0 || modeHeight <= 0) return ""

  var divisor = gcd(Math.round(modeWidth * 120), Math.round(modeHeight * 120))
  var scaleUnits = Math.round(requested * 120)
  if (scaleUnits > divisor) scaleUnits = divisor
  while (divisor % scaleUnits !== 0) scaleUnits++
  return normalizeScale(scaleUnits / 120)
}

function matchingScaleIndex(scales, currentScale, width, height) {
  var current = Number(currentScale)
  if (!Array.isArray(scales) || !isFinite(current)) return -1

  var bestIndex = -1
  var bestDistance = Infinity
  var normalizedCurrent = normalizeScale(current)
  for (var i = 0; i < scales.length; i++) {
    if (cleanScale(scales[i], width, height) !== normalizedCurrent) continue

    var distance = Math.abs(Number(scales[i]) - current)
    if (distance < bestDistance) {
      bestIndex = i
      bestDistance = distance
    }
  }
  return bestIndex
}

function availableScales(scales, width, height) {
  if (!Array.isArray(scales) || Number(width) <= 0 || Number(height) <= 0) return scales || []

  var byEffectiveScale = {}
  for (var i = 0; i < scales.length; i++) {
    var requested = Number(scales[i])
    var effective = Number(cleanScale(requested, width, height))

    if (!isFinite(requested) || !isFinite(effective)) continue

    var key = normalizeScale(effective)
    var existing = byEffectiveScale[key]
    if (!existing || Math.abs(requested - effective) < existing.distance) {
      byEffectiveScale[key] = {
        value: String(scales[i]),
        index: i,
        distance: Math.abs(requested - effective)
      }
    }
  }

  return Object.keys(byEffectiveScale)
    .map(function(key) { return byEffectiveScale[key] })
    .sort(function(a, b) { return a.index - b.index })
    .map(function(candidate) { return candidate.value })
}

function parseDisplayMode(mode) {
  var match = String(mode || "").trim().match(/^(\d+)x(\d+)@([0-9]+(?:\.[0-9]+)?)(?:Hz)?$/i)
  if (!match) return null

  var width = Number(match[1])
  var height = Number(match[2])
  var refreshRate = Number(match[3])
  if (width <= 0 || height <= 0 || !isFinite(refreshRate) || refreshRate <= 0) return null

  return {
    width: width,
    height: height,
    refreshRate: refreshRate,
    value: width + "x" + height + "@" + String(refreshRate)
  }
}

function availableResolutions(modes, preferredResolution) {
  var seen = {}
  var resolutions = []
  for (var i = 0; Array.isArray(modes) && i < modes.length; i++) {
    var parsed = parseDisplayMode(modes[i])
    if (!parsed) continue
    var key = parsed.width + "x" + parsed.height
    if (seen[key]) continue
    seen[key] = true
    resolutions.push({
      value: parsed.value,
      width: parsed.width,
      height: parsed.height,
      refreshRate: parsed.refreshRate
    })
  }

  var preferred = String(preferredResolution || "").match(/^(\d+)x(\d+)/)
  var preferredKey = preferred ? Number(preferred[1]) + "x" + Number(preferred[2]) : ""
  if (!seen[preferredKey] && resolutions.length > 0)
    preferredKey = resolutions[0].width + "x" + resolutions[0].height

  resolutions.forEach(function(resolution) {
    resolution.recommended = resolution.width + "x" + resolution.height === preferredKey
    resolution.label = resolution.width + " × " + resolution.height
      + (resolution.recommended ? " (Recommended)" : "")
  })
  resolutions.sort(function(a, b) {
    return a.recommended === b.recommended ? 0 : (a.recommended ? -1 : 1)
  })
  return resolutions
}

function matchingResolutionValue(options, width, height) {
  var targetWidth = Math.round(finiteNumber(width, 0))
  var targetHeight = Math.round(finiteNumber(height, 0))
  for (var i = 0; Array.isArray(options) && i < options.length; i++) {
    if (Number(options[i].width) === targetWidth && Number(options[i].height) === targetHeight)
      return String(options[i].value || "")
  }
  return ""
}

function cleanTransform(transform) {
  var value = Number(transform)
  if (!isFinite(value) || Math.floor(value) !== value || value < 0 || value > 7) return 0
  return value
}

function stageDisplaySettings(displays, stagedSettings, targetName, overrides) {
  var next = {}
  var source = stagedSettings || {}
  Object.keys(source).forEach(function(name) {
    next[name] = Object.assign({}, source[name])
  })

  var target = null
  for (var i = 0; Array.isArray(displays) && i < displays.length; i++) {
    if (displays[i] && displays[i].name === targetName) {
      target = displays[i]
      break
    }
  }
  if (!target) return next

  var merged = Object.assign({}, next[targetName] || {}, overrides || {})
  var staged = {}
  var fields = ["width", "height", "refreshRate", "scale", "transform"]
  for (var j = 0; j < fields.length; j++) {
    var field = fields[j]
    if (merged[field] === undefined) continue
    var value = Number(merged[field])
    var actual = field === "transform"
      ? cleanTransform(target[field]) : Number(target[field])
    if (!isFinite(value)) continue
    if (field === "transform") {
      if (Math.floor(value) !== value || value < 0 || value > 7) continue
    } else if (value <= 0) continue
    if (field === "width" || field === "height") value = Math.round(value)
    var tolerance = field === "refreshRate" ? 0.01 : 0.0001
    if (!isFinite(actual) || Math.abs(value - actual) > tolerance) staged[field] = value
  }

  if (Object.keys(staged).length > 0) next[targetName] = staged
  else delete next[targetName]
  return next
}

function displaysWithSettings(displays, stagedSettings) {
  var settings = stagedSettings || {}
  return (Array.isArray(displays) ? displays : []).map(function(display) {
    if (!display) return display
    return Object.assign({}, display, settings[display.name] || {})
  })
}

function retainDisplaySettings(displays, stagedSettings) {
  var enabled = {}
  for (var i = 0; Array.isArray(displays) && i < displays.length; i++) {
    if (displays[i] && displays[i].enabled) enabled[displays[i].name] = true
  }

  var retained = {}
  var settings = stagedSettings || {}
  Object.keys(settings).forEach(function(name) {
    if (enabled[name]) retained[name] = Object.assign({}, settings[name])
  })
  return retained
}

function brightnessName(percent) {
  var p = Math.round(percent)
  if (p >= 95) return "Sun blast"
  if (p >= 80) return "Solar flare"
  if (p >= 65) return "Golden hour"
  if (p >= 45) return "Even day"
  if (p >= 30) return "Soft glow"
  if (p >= 20) return "Lamp light"
  if (p >= 10) return "Candlelit"
  return "Night owl"
}

function finiteNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function responsiveDisplayUtilization(displayCount) {
  var count = Math.max(1, Math.floor(finiteNumber(displayCount, 1)))
  // Scale by sqrt(count) so workspace area grows with every display. The
  // conservative coefficient also leaves enough centered travel to pull two
  // identical, fully overlapped monitors completely beside one another.
  return Math.max(0.1, Math.min(0.34, 0.46 / Math.sqrt(count)))
}

function cycleDisplayIndex(currentIndex, displayCount, direction) {
  var count = Math.max(0, Math.floor(finiteNumber(displayCount, 0)))
  if (count === 0) return -1

  var current = Math.floor(finiteNumber(currentIndex, -1))
  var step = finiteNumber(direction, 1) < 0 ? -1 : 1
  if (current < 0 || current >= count) return step < 0 ? count - 1 : 0
  return (current + step + count) % count
}

function displayLabel(display) {
  var name = String(display && display.name || "").trim()
  if (/^(eDP|LVDS|DSI)-/i.test(name)) return "Built-in Display"

  var make = String(display && display.make || "").trim()
  var model = String(display && display.model || "").trim()
  var description = String(display && display.description || "").trim()

  make = make
    .replace(/\s+(Electric Company|Electronics|Incorporated|Inc\.?|Corporation|Corp\.?|Co\.,?\s*Ltd\.?|Ltd\.?)$/i, "")
    .trim()

  if (make && model && model.toLowerCase().indexOf(make.toLowerCase()) === 0) return model
  if (make && model) return make + " " + model
  if (model) return model
  if (make) return make
  return description || name
}

function fitDisplayLayout(displays, canvasWidth, canvasHeight, padding, utilization) {
  var usable = []
  var inset = Math.max(0, finiteNumber(padding, 0))
  var width = Math.max(1, finiteNumber(canvasWidth, 1) - inset * 2)
  var height = Math.max(1, finiteNumber(canvasHeight, 1) - inset * 2)
  var fill = Math.max(0.1, Math.min(1, finiteNumber(utilization, 0.8)))

  for (var i = 0; Array.isArray(displays) && i < displays.length; i++) {
    var display = displays[i]
    var scale = Math.max(0.01, finiteNumber(display && display.scale, 1))
    var pixelWidth = finiteNumber(display && display.width, 0)
    var pixelHeight = finiteNumber(display && display.height, 0)
    if (!display || display.enabled === false || pixelWidth <= 0 || pixelHeight <= 0) continue
    var transform = cleanTransform(display.transform)
    var rotated = transform % 2 === 1

    usable.push({
      name: String(display.name || ""),
      label: displayLabel(display),
      focused: display.focused === true,
      logicalX: finiteNumber(display.x, 0),
      logicalY: finiteNumber(display.y, 0),
      logicalWidth: (rotated ? pixelHeight : pixelWidth) / scale,
      logicalHeight: (rotated ? pixelWidth : pixelHeight) / scale
    })
  }

  if (usable.length === 0) return { items: [], scale: 1, padding: inset }

  var minX = usable[0].logicalX
  var minY = usable[0].logicalY
  var maxX = usable[0].logicalX + usable[0].logicalWidth
  var maxY = usable[0].logicalY + usable[0].logicalHeight
  for (var j = 1; j < usable.length; j++) {
    minX = Math.min(minX, usable[j].logicalX)
    minY = Math.min(minY, usable[j].logicalY)
    maxX = Math.max(maxX, usable[j].logicalX + usable[j].logicalWidth)
    maxY = Math.max(maxY, usable[j].logicalY + usable[j].logicalHeight)
  }

  // Leave working room around the detected arrangement. If the initial
  // monitors fill the canvas exactly, an edge monitor cannot be dropped any
  // farther outward because moveDisplayInCanvas has no valid space there.
  var factor = Math.min(width / Math.max(1, maxX - minX), height / Math.max(1, maxY - minY)) * fill
  var offsetX = (width / factor - (maxX - minX)) / 2
  var offsetY = (height / factor - (maxY - minY)) / 2
  var items = usable.map(function(display) {
    var logicalX = display.logicalX - minX + offsetX
    var logicalY = display.logicalY - minY + offsetY
    return {
      name: display.name,
      label: display.label,
      focused: display.focused,
      logicalX: logicalX,
      logicalY: logicalY,
      logicalWidth: display.logicalWidth,
      logicalHeight: display.logicalHeight,
      x: inset + logicalX * factor,
      y: inset + logicalY * factor,
      width: display.logicalWidth * factor,
      height: display.logicalHeight * factor
    }
  })

  return { items: items, scale: factor, padding: inset }
}

function normalizeDisplayLayout(items) {
  if (!Array.isArray(items) || items.length === 0) return []

  var rounded = items.map(function(item) {
    return {
      name: String(item && item.name || ""),
      x: Math.round(finiteNumber(item && item.logicalX, 0)),
      y: Math.round(finiteNumber(item && item.logicalY, 0))
    }
  })
  var minX = rounded.reduce(function(value, item) { return Math.min(value, item.x) }, rounded[0].x)
  var minY = rounded.reduce(function(value, item) { return Math.min(value, item.y) }, rounded[0].y)

  return rounded.map(function(item) {
    return { name: item.name, x: item.x - minX, y: item.y - minY }
  })
}

function refitDisplayLayout(displays, previewItems, canvasWidth, canvasHeight, padding, utilization) {
  var positions = normalizeDisplayLayout(previewItems)
  if (positions.length === 0)
    return fitDisplayLayout(displays, canvasWidth, canvasHeight, padding, utilization)

  var byName = {}
  for (var i = 0; i < positions.length; i++) byName[positions[i].name] = positions[i]

  var staged = (Array.isArray(displays) ? displays : []).map(function(display) {
    var position = display && byName[display.name]
    if (!position) return display
    return Object.assign({}, display, { x: position.x, y: position.y })
  })

  return fitDisplayLayout(staged, canvasWidth, canvasHeight, padding, utilization)
}

function nearestSnap(value, candidates, threshold) {
  var best = value
  var distance = Math.max(0, finiteNumber(threshold, 0)) + 0.0001
  for (var i = 0; i < candidates.length; i++) {
    var candidateDistance = Math.abs(value - candidates[i])
    if (candidateDistance < distance) {
      best = candidates[i]
      distance = candidateDistance
    }
  }
  return best
}

function snapDisplayPosition(moving, others, threshold) {
  var xCandidates = []
  var yCandidates = []
  var movingWidth = finiteNumber(moving && moving.logicalWidth, 0)
  var movingHeight = finiteNumber(moving && moving.logicalHeight, 0)

  for (var i = 0; Array.isArray(others) && i < others.length; i++) {
    var other = others[i]
    if (!other || other.name === moving.name) continue
    var ox = finiteNumber(other.logicalX, 0)
    var oy = finiteNumber(other.logicalY, 0)
    var ow = finiteNumber(other.logicalWidth, 0)
    var oh = finiteNumber(other.logicalHeight, 0)
    xCandidates.push(ox - movingWidth, ox, ox + ow - movingWidth, ox + ow)
    yCandidates.push(oy - movingHeight, oy, oy + oh - movingHeight, oy + oh)
  }

  return {
    x: nearestSnap(finiteNumber(moving && moving.logicalX, 0), xCandidates, threshold),
    y: nearestSnap(finiteNumber(moving && moving.logicalY, 0), yCandidates, threshold)
  }
}

function moveDisplayInCanvas(items, name, canvasX, canvasY, scale, padding, canvasWidth, canvasHeight, snapPixels) {
  if (!Array.isArray(items)) return []
  var factor = Math.max(0.0001, finiteNumber(scale, 1))
  var inset = Math.max(0, finiteNumber(padding, 0))
  var moving = items.find(function(item) { return item && item.name === name })
  if (!moving) return items.slice()

  var maxLogicalX = Math.max(0, (finiteNumber(canvasWidth, 1) - inset * 2) / factor - moving.logicalWidth)
  var maxLogicalY = Math.max(0, (finiteNumber(canvasHeight, 1) - inset * 2) / factor - moving.logicalHeight)
  var candidate = Object.assign({}, moving, {
    logicalX: Math.max(0, Math.min(maxLogicalX, (finiteNumber(canvasX, inset) - inset) / factor)),
    logicalY: Math.max(0, Math.min(maxLogicalY, (finiteNumber(canvasY, inset) - inset) / factor))
  })
  var snapped = snapDisplayPosition(candidate, items, finiteNumber(snapPixels, 0) / factor)
  candidate.logicalX = Math.max(0, Math.min(maxLogicalX, snapped.x))
  candidate.logicalY = Math.max(0, Math.min(maxLogicalY, snapped.y))
  candidate.x = inset + candidate.logicalX * factor
  candidate.y = inset + candidate.logicalY * factor

  return items.map(function(item) {
    return item && item.name === name ? candidate : Object.assign({}, item)
  })
}

function buildDisplayLayoutPayload(displays, previewItems, stagedSettings) {
  var normalized = normalizeDisplayLayout(previewItems)
  var byName = {}
  var settings = stagedSettings || {}
  for (var i = 0; Array.isArray(displays) && i < displays.length; i++) {
    if (displays[i] && displays[i].enabled !== false) byName[displays[i].name] = displays[i]
  }

  return normalized.map(function(position) {
    var display = byName[position.name] || {}
    var staged = settings[position.name] || {}
    return {
      name: position.name,
      x: position.x,
      y: position.y,
      width: Math.round(finiteNumber(staged.width, finiteNumber(display.width, 0))),
      height: Math.round(finiteNumber(staged.height, finiteNumber(display.height, 0))),
      refreshRate: finiteNumber(staged.refreshRate, finiteNumber(display.refreshRate, 60)),
      scale: finiteNumber(staged.scale, finiteNumber(display.scale, 1)),
      transform: cleanTransform(staged.transform !== undefined
                                ? staged.transform : display.transform)
    }
  }).filter(function(display) {
    return display.name !== "" && display.width > 0 && display.height > 0 && display.scale > 0
  })
}

function buildMonitorSettingPayload(displays, targetName, overrides) {
  var enabled = (Array.isArray(displays) ? displays : []).filter(function(display) {
    return display && display.enabled !== false
  })
  if (enabled.length === 0) return []

  var minX = enabled.reduce(function(value, display) {
    return Math.min(value, Math.round(finiteNumber(display.x, 0)))
  }, Math.round(finiteNumber(enabled[0].x, 0)))
  var minY = enabled.reduce(function(value, display) {
    return Math.min(value, Math.round(finiteNumber(display.y, 0)))
  }, Math.round(finiteNumber(enabled[0].y, 0)))
  var changes = overrides || {}

  return enabled.map(function(display) {
    var targeted = String(display.name || "") === String(targetName || "")
    return {
      name: String(display.name || ""),
      x: Math.round(finiteNumber(display.x, 0)) - minX,
      y: Math.round(finiteNumber(display.y, 0)) - minY,
      width: Math.round(finiteNumber(targeted ? changes.width : undefined,
                                     finiteNumber(display.width, 0))),
      height: Math.round(finiteNumber(targeted ? changes.height : undefined,
                                      finiteNumber(display.height, 0))),
      refreshRate: finiteNumber(targeted ? changes.refreshRate : undefined,
                                finiteNumber(display.refreshRate, 60)),
      scale: finiteNumber(targeted ? changes.scale : undefined,
                          finiteNumber(display.scale, 1)),
      transform: cleanTransform(targeted && changes.transform !== undefined
                                ? changes.transform : display.transform)
    }
  }).filter(function(display) {
    return display.name !== "" && display.width > 0 && display.height > 0 && display.scale > 0
  })
}

function prepareDisplaySettingPreview(displays, stagedSettings, targetName, overrides) {
  var nextSettings = stageDisplaySettings(displays, stagedSettings, targetName, overrides)
  var targetSettings = nextSettings[targetName]
  if (!targetSettings || Object.keys(targetSettings).length === 0) {
    return {
      changed: false,
      stagedSettings: nextSettings,
      previous: [],
      proposed: []
    }
  }

  return {
    changed: true,
    stagedSettings: nextSettings,
    previous: buildMonitorSettingPayload(displays, "", {}),
    proposed: buildMonitorSettingPayload(displays, targetName, targetSettings)
  }
}

function advanceDisplayConfirmation(seconds) {
  var remaining = Math.max(0, Math.floor(finiteNumber(seconds, 0)) - 1)
  return { remaining: remaining, expired: remaining === 0 }
}

function parsePendingDisplayTransaction(raw) {
  var value
  try {
    value = raw ? JSON.parse(String(raw)) : null
  } catch (e) {
    return null
  }

  if (!value || typeof value !== "object") return null
  var id = String(value.id || "")
  var scope = String(value.scope || "")
  var remaining = Math.floor(Number(value.remainingSeconds))
  if (!/^[A-Za-z0-9._-]+$/.test(id)
      || (scope !== "layout" && scope !== "settings")
      || !isFinite(remaining) || remaining < 1) return null

  return { id: id, scope: scope, remainingSeconds: remaining }
}

function workspaceNumber(value, maximum) {
  var text = String(value === undefined || value === null ? "" : value).trim()
  if (!/^\d+$/.test(text)) return 0
  var number = Number(text)
  return number >= 1 && number <= maximum ? Math.floor(number) : 0
}

function workspaceAssignments(displays, workspaces, rules, maximum) {
  var limit = Math.max(1, Math.floor(finiteNumber(maximum, 10)))
  var enabledMonitors = {}
  for (var i = 0; Array.isArray(displays) && i < displays.length; i++) {
    var display = displays[i]
    if (display && display.enabled !== false && display.name)
      enabledMonitors[String(display.name)] = true
  }

  var assignments = {}
  for (var j = 0; Array.isArray(workspaces) && j < workspaces.length; j++) {
    var workspace = workspaces[j] || {}
    var number = workspaceNumber(workspace.name !== undefined ? workspace.name : workspace.id, limit)
    var monitor = String(workspace.monitor || "")
    if (number > 0 && enabledMonitors[monitor]) assignments[String(number)] = monitor
  }

  for (var k = 0; Array.isArray(rules) && k < rules.length; k++) {
    var rule = rules[k] || {}
    var ruleNumber = workspaceNumber(
      rule.workspaceString !== undefined ? rule.workspaceString : rule.workspace, limit)
    var ruleMonitor = String(rule.monitor || "")
    if (ruleNumber > 0 && enabledMonitors[ruleMonitor])
      assignments[String(ruleNumber)] = ruleMonitor
  }
  return assignments
}

function workspacesForMonitor(assignments, monitorName) {
  var target = String(monitorName || "")
  return Object.keys(assignments || {}).filter(function(number) {
    return String(assignments[number]) === target
  }).map(Number).filter(function(number) {
    return isFinite(number) && number > 0
  }).sort(function(a, b) { return a - b })
}

function toggleWorkspaceAssignment(assignments, workspace, monitorName) {
  var number = workspaceNumber(workspace, 10)
  var monitor = String(monitorName || "")
  var next = {}
  Object.keys(assignments || {}).forEach(function(key) {
    next[key] = String(assignments[key])
  })
  if (number === 0 || monitor === "") return next

  var key = String(number)
  if (next[key] === monitor) delete next[key]
  else next[key] = monitor
  return next
}

function workspaceAssignmentsEqual(left, right) {
  var leftKeys = Object.keys(left || {}).sort()
  var rightKeys = Object.keys(right || {}).sort()
  if (leftKeys.length !== rightKeys.length) return false
  for (var i = 0; i < leftKeys.length; i++) {
    var key = leftKeys[i]
    if (key !== rightKeys[i] || String(left[key]) !== String(right[key])) return false
  }
  return true
}

function parseDisplays(raw) {
  var displays = []
  try {
    displays = raw ? JSON.parse(String(raw)) : []
  } catch (e) {
    displays = []
  }
  if (!Array.isArray(displays)) displays = []

  var count = 0
  for (var i = 0; i < displays.length; i++) {
    if (displays[i] && displays[i].enabled) count++
  }

  return {
    displays: displays,
    enabledDisplayCount: count
  }
}

function shouldAutoResetDisplayLayout(state) {
  state = state || {}
  return !state.dirty && !state.dragging && !state.confirmationPending && !state.applying
}

function nextExpandedSection(current, requested) {
  return String(current || "") === String(requested || "")
    ? "" : String(requested || "")
}

if (typeof module !== "undefined") {
  module.exports = {
    clampBrightness: clampBrightness,
    normalizeScale: normalizeScale,
    cleanScale: cleanScale,
    matchingScaleIndex: matchingScaleIndex,
    availableScales: availableScales,
    parseDisplayMode: parseDisplayMode,
    availableResolutions: availableResolutions,
    matchingResolutionValue: matchingResolutionValue,
    cleanTransform: cleanTransform,
    stageDisplaySettings: stageDisplaySettings,
    displaysWithSettings: displaysWithSettings,
    retainDisplaySettings: retainDisplaySettings,
    brightnessName: brightnessName,
    responsiveDisplayUtilization: responsiveDisplayUtilization,
    cycleDisplayIndex: cycleDisplayIndex,
    displayLabel: displayLabel,
    fitDisplayLayout: fitDisplayLayout,
    normalizeDisplayLayout: normalizeDisplayLayout,
    refitDisplayLayout: refitDisplayLayout,
    snapDisplayPosition: snapDisplayPosition,
    moveDisplayInCanvas: moveDisplayInCanvas,
    buildDisplayLayoutPayload: buildDisplayLayoutPayload,
    buildMonitorSettingPayload: buildMonitorSettingPayload,
    prepareDisplaySettingPreview: prepareDisplaySettingPreview,
    advanceDisplayConfirmation: advanceDisplayConfirmation,
    parsePendingDisplayTransaction: parsePendingDisplayTransaction,
    workspaceAssignments: workspaceAssignments,
    workspacesForMonitor: workspacesForMonitor,
    toggleWorkspaceAssignment: toggleWorkspaceAssignment,
    workspaceAssignmentsEqual: workspaceAssignmentsEqual,
    parseDisplays: parseDisplays,
    nextExpandedSection: nextExpandedSection,
    shouldAutoResetDisplayLayout: shouldAutoResetDisplayLayout
  }
}
