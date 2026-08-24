import QtQuick
import qs.Commons
import qs.Ui

ExpandableSection {
  id: root

  required property var profiles
  required property string activeProfileId
  required property var anchorOptions
  required property string anchorDisplayName
  required property var match
  property bool busy: false
  property bool confirmationPending: false

  signal selectRequested(string profileId)
  signal renameRequested(string profileId, string name)
  signal duplicateRequested(string profileId, string name)
  signal deleteRequested(string profileId)
  signal movedKeepRequested(string choice, string profileId)
  signal anchorRequested(string name)

  title: "PROFILES"
  summary: String((match || {}).status || "new").toUpperCase()

  Text {
    width: parent.width
    text: {
      var status = String((root.match || {}).status || "new")
      if (status === "exact") return "This display set exactly matches a saved profile."
      if (status === "moved") return "A known display moved connectors. Review its modes before keeping."
      if (status === "weak") return "The match is uncertain. Identify the displays before keeping."
      if (status === "ambiguous") return "Identical displays cannot be assigned safely yet."
      return "This is a new display set. Existing profiles will not be changed."
    }
    textFormat: Text.PlainText
    color: Qt.darker(root.foreground, 1.35)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
  }

  Text {
    width: parent.width
    visible: root.profiles.length === 0
    text: "Keep a display layout to create your first profile."
    textFormat: Text.PlainText
    color: Qt.darker(root.foreground, 1.35)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
  }

  PanelSectionHeader {
    width: parent.width
    text: "ANCHOR DISPLAY"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Dropdown {
    width: parent.width
    showLabel: false
    options: root.anchorOptions
    value: root.anchorDisplayName
    enabled: !root.busy && !root.confirmationPending && root.anchorOptions.length > 0
    foreground: root.foreground
    fontFamily: root.fontFamily
    onChanged: function(value) { root.anchorRequested(String(value)) }
  }

  Text {
    width: parent.width
    text: "Saved positions are measured from this display, so screens may have negative coordinates."
    textFormat: Text.PlainText
    color: Qt.darker(root.foreground, 1.35)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
  }

  Repeater {
    model: root.profiles

    BorderSurface {
      required property var modelData
      width: parent.width
      implicitHeight: profileRow.implicitHeight + Style.spacing.controlPaddingY * 2
      color: modelData.id === root.activeProfileId
        ? Style.selectedFillFor(root.foreground, Color.accent)
        : Style.normalFillFor(root.foreground)
      borderSpec: Border.controlSpec(modelData.id === root.activeProfileId ? "selected" : "normal",
                                     root.foreground, Color.accent)
      radius: Style.cornerRadius

      Row {
        id: profileRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Style.spacing.controlPaddingX
        spacing: Style.spacing.xs

        TextField {
          width: Math.max(Style.space(120), parent.width - actions.implicitWidth - parent.spacing)
          text: String(modelData.name || "")
          enabled: !root.busy
          foreground: root.foreground
          onAccepted: if (text !== modelData.name) root.renameRequested(modelData.id, text)
        }

        Row {
          id: actions
          spacing: Style.spacing.xs

          PanelActionButton {
            iconText: "󰄬"
            tooltipText: "Select profile"
            focusable: true
            enabled: !root.busy && modelData.id !== root.activeProfileId
            foreground: root.foreground
            onClicked: root.selectRequested(modelData.id)
          }
          PanelActionButton {
            iconText: "󰆏"
            tooltipText: "Duplicate profile"
            focusable: true
            enabled: !root.busy
            foreground: root.foreground
            onClicked: root.duplicateRequested(modelData.id, modelData.name + " Copy")
          }
          PanelActionButton {
            iconText: "󰆴"
            tooltipText: "Delete profile"
            focusable: true
            enabled: !root.busy
            foreground: root.foreground
            hoverColor: Color.urgent
            onClicked: root.deleteRequested(modelData.id)
          }
        }
      }
    }
  }

  Row {
    width: parent.width
    visible: root.confirmationPending && String((root.match || {}).status) === "moved"
    spacing: Style.spacing.xs
    readonly property real cellWidth: (width - spacing) / 2

    Button {
      width: parent.cellWidth
      text: "Update profile"
      focusable: true
      bordered: true
      enabled: !root.busy
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.movedKeepRequested("update-profile", root.match.profileId)
    }
    Button {
      width: parent.cellWidth
      text: "Save as new"
      focusable: true
      bordered: true
      enabled: !root.busy
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.movedKeepRequested("fork-profile", root.match.profileId)
    }
  }
}
