import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  required property var entries
  required property var displays
  required property string fontFamily
  property bool open: false

  function entryFor(name) {
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] && entries[i].name === name) return entries[i]
    }
    return null
  }

  function displayFor(name) {
    for (var i = 0; i < displays.length; i++) {
      if (displays[i] && displays[i].name === name) return displays[i]
    }
    return null
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: identifyWindow
      required property var modelData
      readonly property var entry: root.entryFor(String(modelData.name || ""))

      screen: modelData
      visible: root.open && entry !== null
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}
      WlrLayershell.namespace: "omarchy-monitor-identify"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Rectangle {
        anchors.centerIn: parent
        width: Math.max(240, displayLabel.implicitWidth + 48)
        height: Math.max(150, displayLabel.implicitHeight + connectorLabel.implicitHeight + 48)
        radius: 24
        color: Qt.rgba(0.04, 0.05, 0.07, 0.94)
        border.width: 2
        border.color: "white"

        Column {
          anchors.centerIn: parent
          spacing: 4

          Text {
            id: displayLabel
            width: Math.max(1, identifyWindow.width - 48)
            anchors.horizontalCenter: parent.horizontalCenter
            text: identifyWindow.entry
              ? Model.displayLabel(root.displayFor(identifyWindow.entry.name))
              : ""
            textFormat: Text.PlainText
            color: "white"
            font.family: root.fontFamily
            font.pixelSize: 28
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
          }

          Text {
            id: connectorLabel
            anchors.horizontalCenter: parent.horizontalCenter
            text: identifyWindow.entry ? identifyWindow.entry.name : ""
            textFormat: Text.PlainText
            color: Qt.rgba(1, 1, 1, 0.72)
            font.family: root.fontFamily
            font.pixelSize: 18
            font.bold: true
          }
        }
      }
    }
  }
}
