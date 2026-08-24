import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "TopologyModel.js" as Topology

ExpandableSection {
  id: root

  required property var displays
  required property int enabledDisplayCount
  required property bool transitioning
  required property bool busy
  required property bool cursorActive
  required property string focusSection
  required property int selectedIndex
  property bool identifyActive: false

  signal identifyRequested()
  signal refreshRequested()
  signal displayToggleRequested(string name, bool enabled)
  signal rowHovered(int index)

  title: "CONNECTED DISPLAYS"
  summary: transitioning ? "ENUMERATING…"
    : enabledDisplayCount + " OF " + displays.length + " ACTIVE"
  contentSpacing: Style.space(10)

  Row {
    width: parent.width
    spacing: Style.spacing.xs
    readonly property real cellWidth: (width - spacing) / 2

    Button {
      width: parent.cellWidth
      text: root.identifyActive ? "Identifying…" : "Identify"
      focusable: true
      bordered: true
      enabled: !root.busy && root.enabledDisplayCount > 0
      hasCursor: root.cursorActive && root.focusSection === "displayActions"
        && root.selectedIndex === 0
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.identifyRequested()
      onHovered: function(hovered) { if (hovered) root.rowHovered(-1) }
    }

    Button {
      width: parent.cellWidth
      text: root.transitioning ? "Refresh now" : "Refresh"
      focusable: true
      bordered: true
      enabled: !root.busy
      hasCursor: root.cursorActive && root.focusSection === "displayActions"
        && root.selectedIndex === 1
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.refreshRequested()
      onHovered: function(hovered) { if (hovered) root.rowHovered(-2) }
    }
  }

  Text {
    visible: root.transitioning
    width: parent.width
    text: "Display connections are changing. Waiting for a stable hardware snapshot."
    textFormat: Text.PlainText
    color: Qt.darker(root.foreground, 1.35)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
  }

  Repeater {
    model: root.displays

    CursorSurface {
      id: monitorRow
      required property var modelData
      required property int index
      readonly property bool canToggle: modelData
        && (!modelData.enabled || root.enabledDisplayCount > 1)

      width: parent.width
      hasCursor: root.cursorActive && root.focusSection === "monitors"
        && root.selectedIndex === index
      current: modelData && modelData.focused
      foreground: root.foreground
      fill: Style.hoverFillFor(root.foreground, Color.accent)
      currentFill: Style.selectedFillFor(root.foreground, Color.accent)
      implicitHeight: monitorInner.implicitHeight + Style.spacing.xl
      opacity: canToggle ? 1.0 : 0.55

      Row {
        id: monitorInner
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)
        spacing: Style.space(8)

        Text {
          text: "󰍹"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          width: Style.space(22)
          horizontalAlignment: Text.AlignHCenter
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          text: Model.displayLabel(monitorRow.modelData) + " · " + monitorRow.modelData.name
            + " · " + Topology.transportLabel(monitorRow.modelData.transport)
            + (root.transitioning ? " · transitioning"
               : (monitorRow.modelData.enabled ? " · active" : " · disabled"))
            + (monitorRow.modelData.focused ? " · focused" : "")
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width - Style.space(22) - Style.space(14) - Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          text: monitorRow.modelData.enabled ? "󰄬" : "󰅖"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          width: Style.space(14)
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: monitorRow.canToggle ? Qt.PointingHandCursor : Qt.ArrowCursor
        onContainsMouseChanged: if (containsMouse) root.rowHovered(monitorRow.index)
        onClicked: if (monitorRow.canToggle)
          root.displayToggleRequested(monitorRow.modelData.name, monitorRow.modelData.enabled)
      }
    }
  }
}
