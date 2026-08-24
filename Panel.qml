import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model
import "TopologyModel.js" as Topology
import "DisplayEventModel.js" as DisplayEvents

Panel {
  id: root
  moduleName: "omarchy.monitor"
  ipcTarget: "omarchy.monitor"
  manageIpc: false

  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the brightness + state methods below.
  property int brightnessPercent: 0
  property int pendingBrightnessPercent: 0
  property bool brightnessSetQueued: false
  property bool brightnessAvailable: false
  property string internalMonitor: ""
  property string externalMonitor: ""
  property string focusedMonitor: ""
  property string selectedMonitorName: ""
  property bool internalEnabled: false
  property bool mirrorEnabled: false
  property string monitorScale: ""
  property var displays: []
  property int enabledDisplayCount: 0
  property var layoutPreview: []
  property real layoutScale: 1
  property bool arrangementDirty: false
  property var stagedDisplaySettings: ({})
  readonly property bool settingsDirty: Object.keys(stagedDisplaySettings).length > 0
  property var workspaceAssignmentsActual: ({})
  property var stagedWorkspaceAssignments: ({})
  property bool workspaceAssignmentsManaged: false
  readonly property bool workspaceDirty: !Model.workspaceAssignmentsEqual(
    workspaceAssignmentsActual, stagedWorkspaceAssignments)
  readonly property bool layoutDirty: arrangementDirty || settingsDirty || workspaceDirty || anchorDirty
  readonly property var workspaceNumbers: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  property string expandedSettingsSection: ""
  property bool layoutDragging: false
  property bool layoutApplying: false
  property bool layoutConfirmationPending: false
  property int layoutConfirmationSeconds: 0
  property string layoutTransactionId: ""
  property string layoutProcessAction: ""
  property string layoutTransactionScope: ""
  property var displaySettingsBeforePreview: ({})
  property bool arrangementEditing: false
  property bool expandedLayoutOpen: false
  property string layoutError: ""
  property var displayEventState: DisplayEvents.initialState("")
  property bool displayTransitioning: false
  property bool staleCancellationRequested: false
  property bool stateRefreshQueued: false
  property string stateRefreshQueuedReason: ""
  property bool stateProcHotplugScan: false
  property bool identifyActive: false
  property string confirmationScreenName: ""
  property int confirmationWorkspaceId: 0
  readonly property var confirmationAvailableScreens: {
    var names = []
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var candidate = Quickshell.screens[i]
      if (candidate && candidate.name) names.push(String(candidate.name))
    }
    return names
  }
  readonly property string confirmationWorkspaceScreenName: {
    if (confirmationWorkspaceId <= 0) return ""
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++) {
      var monitor = monitors[i]
      if (monitor && monitor.activeWorkspace
          && Number(monitor.activeWorkspace.id) === confirmationWorkspaceId)
        return String(monitor.name || "")
    }
    return ""
  }
  readonly property string confirmationFocusedScreenName:
    Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
  readonly property string confirmationTargetScreenName:
    Model.confirmationTargetScreen(
      confirmationScreenName, confirmationWorkspaceScreenName,
      confirmationFocusedScreenName, confirmationAvailableScreens)
  readonly property bool ownsDisplayConfirmation: Model.ownsDisplayConfirmation(
    panel.screen ? String(panel.screen.name || "") : "",
    confirmationScreenName, confirmationWorkspaceScreenName,
    confirmationFocusedScreenName, confirmationAvailableScreens)
  property var profiles: []
  property string activeProfileId: ""
  property var activeTopologyVariants: ({})
  property string anchorDisplayName: ""
  property string storedAnchorDisplayName: ""
  property bool anchorDirty: false
  property var profileMatch: ({ status: "new", profileId: "", matches: [] })
  property bool profileSectionOpen: false
  property bool profileActionBusy: false
  property string pendingProfileDeleteId: ""
  readonly property bool profileKeepBlocked: {
    var status = String((profileMatch || {}).status || "new")
    return status === "moved" || status === "weak" || status === "ambiguous"
  }
  readonly property real layoutPadding: Style.space(10)
  readonly property real expandedLayoutPadding: Style.space(24)
  readonly property int layoutConfirmationDuration: 15
  readonly property var activeArrangementCanvas: expandedLayoutOpen
    ? expandedWorkspace.canvasItem : arrangementCanvas
  readonly property real activeLayoutPadding: expandedLayoutOpen
    ? expandedLayoutPadding : layoutPadding
  readonly property real activeLayoutUtilization: expandedLayoutOpen
    ? Model.responsiveDisplayUtilization(enabledDisplayCount) : 0.8
  readonly property var selectedDisplay: {
    var focused = null
    var first = null
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (!display || !display.enabled) continue
      if (!first) first = display
      if (display.name === selectedMonitorName) return display
      if (display.focused) focused = display
    }
    return focused || first
  }
  readonly property var previewDisplays: Model.displaysWithSettings(
    displays, stagedDisplaySettings)
  readonly property var anchorOptions: {
    var result = []
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.enabled)
        result.push({ value: display.name, label: display.name })
    }
    return result
  }
  readonly property var identifyEntries: DisplayEvents.identifyEntries(displays)
  readonly property var duplicatePlan: Topology.prepareDuplicatePreview(
    displays, stagedDisplaySettings, anchorDisplayName)
  readonly property string currentTopologyPreset: Topology.isDuplicateTopology(previewDisplays)
    ? "duplicate" : Topology.currentPreset(previewDisplays)
  readonly property bool internalPresetAvailable: Topology.presetAvailable(displays, "internal")
  readonly property bool externalPresetAvailable: Topology.presetAvailable(displays, "external")
  readonly property bool extendPresetAvailable: Topology.presetAvailable(displays, "extend")
  readonly property var selectedDisplayPreview: {
    for (var i = 0; i < previewDisplays.length; i++) {
      if (previewDisplays[i] && previewDisplays[i].name === selectedMonitorName)
        return previewDisplays[i]
    }
    return selectedDisplay
  }
  readonly property var resolutionOptions: Model.availableResolutions(
    selectedDisplay ? selectedDisplay.availableModes : [],
    selectedDisplay ? selectedDisplay.recommendedResolution : "")
  readonly property string resolutionValue: selectedDisplayPreview
    ? Model.matchingResolutionValue(resolutionOptions, selectedDisplayPreview.width,
                                    selectedDisplayPreview.height)
    : ""
  readonly property var rotationOptions: [
    { value: "0", label: "Landscape" },
    { value: "1", label: "Portrait (90°)" },
    { value: "2", label: "Landscape (180°)" },
    { value: "3", label: "Portrait (270°)" }
  ]
  readonly property string rotationValue: selectedDisplayPreview
    ? String(Model.cleanTransform(selectedDisplayPreview.transform)) : "0"
  readonly property var refreshRateOptions: selectedDisplayPreview
    ? Model.availableRefreshRates(selectedDisplay ? selectedDisplay.availableModes : [],
                                  selectedDisplayPreview.width, selectedDisplayPreview.height)
    : []
  readonly property string refreshRateValue: selectedDisplayPreview
    ? Model.matchingRefreshRateValue(refreshRateOptions, selectedDisplayPreview.refreshRate)
    : ""

  // Carry sub-notch touchpad deltas between wheel events.
  property real wheelAccumulator: 0

  // Cursor model shared by keyboard and mouse. Sections:
  //   "brightness" - single slider row, selectedIndex = -1 sentinel
  //                  (mirrors Audio's slider rows). Only present if a
  //                  controllable backlight was detected.
  //   "scale"      - 6 Button scale presets; treated as a single
  //                  horizontal row from j/k's perspective. h/l moves
  //                  between presets, identical to bluetooth's header.
  //   "monitors"   - vertical display row list for enabling/disabling displays;
  //                  j/k walks each row.
  // Mouse hover on a target updates root state via the components' `hovered`
  // signal so keyboard cursor and pointer share one highlight.
  readonly property var scalePresets: ["1", "1.25", "1.6", "2", "3", "4"]
  readonly property var scaleValues: {
    if (selectedDisplayPreview)
      return Model.availableScales(scalePresets, selectedDisplayPreview.width,
                                   selectedDisplayPreview.height)
    return scalePresets
  }
  property string focusSection: "scale"
  property int selectedIndex: 0
  property bool cursorActive: false

  // Text size slider — curated macOS-style notches (px). The panel snaps to
  // these stops; the CLI (omarchy-display-text-size) accepts any integer in range.
  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  // While a change is in flight, the chosen stop index overrides the live
  // base-size so the knob doesn't snap back during the file round-trip. -1 =
  // no pending change; follow Style.font.baseSize.
  property int textSizePreviewIndex: -1

  // A text-size change reflows the whole panel (both font and spacing scale),
  // which slides rows under a stationary pointer and fires synthetic hover.
  // While true, hover is not allowed to hijack the keyboard focus section —
  // otherwise h/l on the text-size slider can jump focus to another row.
  property bool reflowingText: false
  function markReflowing() {
    root.reflowingText = true
    reflowSettle.restart()
  }

  readonly property var visibleSections: {
    var list = []
    if (brightnessAvailable) list.push("brightness")
    list.push("textsize")
    if (displays.length > 1) list.push("presets")
    if (enabledDisplayCount > 1) list.push("arrangement")
    if (expandedSettingsSection === "workspaces" && selectedDisplay)
      list.push("workspaces")
    if (expandedSettingsSection === "display") {
      if (selectedDisplay && resolutionOptions.length > 0) list.push("resolution")
      list.push("rotation")
      if (refreshRateOptions.length > 0) list.push("refreshRate")
      list.push("scale")
    }
    if (expandedSettingsSection === "monitors" && displays.length > 0) {
      list.push("displayActions")
      list.push("monitors")
    }
    return list
  }

  function sectionCount(section) {
    if (section === "brightness") return 0  // only the slider sentinel at -1
    if (section === "textsize") return 0    // slider sentinel at -1, like brightness
    if (section === "arrangement") return layoutPreview.length + 2
    if (section === "workspaces") return workspaceNumbers.length
    if (section === "resolution") return 0
    if (section === "rotation") return 0
    if (section === "refreshRate") return 0
    if (section === "scale") return scaleValues.length
    if (section === "presets") return 4
    if (section === "displayActions") return 2
    if (section === "monitors") return displays.length
    return 0
  }

  function sectionIsSingleRow(section) {
    // brightness and text size are lone sliders; scale presets sit horizontally.
    return section === "brightness" || section === "textsize"
      || section === "workspaces" || section === "resolution" || section === "scale"
      || section === "rotation" || section === "refreshRate"
      || section === "displayActions" || section === "presets"
  }

  function sectionFirstIndex(section) {
    if (section === "brightness" || section === "textsize"
        || section === "resolution" || section === "rotation" || section === "refreshRate") return -1
    return 0
  }

  function moveCursor(delta) {
    arrangementEditing = false
    var sections = visibleSections
    if (!sections || sections.length === 0) return
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    var inSingleRow = sectionIsSingleRow(focusSection)
    var max = inSingleRow ? 0 : sectionCount(focusSection) - 1

    if (delta > 0) {
      if (!inSingleRow && selectedIndex < max) { selectedIndex = selectedIndex + 1; return }
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = sectionFirstIndex(focusSection)
      }
    } else {
      if (!inSingleRow && selectedIndex > 0) { selectedIndex = selectedIndex - 1; return }
      if (sIdx > 0) {
        var prev = sections[sIdx - 1]
        focusSection = prev
        // Coming up from below — land on the last navigable row of the prev
        // section, or its sentinel for single-row sections.
        selectedIndex = sectionIsSingleRow(prev) ? sectionFirstIndex(prev) : sectionCount(prev) - 1
      }
    }
  }

  // h/l walks horizontal option rows. Sliders handle horizontal movement
  // separately through their adjustment helpers.
  function moveCursorH(delta) {
    if (focusSection !== "scale" && focusSection !== "workspaces"
        && focusSection !== "displayActions" && focusSection !== "presets") return
    var values = focusSection === "workspaces" ? workspaceNumbers
      : (focusSection === "displayActions" ? [0, 1]
         : (focusSection === "presets" ? [0, 1, 2, 3] : scaleValues))
    var next = selectedIndex + delta
    if (next < 0) next = 0
    if (next > values.length - 1) next = values.length - 1
    selectedIndex = next
  }

  function adjustBrightness(delta) {
    if (focusSection !== "brightness") return
    if (!brightnessAvailable) return
    setBrightness(root.brightnessPercent + delta)
  }

  function activateCursor() {
    if (focusSection === "arrangement") {
      if (selectedIndex < layoutPreview.length) {
        selectedMonitorName = layoutPreview[selectedIndex].name
        if (!layoutConfirmationPending && !layoutApplying)
          arrangementEditing = !arrangementEditing
      } else if (selectedIndex === layoutPreview.length) {
        secondaryLayoutAction()
      } else if (selectedIndex === layoutPreview.length + 1) {
        primaryLayoutAction()
      }
      return
    }
    if (focusSection === "resolution") {
      resolutionDropdown.toggle()
      return
    }
    if (focusSection === "rotation") {
      rotationDropdown.toggle()
      return
    }
    if (focusSection === "refreshRate") {
      refreshRateDropdown.toggle()
      return
    }
    if (focusSection === "workspaces" && selectedIndex >= 0
        && selectedIndex < workspaceNumbers.length) {
      toggleWorkspaceForSelected(workspaceNumbers[selectedIndex])
      return
    }
    if (focusSection === "scale" && selectedIndex >= 0 && selectedIndex < scaleValues.length) {
      setScale(scaleValues[selectedIndex])
      return
    }
    if (focusSection === "displayActions") {
      if (selectedIndex === 0) showIdentifyOverlay()
      else if (selectedIndex === 1) refresh("manual")
      return
    }
    if (focusSection === "presets") {
      applyTopologyPreset(["internal", "extend", "external", "duplicate"][selectedIndex])
      return
    }
    if (focusSection === "monitors" && selectedIndex >= 0 && selectedIndex < displays.length) {
      var d = displays[selectedIndex]
      if (d) toggleDisplay(d.name, d.enabled)
    }
    // brightness: no separate action; the slider value is the action.
  }

  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length) return
    if (sections.indexOf(focusSection) < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    var count = sectionCount(focusSection)
    if (sectionIsSingleRow(focusSection)) {
      // brightness/text size use the -1 sentinel; scale clamps into the presets.
      if (focusSection === "brightness" || focusSection === "textsize"
          || focusSection === "resolution" || focusSection === "rotation"
          || focusSection === "refreshRate") selectedIndex = -1
      else if (selectedIndex < 0 || selectedIndex >= count) selectedIndex = 0
      return
    }
    if (count === 0) {
      var sIdx = sections.indexOf(focusSection)
      focusSection = sIdx > 0 ? sections[sIdx - 1] : sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    if (selectedIndex > count - 1) selectedIndex = count - 1
    if (selectedIndex < 0) selectedIndex = 0
  }

  // Keep the keyboard-focused row inside the viewport when the panel grows
  // taller than its allotted height (lots of displays). Mirrors audio's
  // ensureCursorVisible helper.
  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    var margin = 6
    if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin)
      flick.contentY = bottom + margin - flick.height
  }

  function brightnessIpc(percent) {
    var value = Number(percent)
    root.setBrightness(value)
    return "got " + root.pendingBrightnessPercent
  }

  function stateIpc() {
    return JSON.stringify({
      brightness: root.brightnessPercent,
      brightnessAvailable: root.brightnessAvailable,
      focusedMonitor: root.focusedMonitor,
      selectedMonitor: root.selectedMonitorName,
      displaySettingsDirty: root.settingsDirty,
      stagedDisplaySettings: root.stagedDisplaySettings,
      workspaceAssignments: root.stagedWorkspaceAssignments,
      workspaceAssignmentsDirty: root.workspaceDirty,
      expandedSettingsSection: root.expandedSettingsSection,
      scale: root.monitorScale,
      expandedLayoutOpen: root.expandedLayoutOpen,
      layoutConfirmationPending: root.layoutConfirmationPending,
      layoutConfirmationSeconds: root.layoutConfirmationSeconds,
      confirmationScreen: root.confirmationScreenName,
      confirmationWorkspace: root.confirmationWorkspaceId,
      confirmationTargetScreen: root.confirmationTargetScreenName,
      displays: root.displays
    })
  }

  IpcHandler {
    target: "omarchy.monitor"

    function brightness(percent: string): string { return root.brightnessIpc(percent) }
    function state(): string { return root.stateIpc() }
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function show() { root.open() }
    function hide() { root.close() }
    function fullscreen() {
      root.open()
      Qt.callLater(root.openExpandedLayout)
    }
    function revert(): string {
      if (emergencyRevertProc.running) return "busy"
      emergencyRevertProc.command = ["bash", root.pluginScript("apply-layout.sh"),
                                     "revert-pending"]
      emergencyRevertProc.running = true
      return "reverting"
    }
  }

  function refresh(reason) {
    var intent = DisplayEvents.refreshIntent(reason)
    if (stateProc.running) {
      if (intent.queueIfBusy) {
        root.stateRefreshQueued = true
        if (intent.bypassDebounce || !root.stateRefreshQueuedReason)
          root.stateRefreshQueuedReason = intent.bypassDebounce ? "manual" : "hotplug"
      }
      return
    }
    if (intent.bypassDebounce) hotplugQuietTimer.stop()
    root.stateProcHotplugScan = intent.settleTransition
    stateProc.running = true
  }

  function showIdentifyOverlay() {
    if (root.enabledDisplayCount < 1) return
    root.identifyActive = true
    identifyTimer.restart()
  }

  function noteDisplayHardwareEvent() {
    root.displayEventState = DisplayEvents.noteHardwareEvent(
      root.displayEventState, Date.now())
    root.displayTransitioning = root.displayEventState.transitioning
    hotplugQuietTimer.interval = Math.max(
      1, root.displayEventState.refreshAt - Date.now())
    hotplugQuietTimer.restart()
  }

  function handleMonitorSnapshot(raw) {
    var snapshot = null
    try { snapshot = JSON.parse(String(raw || "{}")) } catch (e) {}
    if (!snapshot || !snapshot.hardwareGeneration) return
    // A poll that was already in flight when the burst began may contain the
    // partial dock state. Only the quiet-window scan may settle a transition.
    if (root.displayEventState.transitioning && !root.stateProcHotplugScan) return

    var settled = DisplayEvents.settleSnapshot(
      root.displayEventState, snapshot.hardwareGeneration)
    root.displayEventState = settled.state
    root.displayTransitioning = settled.state.transitioning
    if (settled.hardwareChanged && root.layoutConfirmationPending)
      root.cancelStaleDisplayPreview()
  }

  function cancelStaleDisplayPreview() {
    if (!root.layoutConfirmationPending || !root.layoutTransactionId) return
    if (root.layoutApplying) {
      root.staleCancellationRequested = true
      return
    }
    root.staleCancellationRequested = false
    root.layoutProcessAction = "cancel"
    root.layoutApplying = true
    root.layoutError = ""
    layoutApplyProc.command = ["bash", root.pluginScript("apply-layout.sh"),
                               "cancel-stale", root.layoutTransactionId]
    layoutApplyProc.running = true
  }

  function updateProfiles(raw) {
    var state = null
    try { state = JSON.parse(String(raw || "{}")) } catch (e) {}
    if (!state) return
    root.profiles = Array.isArray(state.profiles) ? state.profiles : []
    root.activeProfileId = String(state.activeProfileId || "")
    root.activeTopologyVariants = state.activeVariants || ({})
    root.storedAnchorDisplayName = Topology.validAnchor(
      root.displays, String(state.activeAnchor || ""))
    if (!root.anchorDirty)
      root.anchorDisplayName = root.storedAnchorDisplayName
    root.profileMatch = state.match || ({ status: "new", profileId: "", matches: [] })
  }

  function selectAnchorDisplay(name) {
    var selected = Topology.validAnchor(root.displays, String(name || ""))
    if (!selected || selected === root.anchorDisplayName) return
    root.anchorDisplayName = selected
    root.anchorDirty = selected !== root.storedAnchorDisplayName
    root.layoutError = ""
  }

  function runProfileAction(action, profileId, value) {
    if (root.profileActionBusy || !profileId) return
    var command = ["bash", root.pluginScript("apply-layout.sh"),
                   "profile-action", action, profileId]
    if (value !== undefined && value !== null) command.push(String(value))
    root.profileActionBusy = true
    profileActionProc.command = command
    profileActionProc.running = true
  }

  function requestProfileDelete(profileId) {
    root.pendingProfileDeleteId = profileId
    profileDeleteDialog.opened = true
  }

  function setBrightness(value) {
    var percent = Model.clampBrightness(value)
    root.brightnessPercent = percent
    root.pendingBrightnessPercent = percent

    if (setBrightnessProc.running) {
      root.brightnessSetQueued = true
      return
    }

    root.brightnessSetQueued = false
    setBrightnessProc.command = ["omarchy-brightness-display", "--no-osd", "--monitor", root.focusedMonitor, percent + "%"]
    setBrightnessProc.running = true
  }

  function previewBrightness(value) {
    root.brightnessPercent = Model.clampBrightness(value)
    brightnessDebounce.restart()
  }

  function showBrightnessOsd(percent) {
    if (!bar || !bar.shell) return
    bar.shell.summon("omarchy.osd", JSON.stringify({
      icon: "brightness",
      value: percent
    }))
  }

  function normalizeScale(scale) {
    return Model.normalizeScale(scale)
  }

  function activeScaleIndex() {
    if (selectedDisplayPreview)
      return Model.matchingScaleIndex(scaleValues, selectedDisplayPreview.scale,
                                      selectedDisplayPreview.width,
                                      selectedDisplayPreview.height)
    return -1
  }

  function effectiveScale(scale) {
    if (selectedDisplayPreview)
      return Model.cleanScale(scale, selectedDisplayPreview.width,
                              selectedDisplayPreview.height)
    return normalizeScale(scale)
  }

  // Playful mood-name for a given brightness percent. Bands intentionally
  // span ~10–20 points so casual tweaks change the label, while small
  // nudges within one band don't.
  function brightnessName(percent) {
    return Model.brightnessName(percent)
  }

  function updateDisplays(displaysJson) {
    var parsed = Model.parseDisplays(displaysJson)
    root.displays = parsed.displays
    root.enabledDisplayCount = parsed.enabledDisplayCount
    if (root.settingsDirty)
      root.stagedDisplaySettings = Model.retainDisplaySettings(
        parsed.displays, root.stagedDisplaySettings)
    var selectedStillAvailable = false
    var fallback = ""
    for (var i = 0; i < parsed.displays.length; i++) {
      var display = parsed.displays[i]
      if (!display || !display.enabled) continue
      if (!fallback || display.focused) fallback = display.name
      if (display.name === root.selectedMonitorName) selectedStillAvailable = true
    }
    if (!selectedStillAvailable) root.selectedMonitorName = fallback
    root.scheduleDisplayLayoutReset()
  }

  function updateWorkspaceAssignments(workspacesJson, rulesJson) {
    var workspaces = []
    var rules = []
    try { workspaces = JSON.parse(String(workspacesJson || "[]")) } catch (e) {}
    try { rules = JSON.parse(String(rulesJson || "[]")) } catch (e) {}
    var preserveStaged = root.workspaceDirty
    var hasMonitorRules = false
    for (var i = 0; i < rules.length; i++) {
      if (rules[i] && String(rules[i].monitor || "") !== "") {
        hasMonitorRules = true
        break
      }
    }
    var assignments = Model.workspaceAssignments(
      root.displays, workspaces, rules, root.workspaceNumbers.length)
    root.workspaceAssignmentsActual = assignments
    if (!preserveStaged) {
      root.stagedWorkspaceAssignments = assignments
      root.workspaceAssignmentsManaged = hasMonitorRules
    }
  }

  function workspacesForMonitor(name) {
    return Model.workspacesForMonitor(root.stagedWorkspaceAssignments, name)
  }

  function workspaceOwner(workspace) {
    return String(root.stagedWorkspaceAssignments[String(workspace)] || "")
  }

  function toggleWorkspaceForSelected(workspace) {
    if (!root.selectedDisplay || root.layoutApplying || root.layoutConfirmationPending) return
    root.stagedWorkspaceAssignments = Model.toggleWorkspaceAssignment(
      root.stagedWorkspaceAssignments, workspace, root.selectedDisplay.name)
    root.layoutError = ""
  }

  function workspacePayload() {
    return root.workspaceAssignmentsManaged || root.workspaceDirty
      ? root.stagedWorkspaceAssignments : ({})
  }

  function toggleSettingsSection(section) {
    var next = Model.nextExpandedSection(
      root.expandedSettingsSection, section)
    root.expandedSettingsSection = next
    if (next === "workspaces") {
      root.focusSection = "workspaces"
      root.selectedIndex = 0
    } else if (next === "display") {
      root.focusSection = root.resolutionOptions.length > 0 ? "resolution" : "scale"
      root.selectedIndex = root.focusSection === "resolution" ? -1 : 0
    } else if (next === "monitors") {
      root.focusSection = "monitors"
      root.selectedIndex = 0
    }
    Qt.callLater(root.clampCursor)
  }

  function pluginScript(name) {
    return String(Qt.resolvedUrl(name)).replace(/^file:\/\//, "")
  }

  function resetDisplayLayout() {
    var canvas = root.activeArrangementCanvas
    if (!canvas || canvas.width <= 0 || canvas.height <= 0) return
    var fitted = Model.fitDisplayLayout(root.displays, canvas.width,
                                        canvas.height, root.activeLayoutPadding,
                                        root.activeLayoutUtilization)
    root.layoutPreview = fitted.items
    root.layoutScale = fitted.scale
    root.arrangementDirty = false
    root.stagedDisplaySettings = ({})
    root.stagedWorkspaceAssignments = root.workspaceAssignmentsActual
    root.anchorDisplayName = Topology.validAnchor(root.displays, root.storedAnchorDisplayName)
    root.anchorDirty = false
    root.layoutDragging = false
    root.arrangementEditing = false
    root.layoutError = ""
  }

  function refitDisplayLayout() {
    var canvas = root.activeArrangementCanvas
    if (!canvas || canvas.width <= 0 || canvas.height <= 0) return
    var fitted = Model.refitDisplayLayout(root.previewDisplays, root.layoutPreview,
                                          canvas.width, canvas.height,
                                          root.activeLayoutPadding,
                                          root.activeLayoutUtilization)
    root.layoutPreview = fitted.items
    root.layoutScale = fitted.scale
  }

  function openExpandedLayout() {
    if (root.expandedLayoutOpen || root.enabledDisplayCount < 2) return
    root.expandedLayoutOpen = true
    root.cursorActive = true
    root.focusSection = "arrangement"
    if (root.selectedIndex < 0 || root.selectedIndex >= root.layoutPreview.length)
      root.selectedIndex = 0
    root.arrangementEditing = false
    Qt.callLater(root.refitDisplayLayout)
  }

  function closeExpandedLayout() {
    if (!root.expandedLayoutOpen) return
    if (root.layoutConfirmationPending) root.revertDisplayLayout()
    root.expandedLayoutOpen = false
    root.arrangementEditing = false
    Qt.callLater(root.refitDisplayLayout)
  }

  function shouldAutoResetDisplayLayout() {
    return Model.shouldAutoResetDisplayLayout({
      dirty: root.layoutDirty,
      dragging: root.layoutDragging,
      confirmationPending: root.layoutConfirmationPending,
      applying: root.layoutApplying
    })
  }

  function scheduleDisplayLayoutReset() {
    if (!root.shouldAutoResetDisplayLayout()) return
    Qt.callLater(function() {
      if (root.shouldAutoResetDisplayLayout()) root.resetDisplayLayout()
    })
  }

  function beginDisplayDrag() {
    if (root.layoutConfirmationPending || root.layoutApplying) return
    root.layoutDragging = true
    root.arrangementDirty = true
    root.layoutError = ""
  }

  function finishDisplayDrag(name, canvasX, canvasY) {
    if (!root.layoutDragging) return
    root.moveDisplay(name, canvasX, canvasY)
    root.layoutDragging = false
  }

  function moveDisplay(name, canvasX, canvasY) {
    if (root.layoutConfirmationPending || root.layoutApplying) return
    var canvas = root.activeArrangementCanvas
    if (!canvas) return
    root.arrangementDirty = true
    root.layoutPreview = Model.moveDisplayInCanvas(
      root.layoutPreview, name, canvasX, canvasY, root.layoutScale,
      root.activeLayoutPadding, canvas.width, canvas.height,
      Style.space(12))
    root.layoutError = ""
  }

  function nudgeSelectedDisplay(dx, dy) {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.layoutPreview.length) return
    var item = root.layoutPreview[root.selectedIndex]
    root.moveDisplay(item.name, item.x + dx * Style.space(4), item.y + dy * Style.space(4))
  }

  function selectAdjacentDisplay(direction) {
    root.cursorActive = true
    root.focusSection = "arrangement"
    root.arrangementEditing = false
    root.selectedIndex = Model.cycleDisplayIndex(
      root.selectedIndex, root.layoutPreview.length, direction)
    if (root.selectedIndex >= 0 && root.selectedIndex < root.layoutPreview.length)
      root.selectedMonitorName = root.layoutPreview[root.selectedIndex].name
  }

  function activeWorkspaceForScreen(screenName) {
    var wanted = String(screenName || "")
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++) {
      var monitor = monitors[i]
      if (!monitor || String(monitor.name || "") !== wanted
          || !monitor.activeWorkspace) continue
      var workspace = Math.floor(Number(monitor.activeWorkspace.id))
      return isFinite(workspace) && workspace > 0 ? workspace : 0
    }
    return 0
  }

  function beginDisplayPreview(proposed, previous, scope, preset, workspaceOverride) {
    if (root.layoutApplying || root.layoutConfirmationPending) return
    if (proposed.length < 1 || previous.length < 1) {
      root.layoutError = "Could not build valid display settings"
      return
    }
    var anchor = Topology.validAnchor(proposed, root.anchorDisplayName)
    proposed = Topology.relativeToAnchor(proposed, anchor)
    root.anchorDisplayName = anchor
    root.layoutTransactionId = "display-" + Date.now()
    root.confirmationScreenName = panel.screen
      ? String(panel.screen.name || "") : String(root.focusedMonitor || "")
    root.confirmationWorkspaceId = root.activeWorkspaceForScreen(
      root.confirmationScreenName)
    root.layoutProcessAction = "preview"
    root.layoutTransactionScope = scope || "layout"
    root.layoutApplying = true
    root.layoutError = ""
    var workspaces = workspaceOverride === undefined
      ? root.workspacePayload() : workspaceOverride
    layoutApplyProc.command = ["bash", root.pluginScript("apply-layout.sh"),
                               "preview", root.layoutTransactionId,
                               JSON.stringify(proposed), JSON.stringify(previous),
                               JSON.stringify(workspaces),
                               root.layoutTransactionScope, anchor, String(preset || ""),
                               root.confirmationScreenName,
                               String(root.confirmationWorkspaceId)]
    layoutApplyProc.running = true
  }

  function applyTopologyPreset(preset) {
    if (root.layoutApplying || root.layoutConfirmationPending) return
    if (preset === "duplicate") {
      var duplicate = root.duplicatePlan
      if (!duplicate.changed || !duplicate.valid) {
        root.layoutError = duplicate.reason || "Duplicate is unavailable"
        return
      }
      root.anchorDisplayName = duplicate.source
      root.layoutError = ""
      root.beginDisplayPreview(
        duplicate.proposed, duplicate.previous, "topology", "duplicate",
        Topology.workspacePayloadForPreset(
          root.workspacePayload(), duplicate.proposed, duplicate.source))
      return
    }
    var transaction = Topology.preparePresetPreview(
      root.displays, root.stagedDisplaySettings, preset,
      root.activeTopologyVariants ? root.activeTopologyVariants[preset] : null)
    if (!transaction.changed || !transaction.valid) {
      root.layoutError = transaction.reason || "This display preset is unavailable"
      return
    }
    root.anchorDisplayName = Topology.validAnchor(transaction.proposed, transaction.anchor)
    var workspaces = transaction.restored
      ? transaction.workspaces
      : Topology.workspacePayloadForPreset(
          root.workspacePayload(), transaction.proposed, root.anchorDisplayName)
    root.layoutError = ""
    root.beginDisplayPreview(
      transaction.proposed, transaction.previous, "topology", preset, workspaces)
  }

  function recoverDisplayConfirmation(raw) {
    var pending = Model.parsePendingDisplayTransaction(raw)
    if (!pending) return
    root.layoutTransactionId = pending.id
    root.layoutTransactionScope = pending.scope
    root.confirmationScreenName = pending.originScreen
    root.confirmationWorkspaceId = pending.originWorkspace
    root.layoutConfirmationSeconds = pending.remainingSeconds
    root.layoutConfirmationPending = true
    layoutConfirmationTimer.restart()
    Qt.callLater(root.refitDisplayLayout)
  }

  function applyDisplayLayout() {
    if (!root.layoutDirty || root.layoutApplying || root.layoutConfirmationPending
        || root.layoutPreview.length < 1) return
    var canvas = root.activeArrangementCanvas
    if (!canvas) return
    var positions = Model.normalizeDisplayLayout(root.layoutPreview)
    var proposed = Topology.withPositions(
      Topology.buildTopologyPayload(root.displays, root.stagedDisplaySettings), positions)
    var previous = Topology.buildTopologyPayload(root.displays, {})
    root.beginDisplayPreview(proposed, previous, "layout")
  }

  function saveWorkspaceAssignments() {
    if (!root.workspaceDirty || root.layoutApplying || root.layoutConfirmationPending) return
    var monitors = Topology.buildTopologyPayload(root.previewDisplays, root.stagedDisplaySettings)
    if (monitors.length < 1) {
      root.layoutError = "Could not build current display settings"
      return
    }
    root.layoutApplying = true
    root.layoutError = ""
    workspaceApplyProc.command = ["bash", root.pluginScript("apply-layout.sh"),
                                  "save-workspaces", JSON.stringify(monitors),
                                  JSON.stringify(root.stagedWorkspaceAssignments),
                                  root.anchorDisplayName]
    workspaceApplyProc.running = true
  }

  function keepDisplayLayout(profileChoice, profileId) {
    if (!root.layoutConfirmationPending || root.layoutApplying || !root.layoutTransactionId) return
    var status = String((root.profileMatch || {}).status || "new")
    if ((status === "weak" || status === "ambiguous") && !profileChoice) {
      root.layoutError = "Identify and map uncertain displays before keeping this profile."
      return
    }
    if (status === "moved" && !profileChoice) {
      root.layoutError = "Choose Update profile or Save as new in Profiles."
      root.profileSectionOpen = true
      return
    }
    root.layoutProcessAction = "keep"
    root.layoutApplying = true
    root.layoutError = ""
    layoutApplyProc.command = ["bash", root.pluginScript("apply-layout.sh"),
                               "keep", root.layoutTransactionId]
    if (profileChoice && profileId)
      layoutApplyProc.command.push(profileChoice, profileId)
    layoutApplyProc.running = true
  }

  function revertDisplayLayout() {
    if (!root.layoutConfirmationPending || root.layoutApplying || !root.layoutTransactionId) return
    root.layoutProcessAction = "revert"
    root.layoutApplying = true
    root.layoutError = ""
    layoutApplyProc.command = ["bash", root.pluginScript("apply-layout.sh"),
                               "revert", root.layoutTransactionId]
    layoutApplyProc.running = true
  }

  function secondaryLayoutAction() {
    if (root.layoutConfirmationPending) root.revertDisplayLayout()
    else root.resetDisplayLayout()
  }

  function primaryLayoutAction() {
    if (root.layoutConfirmationPending) root.keepDisplayLayout()
    else if (root.workspaceDirty && !root.arrangementDirty && !root.settingsDirty
             && !root.anchorDirty)
      root.saveWorkspaceAssignments()
    else root.applyDisplayLayout()
  }

  function toggleDisplay(name, enabled) {
    if (!name) return
    if (enabled && root.enabledDisplayCount <= 1) return
    if (root.layoutApplying || root.layoutConfirmationPending) return

    var transaction = Topology.prepareTogglePreview(
      root.previewDisplays, root.stagedDisplaySettings, name)
    if (!transaction.changed) return
    if (!transaction.valid) {
      root.layoutError = transaction.reason
      return
    }
    root.displaySettingsBeforePreview = root.stagedDisplaySettings
    root.stagedDisplaySettings = transaction.stagedSettings
    root.layoutError = ""
    Qt.callLater(root.refitDisplayLayout)
    root.beginDisplayPreview(transaction.proposed, transaction.previous, "settings")
  }

  function setScale(scale) {
    if (!root.selectedDisplayPreview) return
    var cleaned = Number(Model.cleanScale(scale, root.selectedDisplayPreview.width,
                                          root.selectedDisplayPreview.height))
    if (!isFinite(cleaned) || cleaned <= 0) return
    root.stageMonitorSetting({ scale: cleaned })
  }

  function setRotation(value) {
    var transform = Number(value)
    if (!isFinite(transform) || Math.floor(transform) !== transform
        || transform < 0 || transform > 3) return
    root.stageMonitorSetting({ transform: transform })
  }

  function setResolution(value) {
    if (!root.selectedDisplay) return
    var mode = Model.parseDisplayMode(value)
    if (!mode) return
    var refreshOptions = Model.availableRefreshRates(root.selectedDisplay.availableModes,
                                                      mode.width, mode.height)
    var refreshRate = Number(Model.preferredRefreshRate(
      refreshOptions, root.selectedDisplayPreview.refreshRate))
    if (!isFinite(refreshRate) || refreshRate <= 0) return
    var cleanedScale = Number(Model.cleanScale(root.selectedDisplayPreview.scale,
                                                mode.width, mode.height))
    root.stageMonitorSetting({
      width: mode.width,
      height: mode.height,
      refreshRate: refreshRate,
      scale: cleanedScale > 0 ? cleanedScale : 1
    })
  }

  function setRefreshRate(value) {
    var refreshRate = Number(value)
    if (!isFinite(refreshRate) || refreshRate <= 0) return
    root.stageMonitorSetting({ refreshRate: refreshRate })
  }

  function stageMonitorSetting(overrides) {
    if (!root.selectedDisplay || root.layoutApplying || root.layoutConfirmationPending) return
    var transaction = Model.prepareDisplaySettingPreview(
      root.displays, root.stagedDisplaySettings, root.selectedDisplay.name, overrides,
      function(displays, staged) {
        return Topology.buildTopologyPayload(displays, staged)
      })
    if (!transaction.changed) return
    root.displaySettingsBeforePreview = root.stagedDisplaySettings
    root.stagedDisplaySettings = transaction.stagedSettings
    root.layoutError = ""
    Qt.callLater(root.refitDisplayLayout)
    root.beginDisplayPreview(transaction.proposed, transaction.previous, "settings")
  }

  // ---- Text size (shell base font + GTK text-scaling, via one CLI) ----
  function nearestTextStop(px) {
    var best = 0
    var bestDist = 1e9
    for (var i = 0; i < textSizeStops.length; i++) {
      var d = Math.abs(textSizeStops[i] - px)
      if (d < bestDist) { bestDist = d; best = i }
    }
    return best
  }

  // Effective stop index: the pending choice while a change is in flight,
  // otherwise whatever Style's live base-size rounds to.
  function currentTextIndex() {
    return textSizePreviewIndex >= 0 ? textSizePreviewIndex : nearestTextStop(Style.font.baseSize)
  }

  // px shown in the header: the pending stop if any, else the true base-size
  // (which may be an off-notch value set from the CLI).
  function displayedTextPx() {
    return textSizePreviewIndex >= 0 ? textSizeStops[textSizePreviewIndex] : Style.font.baseSize
  }

  function setTextSize(px) {
    textScaleProc.command = ["omarchy-display-text-size", String(px)]
    if (!textScaleProc.running) textScaleProc.running = true
  }

  function adjustTextSize(deltaSteps) {
    var idx = currentTextIndex() + deltaSteps
    if (idx < 0) idx = 0
    if (idx > textSizeStops.length - 1) idx = textSizeStops.length - 1
    markReflowing()
    textSizePreviewIndex = idx
    setTextSize(textSizeStops[idx])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: {
    restoreLayoutProc.command = ["bash", root.pluginScript("apply-layout.sh"), "restore"]
    restoreLayoutProc.running = true
  }

  // KeyboardPanel primes focus at open-time, so SUPER-bound IPC summons land
  // with j/k ready to navigate. Keep a default landing point, but don't paint
  // the cursor until hover or the first navigation key.
  onOpenedChanged: {
    if (opened) {
      arrangementEditing = false
      layoutError = ""
      refresh()
      if (brightnessAvailable) {
        focusSection = "brightness"
        selectedIndex = -1
      } else {
        focusSection = "textsize"
        selectedIndex = -1
      }
      cursorActive = false
    } else {
      root.expandedLayoutOpen = false
      // Keep the transaction alive when the panel is recreated by a monitor
      // change. The watchdog timer remains the safety fallback; a recovered
      // panel will reopen and expose Keep/Revert again.
    }
  }

  onBrightnessAvailableChanged: clampCursor()
  onDisplaysChanged: clampCursor()
  onScaleValuesChanged: clampCursor()
  onVisibleSectionsChanged: clampCursor()

  // Quickshell screen-list changes are the event-driven fast path. The event
  // model waits for a 1-second quiet window (3-second maximum) before asking
  // Hyprland for a stable snapshot. Polling below remains the recovery path
  // when the host does not emit this signal.
  Connections {
    target: Quickshell
    function onScreensChanged() { root.noteDisplayHardwareEvent() }
  }

  Timer {
    id: hotplugQuietTimer
    interval: DisplayEvents.QUIET_WINDOW_MS
    repeat: false
    onTriggered: {
      if (DisplayEvents.refreshDue(root.displayEventState, Date.now()))
        root.refresh("hotplug")
      else if (root.displayEventState.transitioning) {
        interval = Math.max(1, root.displayEventState.refreshAt - Date.now())
        restart()
      }
    }
  }

  Timer {
    id: identifyTimer
    interval: 5000
    repeat: false
    onTriggered: root.identifyActive = false
  }

  // Only poll while the panel is open; the bar glyph tracks monitor count via
  // Quickshell.screens, and open-time refresh + Component.onCompleted cover the
  // rest. External brightness changes are reflected whenever the panel is open.
  Timer {
    interval: 5000
    running: root.opened || root.layoutConfirmationPending
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: stateProc
    command: ["bash", root.pluginScript("state.sh")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var brightness = String(lines[0] || "").trim()
        root.brightnessAvailable = brightness !== "unavailable" && brightness !== ""
        root.brightnessPercent = root.brightnessAvailable ? Math.max(0, Math.min(100, parseInt(brightness, 10))) : 0
        root.internalMonitor = String(lines[1] || "").trim()
        root.externalMonitor = String(lines[2] || "").trim()
        root.internalEnabled = String(lines[3] || "").trim() !== ""
        root.mirrorEnabled = String(lines[4] || "").trim() === root.externalMonitor && root.externalMonitor !== ""
        root.focusedMonitor = String(lines[5] || "").trim()
        root.monitorScale = root.normalizeScale(String(lines[6] || "").trim())
        root.updateDisplays(String(lines[7] || "[]").trim())
        root.updateWorkspaceAssignments(String(lines[8] || "[]").trim(),
                                        String(lines[9] || "[]").trim())
        root.recoverDisplayConfirmation(String(lines[10] || "{}").trim())
        root.handleMonitorSnapshot(String(lines[11] || "{}").trim())
        root.updateProfiles(String(lines[12] || "{}").trim())
      }
    }
    onRunningChanged: {
      if (running || !root.stateRefreshQueued) return
      var queuedReason = root.stateRefreshQueuedReason || "hotplug"
      root.stateRefreshQueued = false
      root.stateRefreshQueuedReason = ""
      Qt.callLater(function() { root.refresh(queuedReason) })
    }
  }

  Timer {
    id: brightnessDebounce
    interval: 180
    repeat: false
    onTriggered: root.setBrightness(root.brightnessPercent)
  }

  Process {
    id: setBrightnessProc
    stdout: StdioCollector { waitForEnd: true }
    // Do NOT call refresh() after a brightness set completes. The local
    // brightnessPercent we just wrote is authoritative; re-reading via
    // `omarchy-brightness-display` races the hardware/driver and can
    // return an empty string, which the parser then coerces to 0 —
    // visible as a "bounce to zero" after h/l keypresses. External
    // brightness changes are still picked up by the 5s periodic refresh,
    // the open-time refresh, and Component.onCompleted.
    onRunningChanged: {
      if (running) return
      if (root.brightnessSetQueued) {
        root.setBrightness(root.pendingBrightnessPercent)
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) root.refresh()
  }

  Process {
    id: emergencyRevertProc
    stderr: StdioCollector { id: emergencyRevertError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var message = Topology.explainBackendReport(emergencyRevertError.text)
        root.layoutError = message || "Emergency display revert failed"
      }
      root.layoutConfirmationPending = false
      root.layoutConfirmationSeconds = 0
      root.layoutTransactionId = ""
      root.confirmationScreenName = ""
      root.confirmationWorkspaceId = 0
      layoutConfirmationTimer.stop()
      root.refresh("manual")
    }
  }

  Process {
    id: restoreLayoutProc
    stderr: StdioCollector { id: restoreLayoutError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var message = String(restoreLayoutError.text || "").trim()
        root.layoutError = message || "Could not restore saved display layout"
      }
      root.refresh()
    }
  }

  Process {
    id: layoutApplyProc
    stderr: StdioCollector { id: layoutApplyError; waitForEnd: true }
    onExited: function(exitCode) {
      var completedAction = root.layoutProcessAction
      root.layoutApplying = false
      if (exitCode === 0) {
        if (completedAction === "preview") {
          if (root.layoutTransactionScope === "layout") root.arrangementDirty = false
          root.arrangementEditing = false
          root.layoutConfirmationPending = true
          root.layoutConfirmationSeconds = root.layoutConfirmationDuration
          layoutConfirmationTimer.restart()
          root.refresh()
          if (root.staleCancellationRequested)
            Qt.callLater(root.cancelStaleDisplayPreview)
          // The compact confirmation overlay is independent of the bar icon,
          // so close the full menu before per-screen bars are recreated.
          if (root.opened) Qt.callLater(root.close)
        } else {
          root.stagedDisplaySettings = ({})
          root.displaySettingsBeforePreview = ({})
          if (completedAction === "keep") {
            root.workspaceAssignmentsManaged = Object.keys(root.stagedWorkspaceAssignments).length > 0
            root.storedAnchorDisplayName = root.anchorDisplayName
          } else {
            root.anchorDisplayName = Topology.validAnchor(
              root.displays, root.storedAnchorDisplayName)
          }
          root.anchorDirty = false
          if (root.layoutTransactionScope === "layout") root.arrangementDirty = false
          root.layoutConfirmationPending = false
          root.layoutConfirmationSeconds = 0
          root.layoutTransactionId = ""
          root.layoutTransactionScope = ""
          root.confirmationScreenName = ""
          root.confirmationWorkspaceId = 0
          layoutConfirmationTimer.stop()
          root.staleCancellationRequested = false
          if (completedAction === "cancel")
            root.layoutError = "Displays changed. The preview was canceled and the available layout was restored."
          else if (completedAction === "keep") {
            var adjustment = Topology.explainBackendReport(layoutApplyError.text)
            if (adjustment) root.layoutError = adjustment
          }
          root.refresh()
        }
      } else {
        var message = Topology.explainBackendReport(layoutApplyError.text)
        root.layoutError = message || "Could not apply display layout"
        if (completedAction === "preview") {
          if (root.layoutTransactionScope === "settings") {
            root.stagedDisplaySettings = root.displaySettingsBeforePreview
            root.displaySettingsBeforePreview = ({})
            Qt.callLater(root.refitDisplayLayout)
          }
          root.layoutTransactionId = ""
          root.layoutTransactionScope = ""
          root.confirmationScreenName = ""
          root.confirmationWorkspaceId = 0
        }
      }
      root.layoutProcessAction = ""
    }
  }

  Process {
    id: workspaceApplyProc
    stderr: StdioCollector { id: workspaceApplyError; waitForEnd: true }
    onExited: function(exitCode) {
      root.layoutApplying = false
      if (exitCode === 0) {
        root.workspaceAssignmentsManaged = Object.keys(root.stagedWorkspaceAssignments).length > 0
        root.workspaceAssignmentsActual = root.stagedWorkspaceAssignments
        root.storedAnchorDisplayName = root.anchorDisplayName
        root.anchorDirty = false
        root.refresh()
      } else {
        var message = String(workspaceApplyError.text || "").trim()
        root.layoutError = message || "Could not save workspace assignments"
      }
    }
  }

  Process {
    id: profileActionProc
    stderr: StdioCollector { id: profileActionError; waitForEnd: true }
    onExited: function(exitCode) {
      root.profileActionBusy = false
      if (exitCode !== 0) {
        var message = String(profileActionError.text || "").trim()
        root.layoutError = message || "Could not update display profile"
      }
      root.refresh()
    }
  }

  Timer {
    id: layoutConfirmationTimer
    interval: 1000
    repeat: true
    onTriggered: {
      var next = Model.advanceDisplayConfirmation(root.layoutConfirmationSeconds)
      root.layoutConfirmationSeconds = next.remaining
      if (next.expired) {
        stop()
        root.revertDisplayLayout()
      }
    }
  }

  // Applies text size via the CLI, which rewrites the shell override file;
  // Style picks the new base-size up through its own file watch, so there's
  // nothing to refresh here.
  Process {
    id: textScaleProc
    stdout: StdioCollector { waitForEnd: true }
  }

  // Clears the hover-suppression flag once the reflow triggered by a text-size
  // change has settled.
  Timer {
    id: reflowSettle
    interval: 300
    repeat: false
    onTriggered: root.reflowingText = false
  }

  // Once Style's base-size catches up to the pending choice, drop the preview
  // so the slider tracks the live value again. The change itself reflows the
  // panel, so suppress hover for a beat while it lands.
  Connections {
    target: Style
    function onFontBaseSizeChanged() {
      root.markReflowing()
      if (root.textSizePreviewIndex >= 0
          && root.nearestTextStop(Style.font.baseSize) === root.textSizePreviewIndex)
        root.textSizePreviewIndex = -1
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"
    onPressed: function(b) { root.toggle() }
    onWheelMoved: function(delta) {
      if (!root.brightnessAvailable) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      root.setBrightness(root.brightnessPercent + wheel.steps * 5)
      root.showBrightnessOsd(root.brightnessPercent)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (root.arrangementEditing && root.focusSection === "arrangement") {
          root.nudgeSelectedDisplay(dx, dy)
          return
        }
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) {
          if (root.focusSection === "brightness") root.adjustBrightness(dx * 5)
          else if (root.focusSection === "textsize") root.adjustTextSize(dx)
          else if (root.focusSection === "scale" || root.focusSection === "workspaces"
                   || root.focusSection === "displayActions"
                   || root.focusSection === "presets")
            root.moveCursorH(dx)
        }
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: {
        if (root.arrangementEditing) root.arrangementEditing = false
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Hero: display icon · title/status ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              text: root.displays.length > 1 ? "󰍺" : "󰍹"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Display"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                id: heroLabel
                text: {
                  if (root.brightnessAvailable) {
                    return root.brightnessName(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent).toUpperCase()
                  }
                  return "FIXED BRIGHTNESS"
                }
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          // ---------- Brightness ----------
          PanelSeparator {
            visible: root.brightnessAvailable
            foreground: root.bar.foreground
          }

          Column {
            visible: root.brightnessAvailable
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(brightnessHeader.implicitHeight, brightnessPercent.implicitHeight)

              PanelSectionHeader {
                id: brightnessHeader
                text: "BRIGHTNESS"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: brightnessPercent
                text: Math.round(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent) + "%"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: brightnessRow
              width: parent.width
              height: brightnessSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "brightness" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(brightnessRow)
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: brightnessSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 1
                maximum: 100
                step: 1
                value: root.brightnessPercent
                integer: true
                onMoved: function(v) { root.previewBrightness(v) }
                onReleased: function(v) {
                  brightnessDebounce.stop()
                  root.setBrightness(v)
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered && !root.reflowingText) {
                  root.cursorActive = true
                  root.focusSection = "brightness"
                  root.selectedIndex = -1
                }
              }
            }
          }

          // ---------- Text size ----------
          PanelSeparator {
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(textSizeHeader.implicitHeight, textSizePx.implicitHeight)

              PanelSectionHeader {
                id: textSizeHeader
                text: "TEXT SIZE"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: textSizePx
                text: (textSizeSlider.dragging
                       ? root.textSizeStops[Math.round(textSizeSlider.liveValue)]
                       : root.displayedTextPx()) + "px"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: textSizeRow
              width: parent.width
              height: textSizeSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "textsize" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(textSizeRow)
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: textSizeSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 0
                maximum: root.textSizeStops.length - 1
                step: 1
                integer: true
                tickCount: root.textSizeStops.length
                value: root.currentTextIndex()
                onReleased: function(v) { root.setTextSize(root.textSizeStops[Math.round(v)]) }
              }

              HoverHandler {
                onHoveredChanged: if (hovered && !root.reflowingText) {
                  root.cursorActive = true
                  root.focusSection = "textsize"
                  root.selectedIndex = -1
                }
              }
            }
          }

          // ---------- Topology presets ----------
          PanelSeparator {
            visible: root.displays.length > 1
            foreground: root.bar.foreground
          }

          TopologyPresets {
            visible: root.displays.length > 1
            width: parent.width
            internalAvailable: root.internalPresetAvailable
            externalAvailable: root.externalPresetAvailable
            extendAvailable: root.extendPresetAvailable
            duplicateAvailable: root.duplicatePlan.valid === true
            duplicateSummary: root.duplicatePlan.summary || "Duplicate is unavailable."
            currentPreset: root.currentTopologyPreset
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            cursorActive: root.cursorActive
            focusSection: root.focusSection
            selectedIndex: root.selectedIndex
            busy: root.layoutApplying || root.layoutConfirmationPending
            onPresetRequested: function(preset) { root.applyTopologyPreset(preset) }
          }

          // ---------- Arrangement ----------
          PanelSeparator {
            visible: root.enabledDisplayCount > 1
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.enabledDisplayCount > 1

            Item {
              width: parent.width
              implicitHeight: Math.max(arrangementHeader.implicitHeight,
                                       arrangementHint.implicitHeight)

              PanelSectionHeader {
                id: arrangementHeader
                text: "ARRANGEMENT"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: arrangementHint
                text: root.layoutConfirmationPending ? "CONFIRM DISPLAY SETTINGS"
                  : (root.layoutApplying ? "APPLYING PREVIEW…"
                     : (root.arrangementEditing ? "ARROWS MOVE · ENTER DROPS"
                        : (root.layoutDirty ? "CHANGES READY · CLICK APPLY" : "DRAG TO ADJUST")))
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            BorderSurface {
              id: arrangementCanvas
              width: parent.width
              height: Style.space(170)
              clip: true
              radius: Style.cornerRadius
              color: Style.normalFillFor(root.bar.foreground)
              borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)
              onWidthChanged: root.scheduleDisplayLayoutReset()

              Repeater {
                model: root.layoutPreview

                DisplayLayoutTile {
                  required property var modelData
                  required property int index

                  display: modelData
                  tileIndex: index
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  workspaceNumbers: root.workspacesForMonitor(modelData.name)
                  selected: modelData.name === root.selectedMonitorName
                  hasCursor: root.cursorActive
                    && root.focusSection === "arrangement"
                    && root.selectedIndex === index
                  editing: root.arrangementEditing
                    && root.focusSection === "arrangement"
                    && root.selectedIndex === index
                  interactionEnabled: !root.layoutConfirmationPending && !root.layoutApplying
                  onDragBegan: root.beginDisplayDrag()
                  onDragFinished: function(name, canvasX, canvasY) {
                    root.finishDisplayDrag(name, canvasX, canvasY)
                  }
                  onPointerSelected: {
                    root.cursorActive = true
                    root.focusSection = "arrangement"
                    root.selectedIndex = index
                    if (dragStarted) root.arrangementEditing = false
                  }
                  onMonitorSelected: root.selectedMonitorName = modelData.name
                }
              }

              Button {
                id: expandArrangement
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: Style.space(6)
                anchors.bottomMargin: Style.space(6)
                z: 10
                iconText: "󰊓"
                tooltipText: "Open full-screen arrangement"
                enabled: !root.layoutApplying
                foreground: root.bar.foreground
                background: Color.popups.background
                fontFamily: root.bar.fontFamily
                iconSize: Style.font.subtitle
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(4)
                bordered: true
                onClicked: root.openExpandedLayout()
              }
            }

            BorderSurface {
              visible: root.layoutConfirmationPending
              width: parent.width
              implicitHeight: confirmationText.implicitHeight + Style.spacing.controlPaddingY * 2
              color: Style.selectedFillFor(root.bar.foreground, Color.accent)
              borderSpec: Border.controlSpec("selected", root.bar.foreground, Color.accent)
              radius: Style.cornerRadius

              Text {
                id: confirmationText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.controlPaddingX
                anchors.rightMargin: Style.spacing.controlPaddingX
                text: "Keep these display settings? Reverting in "
                      + root.layoutConfirmationSeconds + " seconds."
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
              }
            }

            Text {
              visible: root.layoutError !== ""
              width: parent.width
              text: root.layoutError
              textFormat: Text.PlainText
              color: root.bar.urgent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            Row {
              width: parent.width
              spacing: Style.spacing.xs

              readonly property real cellWidth: (width - spacing) / 2

              Button {
                width: parent.cellWidth
                text: root.layoutConfirmationPending
                  ? (root.layoutProcessAction === "revert" ? "Reverting…" : "Revert")
                  : "Reset"
                enabled: !root.layoutApplying && (root.layoutConfirmationPending || root.layoutDirty)
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.caption
                bordered: true
                hasCursor: root.cursorActive && root.focusSection === "arrangement"
                           && root.selectedIndex === root.layoutPreview.length
                onClicked: root.secondaryLayoutAction()
                onHovered: function(isHovered) {
                  if (!isHovered) return
                  root.cursorActive = true
                  root.focusSection = "arrangement"
                  root.selectedIndex = root.layoutPreview.length
                }
              }

              Button {
                width: parent.cellWidth
                text: root.layoutConfirmationPending
                  ? (root.layoutProcessAction === "keep"
                     ? "Keeping…" : "Keep (" + root.layoutConfirmationSeconds + ")")
                  : (root.layoutApplying ? "Applying…" : "Apply")
                enabled: !root.layoutApplying && (root.layoutConfirmationPending || root.layoutDirty)
                  && !(root.layoutConfirmationPending && root.profileKeepBlocked)
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.caption
                bordered: true
                hasCursor: root.cursorActive && root.focusSection === "arrangement"
                           && root.selectedIndex === root.layoutPreview.length + 1
                onClicked: root.primaryLayoutAction()
                onHovered: function(isHovered) {
                  if (!isHovered) return
                  root.cursorActive = true
                  root.focusSection = "arrangement"
                  root.selectedIndex = root.layoutPreview.length + 1
                }
              }
            }
          }

          // ---------- Profiles ----------
          PanelSeparator { foreground: root.bar.foreground }

          ProfileSection {
            width: parent.width
            profiles: root.profiles
            activeProfileId: root.activeProfileId
            anchorOptions: root.anchorOptions
            anchorDisplayName: root.anchorDisplayName
            match: root.profileMatch
            busy: root.profileActionBusy
            confirmationPending: root.layoutConfirmationPending
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            expanded: root.profileSectionOpen
            onToggleRequested: root.profileSectionOpen = !root.profileSectionOpen
            onSelectRequested: function(id) { root.runProfileAction("select", id) }
            onRenameRequested: function(id, name) { root.runProfileAction("rename", id, name) }
            onDuplicateRequested: function(id, name) { root.runProfileAction("duplicate", id, name) }
            onDeleteRequested: function(id) { root.requestProfileDelete(id) }
            onMovedKeepRequested: function(choice, id) { root.keepDisplayLayout(choice, id) }
            onAnchorRequested: function(name) { root.selectAnchorDisplay(name) }
          }

          // ---------- Workspaces ----------
          PanelSeparator {
            visible: root.selectedDisplay
            foreground: root.bar.foreground
          }

          ExpandableSection {
            id: workspacesSection
            width: parent.width
            visible: root.selectedDisplay
            title: "WORKSPACES"
            summary: root.workspaceDirty ? "CHANGES READY" : ""
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            expanded: root.expandedSettingsSection === "workspaces"
            onToggleRequested: root.toggleSettingsSection("workspaces")

            Text {
              width: parent.width
              text: root.workspaceDirty
                ? "Workspace changes are ready — click Apply."
                : "Choose the workspace numbers that belong to this display."
              color: Qt.darker(root.bar.foreground, 1.35)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            Grid {
              id: workspaceGrid
              width: parent.width
              columns: 5
              spacing: Style.spacing.xs

              readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

              Repeater {
                model: root.workspaceNumbers

                Button {
                  required property int modelData
                  required property int index

                  width: workspaceGrid.cellWidth
                  text: modelData === 10 ? "0" : String(modelData)
                  tooltipText: "Toggle workspace "
                    + (modelData === 10 ? "10 (0 key)" : modelData)
                    + " for the selected display"
                  selected: root.workspaceOwner(modelData) === root.selectedMonitorName
                  hasCursor: root.cursorActive && root.focusSection === "workspaces"
                    && root.selectedIndex === index
                  enabled: !root.layoutApplying && !root.layoutConfirmationPending
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(4)
                  verticalPadding: Style.space(6)
                  bordered: true
                  onClicked: root.toggleWorkspaceForSelected(modelData)
                  onHovered: function(isHovered) {
                    if (!isHovered || root.reflowingText) return
                    root.cursorActive = true
                    root.focusSection = "workspaces"
                    root.selectedIndex = index
                  }
                }
              }
            }
          }

          // ---------- Display settings ----------
          PanelSeparator {
            visible: root.selectedDisplay
            foreground: root.bar.foreground
          }

          ExpandableSection {
            id: displaySettingsSection
            width: parent.width
            visible: root.selectedDisplay
            title: "DISPLAY SETTINGS"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            expanded: root.expandedSettingsSection === "display"
            onToggleRequested: root.toggleSettingsSection("display")

            PanelSectionHeader {
              width: parent.width
              text: "RESOLUTION"
              visible: root.resolutionOptions.length > 0
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Dropdown {
              id: resolutionDropdown
              width: parent.width
              visible: root.resolutionOptions.length > 0
              showLabel: false
              options: root.resolutionOptions
              value: root.resolutionValue
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "resolution"
              enabled: !root.layoutApplying && !root.layoutConfirmationPending
              onChanged: function(value) { root.setResolution(value) }
              onHovered: function(isHovered) {
                if (!isHovered || root.reflowingText) return
                root.cursorActive = true
                root.focusSection = "resolution"
                root.selectedIndex = -1
              }
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
            }

            PanelSeparator {
              width: parent.width
              visible: root.resolutionOptions.length > 0
              foreground: root.bar.foreground
            }

            PanelSectionHeader {
              width: parent.width
              text: "ROTATION"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Dropdown {
              id: rotationDropdown
              width: parent.width
              showLabel: false
              options: root.rotationOptions
              value: root.rotationValue
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "rotation"
              enabled: !root.layoutApplying && !root.layoutConfirmationPending
              onChanged: function(value) { root.setRotation(value) }
              onHovered: function(isHovered) {
                if (!isHovered || root.reflowingText) return
                root.cursorActive = true
                root.focusSection = "rotation"
                root.selectedIndex = -1
              }
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
            }

            PanelSeparator {
              width: parent.width
              foreground: root.bar.foreground
            }

            PanelSectionHeader {
              width: parent.width
              text: "REFRESH RATE"
              visible: root.refreshRateOptions.length > 0
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Dropdown {
              id: refreshRateDropdown
              width: parent.width
              visible: root.refreshRateOptions.length > 0
              showLabel: false
              options: root.refreshRateOptions
              value: root.refreshRateValue
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "refreshRate"
              enabled: !root.layoutApplying && !root.layoutConfirmationPending
              onChanged: function(value) { root.setRefreshRate(value) }
              onHovered: function(isHovered) {
                if (!isHovered || root.reflowingText) return
                root.cursorActive = true
                root.focusSection = "refreshRate"
                root.selectedIndex = -1
              }
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
            }

            PanelSeparator {
              width: parent.width
              visible: root.refreshRateOptions.length > 0
              foreground: root.bar.foreground
            }

            PanelSectionHeader {
              width: parent.width
              text: "SCALE"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Grid {
              id: scaleRow
              width: parent.width
              columns: root.scaleValues.length
              spacing: Style.spacing.xs

              readonly property real cellWidth: root.scaleValues.length > 0
                ? (width - spacing * (columns - 1)) / columns
                : 0

              Repeater {
                model: root.scaleValues

                ScalePill {
                  required property string modelData
                  required property int index

                  scaleValue: modelData
                  scaleIndex: index
                  width: scaleRow.cellWidth
                }
              }
            }
          }

          // ---------- Monitors ----------
          PanelSeparator {
            visible: root.displays.length > 0
            foreground: root.bar.foreground
          }

          ConnectedDisplaysSection {
            id: monitorsSection
            width: parent.width
            visible: root.displays.length > 0
            displays: root.displays
            enabledDisplayCount: root.enabledDisplayCount
            transitioning: root.displayTransitioning
            busy: root.layoutApplying || stateProc.running
            identifyActive: root.identifyActive
            cursorActive: root.cursorActive
            focusSection: root.focusSection
            selectedIndex: root.selectedIndex
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            expanded: root.expandedSettingsSection === "monitors"
            onToggleRequested: root.toggleSettingsSection("monitors")
            onIdentifyRequested: root.showIdentifyOverlay()
            onRefreshRequested: root.refresh("manual")
            onRowHovered: function(index) {
              if (root.reflowingText) return
              root.cursorActive = true
              if (index < 0) {
                root.focusSection = "displayActions"
                root.selectedIndex = index === -1 ? 0 : 1
              } else {
                root.focusSection = "monitors"
                root.selectedIndex = index
              }
            }
            onDisplayToggleRequested: function(name, enabled) { root.toggleDisplay(name, enabled) }
          }

          Item {
            width: parent.width
            height: Style.space(4)
          }
        }
      }
    }
  }

  FullScreenArrangement {
    id: expandedWorkspace
    controller: root
    targetScreen: panel.screen
    foreground: root.bar.foreground
    urgent: root.bar.urgent
    fontFamily: root.bar.fontFamily
    onCloseRequested: root.closeExpandedLayout()
  }

  IdentifyOverlay {
    entries: root.identifyEntries
    displays: root.displays
    fontFamily: root.bar.fontFamily
    open: root.identifyActive
  }

  DisplayConfirmationOverlay {
    preferredScreenName: root.confirmationTargetScreenName
    remainingSeconds: root.layoutConfirmationSeconds
    busy: root.layoutApplying
    keepEnabled: !root.profileKeepBlocked
    foreground: root.bar.foreground
    urgent: root.bar.urgent
    fontFamily: root.bar.fontFamily
    open: root.layoutConfirmationPending && root.ownsDisplayConfirmation
    onKeepRequested: root.keepDisplayLayout()
    onRevertRequested: root.revertDisplayLayout()
  }

  ConfirmDialog {
    id: profileDeleteDialog
    parent: keyCatcher
    anchors.fill: parent
    z: 100
    message: "Delete this display profile? The live display layout will not change."
    confirmText: "Delete"
    onCanceled: {
      opened = false
      root.pendingProfileDeleteId = ""
    }
    onConfirmed: {
      opened = false
      root.runProfileAction("delete", root.pendingProfileDeleteId, "confirmed")
      root.pendingProfileDeleteId = ""
    }
  }

  component ScalePill: Button {
    id: pill
    required property string scaleValue
    required property int scaleIndex

    text: root.effectiveScale(scaleValue) + "x"
    fontSize: Style.font.caption
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.sm
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true
    enabled: !root.layoutApplying && !root.layoutConfirmationPending

    active: root.activeScaleIndex() === scaleIndex
    hasCursor: root.cursorActive && root.focusSection === "scale" && root.selectedIndex === scaleIndex

    onClicked: root.setScale(scaleValue)
    onHovered: function(isHovered) {
      if (!isHovered || root.reflowingText) return
      root.cursorActive = true
      root.focusSection = "scale"
      root.selectedIndex = pill.scaleIndex
    }
  }

}
