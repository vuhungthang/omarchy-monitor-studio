import QtQuick
import qs.Ui
import qs.Commons

BorderSurface {
  id: tile

  required property var display
  required property int tileIndex
  required property color foreground
  required property string fontFamily
  property bool selected: false
  property bool hasCursor: false
  property bool editing: false
  property bool interactionEnabled: true
  property var workspaceNumbers: []
  readonly property int workspaceBadgeLimit: width >= Style.space(104) ? 5
    : (width >= Style.space(70) ? 3 : 2)
  readonly property var visibleWorkspaceNumbers: workspaceNumbers.slice(0, workspaceBadgeLimit)
  readonly property int hiddenWorkspaceCount: Math.max(0,
    workspaceNumbers.length - visibleWorkspaceNumbers.length)
  property real dragStartX: 0
  property real dragStartY: 0
  property real stagedDropX: 0
  property real stagedDropY: 0
  property bool dragStarted: false

  signal dragBegan()
  signal dragFinished(string name, real canvasX, real canvasY)
  signal pointerSelected()
  signal monitorSelected()

  x: drag.active ? dragStartX + drag.activeTranslation.x : display.x
  y: drag.active ? dragStartY + drag.activeTranslation.y : display.y
  width: display.width
  height: display.height
  clip: true
  z: drag.active || editing || selected ? 2 : 1
  radius: Style.cornerRadius
  color: selected
    ? Style.selectedFillFor(foreground, Color.accent)
    : (hasCursor || display.focused
       ? Style.hoverFillFor(foreground, Color.accent) : "transparent")
  borderSpec: Border.controlSpec(
    drag.active || editing || selected || hasCursor ? "hover-cursor" : "normal",
    foreground, Color.accent)

  Column {
    anchors.centerIn: parent
    width: Math.max(1, parent.width - Style.space(8))
    spacing: Style.space(1)

    Text {
      width: parent.width
      text: tile.display.label || tile.display.name
      color: tile.foreground
      font.family: tile.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      text: tile.display.name + " · "
        + Math.round(tile.display.logicalWidth) + " × " + Math.round(tile.display.logicalHeight)
      color: Qt.darker(tile.foreground, 1.35)
      font.family: tile.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(2)
      visible: tile.workspaceNumbers.length > 0 && tile.height >= Style.space(52)

      Repeater {
        model: tile.visibleWorkspaceNumbers

        BorderSurface {
          required property int modelData

          width: Style.space(18)
          height: Style.space(16)
          radius: height / 2
          color: Style.normalFillFor(tile.foreground)
          borderSpec: Border.controlSpec("normal", tile.foreground, Color.accent)

          Text {
            anchors.centerIn: parent
            text: modelData === 10 ? "0" : String(modelData)
            color: tile.foreground
            font.family: tile.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }

      BorderSurface {
        visible: tile.hiddenWorkspaceCount > 0
        width: Style.space(24)
        height: Style.space(16)
        radius: height / 2
        color: Style.normalFillFor(tile.foreground)
        borderSpec: Border.controlSpec("normal", tile.foreground, Color.accent)

        Text {
          anchors.centerIn: parent
          text: "+" + tile.hiddenWorkspaceCount
          color: tile.foreground
          font.family: tile.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
    }
  }

  HoverHandler {
    cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    onHoveredChanged: if (hovered) tile.pointerSelected()
  }

  TapHandler {
    onTapped: {
      tile.pointerSelected()
      tile.monitorSelected()
    }
  }

  DragHandler {
    id: drag
    enabled: tile.interactionEnabled
    target: null
    cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    onActiveChanged: {
      if (active) {
        tile.dragStarted = true
        tile.dragBegan()
        tile.dragStartX = tile.display.x
        tile.dragStartY = tile.display.y
        tile.stagedDropX = tile.dragStartX
        tile.stagedDropY = tile.dragStartY
        tile.pointerSelected()
        tile.monitorSelected()
      } else if (tile.dragStarted) {
        tile.dragFinished(tile.display.name, tile.stagedDropX, tile.stagedDropY)
        tile.dragStarted = false
      }
    }
    onActiveTranslationChanged: if (active && tile.dragStarted) {
      tile.stagedDropX = tile.dragStartX + activeTranslation.x
      tile.stagedDropY = tile.dragStartY + activeTranslation.y
    }
  }
}
