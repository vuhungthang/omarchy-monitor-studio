import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root

  required property bool internalAvailable
  required property bool externalAvailable
  required property bool extendAvailable
  required property bool duplicateAvailable
  required property string duplicateSummary
  required property string currentPreset
  required property color foreground
  required property string fontFamily
  required property bool cursorActive
  required property string focusSection
  required property int selectedIndex
  property bool busy: false

  signal presetRequested(string preset)

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(6)

  PanelSectionHeader {
    text: "MULTIPLE DISPLAYS"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Row {
    width: parent.width
    spacing: Style.spacing.xs
    readonly property real cellWidth: (width - spacing * 2) / 3

    Button {
      width: parent.cellWidth
      text: "Internal only"
      focusable: true
      bordered: true
      active: root.currentPreset === "internal"
      hasCursor: root.cursorActive && root.focusSection === "presets" && root.selectedIndex === 0
      enabled: !root.busy && root.internalAvailable
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.presetRequested("internal")
    }

    Button {
      width: parent.cellWidth
      text: "Extend"
      focusable: true
      bordered: true
      active: root.currentPreset === "extend"
      hasCursor: root.cursorActive && root.focusSection === "presets" && root.selectedIndex === 1
      enabled: !root.busy && root.extendAvailable
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.presetRequested("extend")
    }

    Button {
      width: parent.cellWidth
      text: "External only"
      focusable: true
      bordered: true
      active: root.currentPreset === "external"
      hasCursor: root.cursorActive && root.focusSection === "presets" && root.selectedIndex === 2
      enabled: !root.busy && root.externalAvailable
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.presetRequested("external")
    }
  }

  Button {
    width: parent.width
    text: "Duplicate"
    focusable: true
    bordered: true
    active: root.currentPreset === "duplicate"
    hasCursor: root.cursorActive && root.focusSection === "presets" && root.selectedIndex === 3
    enabled: !root.busy && root.duplicateAvailable
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: root.presetRequested("duplicate")
  }

  Text {
    width: parent.width
    text: root.duplicateSummary
    textFormat: Text.PlainText
    color: Qt.darker(root.foreground, 1.35)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
  }
}
