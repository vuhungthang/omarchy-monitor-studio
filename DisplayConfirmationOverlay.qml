import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  required property string preferredScreenName
  required property int remainingSeconds
  required property bool busy
  required property var keepPolicy
  required property color foreground
  required property color urgent
  required property string fontFamily
  property bool open: false

  signal keepRequested(string profileChoice, string profileId)
  signal revertRequested()

  readonly property string policyKind: String((keepPolicy || {}).kind || "keep")
  readonly property string policyProfileId: String((keepPolicy || {}).profileId || "")
  readonly property string policyMessage: String((keepPolicy || {}).message || "")

  function screenNamed(name) {
    var wanted = String(name || "")
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var candidate = Quickshell.screens[i]
      if (candidate && String(candidate.name || "") === wanted) return candidate
    }
    return null
  }

  function fallbackScreen() {
    var candidates = []
    for (var i = 0; i < Quickshell.screens.length; i++) {
      if (Quickshell.screens[i]) candidates.push(Quickshell.screens[i])
    }
    candidates.sort(function(left, right) {
      return String(left.name || "").localeCompare(String(right.name || ""))
    })
    return candidates.length > 0 ? candidates[0] : null
  }

  readonly property var targetScreen: screenNamed(preferredScreenName) || fallbackScreen()

  PanelWindow {
    id: confirmationWindow

    screen: root.targetScreen
    visible: root.open && root.targetScreen !== null
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region { item: card }
    WlrLayershell.namespace: "omarchy-monitor-confirmation"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    BorderSurface {
      id: card

      anchors.centerIn: parent
      width: Math.min(Style.space(380), Math.max(Style.space(280), parent.width - Style.space(32)))
      height: content.implicitHeight + Style.space(36)
      radius: Style.cornerRadius
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border,
                                     Math.max(1, Style.normalBorderWidth))

      Column {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(18)
        anchors.rightMargin: Style.space(18)
        spacing: Style.space(10)

        Text {
          width: parent.width
          text: "Keep these display settings?"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          width: parent.width
          text: "Reverting automatically in " + root.remainingSeconds + " seconds."
          color: Qt.darker(root.foreground, 1.35)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
        }

        Text {
          width: parent.width
          visible: root.policyKind !== "keep" && root.policyMessage !== ""
          text: root.policyMessage
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
        }

        Row {
          width: parent.width
          visible: root.policyKind === "keep"
          spacing: Style.spacing.xs
          readonly property real cellWidth: (width - spacing) / 2

          Button {
            width: parent.cellWidth
            text: root.busy ? "Working…" : "Revert"
            focusable: true
            bordered: true
            enabled: !root.busy
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.revertRequested()
          }

          Button {
            width: parent.cellWidth
            text: root.busy ? "Working…" : "Keep (" + root.remainingSeconds + ")"
            focusable: true
            bordered: true
            selected: true
            enabled: !root.busy
            foreground: root.foreground
            accent: root.urgent
            fontFamily: root.fontFamily
            onClicked: root.keepRequested("", "")
          }
        }

        Row {
          width: parent.width
          visible: root.policyKind === "choose-profile"
          spacing: Style.spacing.xs
          readonly property real cellWidth: (width - spacing) / 2

          Button {
            width: parent.cellWidth
            text: root.busy ? "Working…" : "Update profile"
            focusable: true
            bordered: true
            selected: true
            enabled: !root.busy && root.policyProfileId !== ""
            foreground: root.foreground
            accent: root.urgent
            fontFamily: root.fontFamily
            onClicked: root.keepRequested("update-profile", root.policyProfileId)
          }

          Button {
            width: parent.cellWidth
            text: root.busy ? "Working…" : "Save as new"
            focusable: true
            bordered: true
            enabled: !root.busy && root.policyProfileId !== ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.keepRequested("fork-profile", root.policyProfileId)
          }
        }

        Button {
          width: parent.width
          visible: root.policyKind !== "keep"
          text: root.busy ? "Working…" : "Revert"
          focusable: true
          bordered: true
          enabled: !root.busy
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.revertRequested()
        }
      }
    }
  }
}
