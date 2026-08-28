// Staged topology operations: enable/disable, validation, and payload
// construction for full-topology transactions. Pure functions, node-testable.

function cleanTransform(transform) {
  var value = Number(transform)
  if (!isFinite(value) || Math.floor(value) !== value || value < 0 || value > 7) return 0
  return value
}

function finiteNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function displayByName(displays, name) {
  for (var i = 0; Array.isArray(displays) && i < displays.length; i++) {
    if (displays[i] && displays[i].name === name) return displays[i]
  }
  return null
}

function logicalSize(width, height, scale, transform) {
  var divisor = Math.max(0.01, finiteNumber(scale, 1))
  var rotated = cleanTransform(transform) % 2 === 1
  var pixelWidth = finiteNumber(width, 0)
  var pixelHeight = finiteNumber(height, 0)
  return {
    width: (rotated ? pixelHeight : pixelWidth) / divisor,
    height: (rotated ? pixelWidth : pixelHeight) / divisor
  }
}

// Build a full-topology payload from displays with a staged overlay. Enabled
// records carry the complete spec; disabled records carry only their identity
// so their last usable settings stay attached to the display record.
function buildTopologyPayload(displays, stagedSettings) {
  var settings = stagedSettings || {}
  var merged = (Array.isArray(displays) ? displays : []).map(function(display) {
    if (!display) return display
    return Object.assign({}, display, settings[display.name] || {})
  })

  var minX = 0
  var minY = 0
  var first = true
  for (var i = 0; i < merged.length; i++) {
    var entry = merged[i]
    if (!entry || entry.enabled === false) continue
    var x = Math.round(finiteNumber(entry.x, 0))
    var y = Math.round(finiteNumber(entry.y, 0))
    if (first || x < minX) minX = x
    if (first || y < minY) minY = y
    first = false
  }

  return merged.filter(function(entry) {
    return entry && entry.name
  }).map(function(entry) {
    if (entry.enabled === false) {
      // Keep the last usable mode and geometry with a disabled record. The
      // compositor may omit those fields while an output is disabled, but
      // retaining them when available lets a later enable restore the same
      // topology instead of producing an incomplete proposal.
      var disabled = { name: String(entry.name), enabled: false }
      var disabledFields = ["x", "y", "width", "height", "refreshRate", "scale"]
      for (var d = 0; d < disabledFields.length; d++) {
        var field = disabledFields[d]
        var value = Number(entry[field])
        if (!isFinite(value)) continue
        if ((field === "width" || field === "height") && value <= 0) continue
        if (field === "refreshRate" && value <= 0) continue
        if (field === "scale" && value <= 0) continue
        disabled[field] = field === "width" || field === "height"
          ? Math.round(value) : value
      }
      if (entry.transform !== undefined)
        disabled.transform = cleanTransform(entry.transform)
      return disabled
    }
    var record = {
      name: String(entry.name),
      x: Math.round(finiteNumber(entry.x, 0)) - minX,
      y: Math.round(finiteNumber(entry.y, 0)) - minY,
      width: Math.round(finiteNumber(entry.width, 0)),
      height: Math.round(finiteNumber(entry.height, 0)),
      refreshRate: finiteNumber(entry.refreshRate, 60),
      scale: finiteNumber(entry.scale, 1),
      transform: cleanTransform(entry.transform)
    }
    var mirror = String(entry.mirrorOf || "")
    if (mirror && mirror !== "none") record.mirrorOf = mirror
    return record
  }).filter(function(record) {
    return record.enabled === false
      || (record.width > 0 && record.height > 0 && record.scale > 0)
  })
}

// A topology is applicable when it keeps at least one usable display, every
// enabled display has a positive mode, and enabled logical areas never overlap.
function validateTopologyPayload(payload) {
  if (!Array.isArray(payload) || payload.length === 0)
    return { valid: false, reason: "no displays in topology" }

  var enabled = payload.filter(function(record) { return record.enabled !== false })
  if (enabled.length === 0)
    return { valid: false, reason: "at least one display must stay active" }

  var seen = {}
  for (var i = 0; i < payload.length; i++) {
    var name = String(payload[i].name || "")
    if (seen[name]) return { valid: false, reason: "duplicate display " + name }
    seen[name] = true
  }

  for (var j = 0; j < enabled.length; j++) {
    var record = enabled[j]
    if (!(record.width > 0 && record.height > 0 && record.scale > 0))
      return { valid: false, reason: name + " has no usable mode" }
  }

  for (var a = 0; a < enabled.length; a++) {
    for (var b = a + 1; b < enabled.length; b++) {
      var left = enabled[a]
      var right = enabled[b]
      var leftSize = logicalSize(left.width, left.height, left.scale, left.transform)
      var rightSize = logicalSize(right.width, right.height, right.scale, right.transform)
      var overlaps = left.x < right.x + rightSize.width
        && right.x < left.x + leftSize.width
        && left.y < right.y + rightSize.height
        && right.y < left.y + leftSize.height
      var mirroredTogether = left.mirrorOf === right.name
        || right.mirrorOf === left.name
        || (left.mirrorOf && left.mirrorOf === right.mirrorOf)
      if (overlaps && !mirroredTogether)
        return { valid: false, reason: left.name + " and " + right.name + " would overlap" }
    }
  }

  return { valid: true, reason: "" }
}

function withStagedSetting(stagedSettings, name, changes) {
  var next = {}
  var source = stagedSettings || {}
  Object.keys(source).forEach(function(key) {
    next[key] = Object.assign({}, source[key])
  })
  next[name] = Object.assign({}, next[name] || {}, changes || {})
  return next
}

function placeEnabledDisplayBeside(displays, stagedSettings, name) {
  var settings = stagedSettings || {}
  var maxRight = null
  var placementTop = 0

  for (var i = 0; Array.isArray(displays) && i < displays.length; i++) {
    var display = displays[i]
    if (!display || display.name === name) continue
    var entry = Object.assign({}, display, settings[display.name] || {})
    if (entry.enabled === false) continue
    var size = logicalSize(entry.width, entry.height, entry.scale, entry.transform)
    var right = finiteNumber(entry.x, 0) + size.width
    var top = finiteNumber(entry.y, 0)
    if (maxRight === null || right > maxRight) {
      maxRight = right
      placementTop = top
    }
  }

  if (maxRight === null) return stagedSettings
  return withStagedSetting(stagedSettings, name, {
    x: Math.round(maxRight),
    y: Math.round(placementTop)
  })
}

// Stage an enable/disable change for one display and build the preview
// transaction payloads. Disabling keeps the display's last known settings in
// its record; re-enabling restores them unchanged.
function prepareTogglePreview(displays, stagedSettings, name) {
  var target = displayByName(displays, name)
  if (!target) return { changed: false }

  var enable = target.enabled === false
  var merged = Object.assign({}, target, (stagedSettings || {})[name] || {})
  if ((merged.enabled !== false) === enable) return { changed: false }

  var nextSettings = withStagedSetting(stagedSettings, name, { enabled: enable })
  var proposed = buildTopologyPayload(displays, nextSettings)
  var previous = buildTopologyPayload(displays, stagedSettings)
  var validation = validateTopologyPayload(proposed)

  // Disabled outputs are commonly enumerated at 0,0, which can collide with
  // the active layout even when their last usable geometry is otherwise
  // intact. Preserve a remembered position when it is valid; only when the
  // enable proposal overlaps, place the returning output to the right of the
  // active desktop and validate again.
  if (enable && !validation.valid && /would overlap/.test(validation.reason)) {
    nextSettings = placeEnabledDisplayBeside(displays, nextSettings, name)
    proposed = buildTopologyPayload(displays, nextSettings)
    validation = validateTopologyPayload(proposed)
  }

  return {
    changed: true,
    valid: validation.valid,
    reason: validation.reason,
    stagedSettings: nextSettings,
    proposed: proposed,
    previous: previous
  }
}

// Overlay normalized arrangement positions (from the layout editor) onto a
// full topology payload without disturbing disabled records.
function withPositions(payload, positions) {
  var byName = {}
  for (var i = 0; Array.isArray(positions) && i < positions.length; i++) {
    if (positions[i] && positions[i].name) byName[positions[i].name] = positions[i]
  }
  return (Array.isArray(payload) ? payload : []).map(function(record) {
    var position = record && byName[record.name]
    if (!position || record.enabled === false) return record
    return Object.assign({}, record, {
      x: Math.round(finiteNumber(position.x, record.x)),
      y: Math.round(finiteNumber(position.y, record.y))
    })
  })
}

function validAnchor(payload, requestedName) {
  var enabled = (Array.isArray(payload) ? payload : []).filter(function(record) {
    return record && record.enabled !== false && record.name
  })
  for (var i = 0; i < enabled.length; i++) {
    if (enabled[i].name === requestedName) return requestedName
  }
  return enabled.length ? String(enabled[0].name) : ""
}

function relativeToAnchor(payload, requestedName) {
  var anchorName = validAnchor(payload, requestedName)
  var anchor = displayByName(payload, anchorName)
  if (!anchor) return (Array.isArray(payload) ? payload : []).slice()
  var anchorX = Math.round(finiteNumber(anchor.x, 0))
  var anchorY = Math.round(finiteNumber(anchor.y, 0))
  return payload.map(function(record) {
    if (!record || record.enabled === false) return record
    return Object.assign({}, record, {
      x: Math.round(finiteNumber(record.x, 0)) - anchorX,
      y: Math.round(finiteNumber(record.y, 0)) - anchorY
    })
  })
}

function isInternalDisplay(name) {
  return /^(eDP|LVDS|DSI)-/.test(String(name || ""))
}

function presetAvailable(displays, preset) {
  var records = (Array.isArray(displays) ? displays : []).filter(function(display) {
    return display && display.name && Number(display.width) > 0 && Number(display.height) > 0
  })
  var hasInternal = records.some(function(display) { return isInternalDisplay(display.name) })
  var hasExternal = records.some(function(display) { return !isInternalDisplay(display.name) })
  if (preset === "internal") return hasInternal
  if (preset === "external") return hasExternal
  if (preset === "extend") return hasInternal && hasExternal
  return false
}

function currentPreset(displays) {
  var enabled = (Array.isArray(displays) ? displays : []).filter(function(display) {
    return display && display.enabled !== false && display.name
  })
  var hasInternal = enabled.some(function(display) { return isInternalDisplay(display.name) })
  var hasExternal = enabled.some(function(display) { return !isInternalDisplay(display.name) })
  if (hasInternal && hasExternal) return "extend"
  if (hasInternal) return "internal"
  if (hasExternal) return "external"
  return ""
}

function presetMatches(payload, preset) {
  var enabled = (Array.isArray(payload) ? payload : []).filter(function(record) {
    return record && record.enabled !== false
  })
  if (!enabled.length) return false
  if (enabled.some(function(record) {
    return record.mirrorOf && record.mirrorOf !== "none"
  })) return false
  if (preset === "internal")
    return enabled.every(function(record) { return isInternalDisplay(record.name) })
  if (preset === "external")
    return enabled.every(function(record) { return !isInternalDisplay(record.name) })
  if (preset === "extend")
    return enabled.some(function(record) { return isInternalDisplay(record.name) })
      && enabled.some(function(record) { return !isInternalDisplay(record.name) })
  return false
}

function compatibleVariant(displays, preset, variant) {
  if (!variant || !Array.isArray(variant.monitors)) return false
  var currentNames = (Array.isArray(displays) ? displays : [])
    .filter(function(display) { return display && display.name })
    .map(function(display) { return String(display.name) }).sort()
  var savedNames = variant.monitors
    .filter(function(record) { return record && record.name })
    .map(function(record) { return String(record.name) }).sort()
  var byName = {}
  var liveDisplays = Array.isArray(displays) ? displays : []
  liveDisplays.forEach(function(display) {
    if (display && display.name) byName[display.name] = display
  })
  var modesAvailable = variant.monitors.every(function(record) {
    if (!record || record.enabled === false) return true
    var live = byName[record.name]
    if (!live || !Array.isArray(live.availableModes) || live.availableModes.length === 0)
      return true
    return live.availableModes.some(function(mode) {
      var match = String(mode).match(/^(\d+)x(\d+)@(\d+(?:\.\d+)?)Hz?$/)
      return match && Number(match[1]) === Number(record.width)
        && Number(match[2]) === Number(record.height)
        && Math.abs(Number(match[3]) - Number(record.refreshRate)) <= 0.05
    })
  })
  return JSON.stringify(currentNames) === JSON.stringify(savedNames)
    && presetMatches(variant.monitors, preset)
    && modesAvailable
    && validateTopologyPayload(variant.monitors).valid
}

function arrangeEnabledHorizontally(payload) {
  var cursor = 0
  return payload.map(function(record) {
    if (!record || record.enabled === false) return record
    var placed = Object.assign({}, record, { x: Math.round(cursor), y: 0 })
    cursor += logicalSize(record.width, record.height, record.scale, record.transform).width
    return placed
  })
}

function preparePresetPreview(displays, stagedSettings, preset, savedVariant) {
  if (!presetAvailable(displays, preset))
    return { changed: false, valid: false, reason: "required displays are unavailable" }

  var previous = buildTopologyPayload(displays, stagedSettings)
  if (compatibleVariant(displays, preset, savedVariant)) {
    return {
      changed: true,
      valid: true,
      reason: "",
      restored: true,
      anchor: validAnchor(savedVariant.monitors, savedVariant.anchor),
      workspaces: savedVariant.workspaces || {},
      proposed: savedVariant.monitors.map(function(record) {
        return Object.assign({}, record)
      }),
      previous: previous
    }
  }

  var nextSettings = {}
  var sourceDisplays = Array.isArray(displays) ? displays : []
  sourceDisplays.forEach(function(display) {
    if (!display || !display.name) return
    var internal = isInternalDisplay(display.name)
    var enabled = preset === "extend"
      || (preset === "internal" && internal)
      || (preset === "external" && !internal)
    nextSettings[display.name] = Object.assign({}, (stagedSettings || {})[display.name] || {}, {
      enabled: enabled,
      mirrorOf: ""
    })
  })
  var proposed = arrangeEnabledHorizontally(buildTopologyPayload(displays, nextSettings))
  var validation = validateTopologyPayload(proposed)
  return {
    changed: true,
    valid: validation.valid,
    reason: validation.reason,
    restored: false,
    anchor: validAnchor(proposed, ""),
    proposed: proposed,
    previous: previous
  }
}

function workspacePayloadForPreset(assignments, payload, requestedAnchor) {
  var anchor = validAnchor(payload, requestedAnchor)
  var enabled = {}
  var records = Array.isArray(payload) ? payload : []
  records.forEach(function(record) {
    if (record && record.enabled !== false && record.name) enabled[record.name] = true
  })
  var result = {}
  Object.keys(assignments || {}).forEach(function(workspace) {
    var owner = String(assignments[workspace] || "")
    if (enabled[owner]) result[workspace] = owner
    else if (anchor) result[workspace] = anchor
  })
  return result
}

function parsedAdvertisedModes(display) {
  return (display && Array.isArray(display.availableModes) ? display.availableModes : [])
    .map(function(mode) {
      var match = String(mode).match(/^(\d+)x(\d+)@(\d+(?:\.\d+)?)Hz?$/)
      return match ? {
        width: Number(match[1]), height: Number(match[2]), refreshRate: Number(match[3])
      } : null
    }).filter(function(mode) { return mode !== null })
}

function commonAdvertisedModes(displays) {
  var group = (Array.isArray(displays) ? displays : []).filter(function(display) {
    return display && display.name
  })
  if (group.length < 2) return []
  var candidates = parsedAdvertisedModes(group[0])
  var seen = {}
  return candidates.filter(function(candidate) {
    var key = candidate.width + "x" + candidate.height + "@" + candidate.refreshRate.toFixed(2)
    if (seen[key]) return false
    seen[key] = true
    return group.every(function(display) {
      return parsedAdvertisedModes(display).some(function(mode) {
        return mode.width === candidate.width && mode.height === candidate.height
          && Math.abs(mode.refreshRate - candidate.refreshRate) <= 0.05
      })
    })
  }).sort(function(left, right) {
    return right.width * right.height - left.width * left.height
      || right.refreshRate - left.refreshRate
  })
}

function displayAspectRatio(display) {
  var preferred = String(display && display.recommendedResolution || "")
    .match(/^(\d+)x(\d+)$/)
  if (preferred && Number(preferred[2]) > 0)
    return Number(preferred[1]) / Number(preferred[2])

  var physicalWidth = Number(display && display.physicalWidth)
  var physicalHeight = Number(display && display.physicalHeight)
  if (physicalWidth > 0 && physicalHeight > 0) return physicalWidth / physicalHeight

  var modes = parsedAdvertisedModes(display)
  if (modes.length > 0 && modes[0].height > 0) return modes[0].width / modes[0].height
  var width = Number(display && display.width)
  var height = Number(display && display.height)
  return width > 0 && height > 0 ? width / height : 0
}

function compatiblePhysicalAspects(displays) {
  var ratios = (Array.isArray(displays) ? displays : [])
    .map(displayAspectRatio).filter(function(ratio) { return ratio > 0 })
  if (ratios.length < 2) return true
  return ratios.every(function(ratio) {
    return Math.abs(ratio - ratios[0]) / ratios[0] <= 0.01
  })
}

function prepareDuplicatePreview(displays, stagedSettings, requestedSource) {
  var group = (Array.isArray(displays) ? displays : []).filter(function(display) {
    return display && display.name
  })
  var previous = buildTopologyPayload(displays, stagedSettings)
  if (group.length < 2) {
    return {
      changed: false,
      valid: false,
      reason: "Duplicate needs at least two displays",
      summary: "Duplicate unavailable: needs at least two displays."
    }
  }

  var source = group[0]
  for (var i = 0; i < group.length; i++) {
    if (group[i].name === requestedSource) source = group[i]
  }

  var orderedGroup = [source].concat(group.filter(function(display) {
    return display.name !== source.name
  }))

  var modes = commonAdvertisedModes(group)
  var aspectMatch = compatiblePhysicalAspects(group)
  var proposed
  var summary = ""

  var hasSixteenNine = group.some(function(d) {
    var ratio = displayAspectRatio(d)
    return ratio > 0 && Math.abs(ratio - 16 / 9) <= 0.05
  })

  if (modes.length > 0) {
    var mode = modes[0]
    if (!aspectMatch && hasSixteenNine) {
      var sixteenNineMode = modes.find(function(m) {
        return Math.abs(m.width / m.height - 16 / 9) <= 0.05
      })
      if (sixteenNineMode) mode = sixteenNineMode
    }
    var compromises = group.filter(function(display) {
      return Number(display.width) !== mode.width || Number(display.height) !== mode.height
        || Math.abs(Number(display.refreshRate) - mode.refreshRate) > 0.05
    }).length
    proposed = orderedGroup.map(function(display) {
      var record = {
        name: String(display.name), x: 0, y: 0,
        width: mode.width, height: mode.height, refreshRate: mode.refreshRate,
        scale: 1, transform: 0
      }
      if (display.name !== source.name) record.mirrorOf = String(source.name)
      return record
    })
    summary = "Duplicate uses " + (aspectMatch ? "" : "16:9 presentation mode ")
      + mode.width + " × " + mode.height + " @ "
      + Math.round(mode.refreshRate * 100) / 100 + " Hz"
      + (aspectMatch ? "" : " (letterboxed on 16:10 display)")
      + (compromises ? "; " + compromises + " display mode"
        + (compromises === 1 ? " changes." : "s change.") : ".")
  } else if (!aspectMatch && hasSixteenNine) {
    // When no common advertised mode exists and displays differ in aspect ratio,
    // default to standard 16:9 presentation mode (1920x1080@60) to eliminate stretching
    // and letterbox cleanly on 16:10 laptop screens for presentations.
    proposed = orderedGroup.map(function(display) {
      var prevRecord = null
      for (var p = 0; p < previous.length; p++) {
        if (previous[p].name === display.name) {
          prevRecord = previous[p]
          break
        }
      }
      var modeScale = prevRecord && prevRecord.scale > 0 ? prevRecord.scale : finiteNumber(display.scale, 1)
      var modeTransform = prevRecord && prevRecord.transform !== undefined ? prevRecord.transform : cleanTransform(display.transform)

      var record = {
        name: String(display.name), x: 0, y: 0,
        width: 1920, height: 1080, refreshRate: 60,
        scale: modeScale, transform: modeTransform
      }
      if (display.name !== source.name) record.mirrorOf = String(source.name)
      return record
    })
    summary = "Duplicate uses 16:9 presentation mode (1920 × 1080 @ 60 Hz) with letterboxing on 16:10 display."
  } else {
    proposed = orderedGroup.map(function(display) {
      var prevRecord = null
      for (var p = 0; p < previous.length; p++) {
        if (previous[p].name === display.name) {
          prevRecord = previous[p]
          break
        }
      }
      var dispModes = parsedAdvertisedModes(display)
      var modeWidth = prevRecord && prevRecord.width > 0 ? prevRecord.width : (dispModes.length > 0 ? dispModes[0].width : Math.round(finiteNumber(display.width, 1920)))
      var modeHeight = prevRecord && prevRecord.height > 0 ? prevRecord.height : (dispModes.length > 0 ? dispModes[0].height : Math.round(finiteNumber(display.height, 1080)))
      var modeRefresh = prevRecord && prevRecord.refreshRate > 0 ? prevRecord.refreshRate : (dispModes.length > 0 ? dispModes[0].refreshRate : finiteNumber(display.refreshRate, 60))
      var modeScale = prevRecord && prevRecord.scale > 0 ? prevRecord.scale : finiteNumber(display.scale, 1)
      var modeTransform = prevRecord && prevRecord.transform !== undefined ? prevRecord.transform : cleanTransform(display.transform)

      var record = {
        name: String(display.name), x: 0, y: 0,
        width: modeWidth, height: modeHeight, refreshRate: modeRefresh,
        scale: modeScale, transform: modeTransform
      }
      if (display.name !== source.name) record.mirrorOf = String(source.name)
      return record
    })
    var srcRecord = proposed[0]
    summary = "Duplicate mirrors " + source.name + " (" + srcRecord.width + " × " + srcRecord.height + ")"
      + " onto " + orderedGroup.slice(1).map(function(d) { return d.name }).join(", ")
      + " (aspect ratios differ; letterboxing may occur)."
  }

  var validation = validateTopologyPayload(proposed)
  return {
    changed: true,
    valid: validation.valid,
    reason: validation.reason,
    source: String(source.name),
    mode: modes.length > 0 ? modes[0] : null,
    summary: summary,
    proposed: proposed,
    previous: previous
  }
}

function isDuplicateTopology(payload) {
  var enabled = (Array.isArray(payload) ? payload : []).filter(function(record) {
    return record && record.enabled !== false && record.name
  })
  if (enabled.length < 2) return false
  var sources = enabled.filter(function(record) {
    return !record.mirrorOf || record.mirrorOf === "none"
  })
  if (sources.length !== 1) return false
  return enabled.every(function(record) {
    return record.name === sources[0].name || record.mirrorOf === sources[0].name
  })
}

function transportLabel(transport) {
  var labels = {
    internal: "Built-in",
    displayport: "DisplayPort",
    hdmi: "HDMI",
    vga: "VGA",
    unknown: "Unknown transport"
  }
  return labels[String(transport || "unknown")] || labels.unknown
}

function constraintReason(reason) {
  var item = reason || {}
  var output = String(item.output || "This display")
  var detail = String(item.detail || "")
  if (item.code === "missing-output" || item.code === "output-lost")
    return output + " disconnected. Refresh the display list and try again."
  if (item.code === "output-disabled")
    return output + " was disabled by the compositor. Refresh, then choose an available topology."
  if (item.code === "mode-unavailable")
    return output + " no longer offers the requested advertised mode. Refresh or choose another resolution and refresh rate."
  if (item.code === "mode-adjusted")
    return "The compositor used a different mode on " + output + ". The confirmed result was saved."
  if (item.code === "position-adjusted")
    return "The compositor adjusted the position of " + output + ". The confirmed position was saved."
  if (item.code === "scale-adjusted")
    return "The compositor adjusted the scale on " + output + ". The confirmed scale was saved."
  if (item.code === "mirror-adjusted")
    return "The compositor adjusted mirroring on " + output + ". The confirmed grouping was saved."
  if (item.code === "resource-conflict")
    return "The display hardware reported a resource limit" + (detail ? ": " + detail : ".")
  if (item.code === "compositor-rejected")
    return "The compositor rejected this combination. Try a lower resolution or refresh rate; the system detail was: "
      + (detail || "no detail was provided")
  if (item.code === "identity-weak")
    return "This display has no stable serial identity. Use Identify before assigning its profile."
  if (item.code === "identity-ambiguous")
    return "Multiple identical displays cannot be mapped safely. Use Identify and confirm each connector."
  return detail || "The compositor rejected this display configuration. Refresh and try a supported mode."
}

function explainBackendReport(raw) {
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line || line[0] !== "[") continue
    try {
      var reasons = JSON.parse(line)
      if (Array.isArray(reasons) && reasons.length)
        return reasons.map(constraintReason).join(" ")
    } catch (error) {}
  }
  return String(raw || "").trim()
}

if (typeof module !== "undefined") {
  module.exports = {
    cleanTransform: cleanTransform,
    logicalSize: logicalSize,
    buildTopologyPayload: buildTopologyPayload,
    validateTopologyPayload: validateTopologyPayload,
    prepareTogglePreview: prepareTogglePreview,
    withPositions: withPositions,
    validAnchor: validAnchor,
    relativeToAnchor: relativeToAnchor,
    isInternalDisplay: isInternalDisplay,
    presetAvailable: presetAvailable,
    currentPreset: currentPreset,
    preparePresetPreview: preparePresetPreview,
    workspacePayloadForPreset: workspacePayloadForPreset,
    commonAdvertisedModes: commonAdvertisedModes,
    prepareDuplicatePreview: prepareDuplicatePreview,
    isDuplicateTopology: isDuplicateTopology,
    transportLabel: transportLabel,
    constraintReason: constraintReason,
    explainBackendReport: explainBackendReport
  }
}
