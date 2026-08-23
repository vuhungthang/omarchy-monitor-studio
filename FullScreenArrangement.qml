import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Ui
import qs.Commons

PanelWindow {
  id: overlay

  required property var controller
  required property var targetScreen
  required property color foreground
  required property color urgent
  required property string fontFamily
  property alias canvasItem: arrangementCanvas

  signal closeRequested()

  visible: controller.expandedLayoutOpen
  screen: targetScreen
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  anchors { top: true; bottom: true; left: true; right: true }

  WlrLayershell.namespace: "omarchy-monitor-arrangement"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: visible
    ? WlrKeyboardFocus.Exclusive
    : WlrKeyboardFocus.None

  onVisibleChanged: if (visible) {
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
      controller.refitDisplayLayout()
    })
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.78)

    MouseArea {
      anchors.fill: parent
      onClicked: overlay.closeRequested()
    }
  }

  BorderSurface {
    id: workspace
    anchors.fill: parent
    anchors.margins: Style.space(24)
    color: Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border,
                                   Math.max(1, Style.space(2)))
    radius: Style.cornerRadius

    MouseArea { anchors.fill: parent; onClicked: {} }

    Item {
      id: keyCatcher
      anchors.fill: parent
      anchors.margins: Style.space(20)
      focus: true

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          overlay.closeRequested()
          event.accepted = true
        } else if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
          controller.toggleWorkspaceForSelected(
            event.key === Qt.Key_0 ? 10 : event.key - Qt.Key_0)
          event.accepted = true
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          var backwards = event.key === Qt.Key_Backtab
            || (event.modifiers & Qt.ShiftModifier)
          controller.selectAdjacentDisplay(backwards ? -1 : 1)
          event.accepted = true
        } else if (event.key === Qt.Key_Left) {
          controller.nudgeSelectedDisplay(-1, 0)
          event.accepted = true
        } else if (event.key === Qt.Key_Right) {
          controller.nudgeSelectedDisplay(1, 0)
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          controller.nudgeSelectedDisplay(0, -1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          controller.nudgeSelectedDisplay(0, 1)
          event.accepted = true
        }
      }

      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(54)

        Column {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            text: "Arrange Displays"
            color: overlay.foreground
            font.family: overlay.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            text: controller.enabledDisplayCount + " displays · Drag each one to match your desk"
            color: Qt.darker(overlay.foreground, 1.35)
            font.family: overlay.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Button {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "Done"
          foreground: overlay.foreground
          fontFamily: overlay.fontFamily
          fontSize: Style.font.caption
          bordered: true
          onClicked: overlay.closeRequested()
        }
      }

      Item {
        id: workspacePicker
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(52)

        Column {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            text: "Workspaces"
            color: overlay.foreground
            font.family: overlay.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Text {
            text: controller.selectedDisplay
              ? "Assign to " + controller.selectedDisplay.label
              : "Select a display"
            textFormat: Text.PlainText
            color: Qt.darker(overlay.foreground, 1.35)
            font.family: overlay.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xs

          Repeater {
            model: controller.workspaceNumbers

            Button {
              required property int modelData

              width: Style.space(38)
              text: modelData === 10 ? "0" : String(modelData)
              tooltipText: "Toggle workspace "
                + (modelData === 10 ? "10 (0 key)" : modelData)
                + " for the selected display"
              selected: controller.workspaceOwner(modelData)
                === controller.selectedMonitorName
              enabled: controller.selectedDisplay && !controller.layoutApplying
                && !controller.layoutConfirmationPending
              foreground: overlay.foreground
              fontFamily: overlay.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(4)
              verticalPadding: Style.space(6)
              bordered: true
              onClicked: controller.toggleWorkspaceForSelected(modelData)
            }
          }
        }
      }

      BorderSurface {
        id: arrangementCanvas
        anchors.top: workspacePicker.bottom
        anchors.bottom: footer.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Style.space(12)
        anchors.bottomMargin: Style.space(12)
        clip: true
        radius: Style.cornerRadius
        color: Style.normalFillFor(overlay.foreground)
        borderSpec: Border.controlSpec("normal", overlay.foreground, Color.accent)

        onWidthChanged: if (overlay.visible) Qt.callLater(controller.refitDisplayLayout)
        onHeightChanged: if (overlay.visible) Qt.callLater(controller.refitDisplayLayout)

        Repeater {
          model: controller.layoutPreview

          DisplayLayoutTile {
            required property var modelData
            required property int index

            display: modelData
            tileIndex: index
            foreground: overlay.foreground
            fontFamily: overlay.fontFamily
            workspaceNumbers: controller.workspacesForMonitor(modelData.name)
            selected: modelData.name === controller.selectedMonitorName
            hasCursor: controller.cursorActive
              && controller.focusSection === "arrangement"
              && controller.selectedIndex === index
            editing: controller.arrangementEditing
              && controller.focusSection === "arrangement"
              && controller.selectedIndex === index
            interactionEnabled: !controller.layoutConfirmationPending
              && !controller.layoutApplying
            onDragBegan: controller.beginDisplayDrag()
            onDragFinished: function(name, canvasX, canvasY) {
              controller.finishDisplayDrag(name, canvasX, canvasY)
            }
            onPointerSelected: {
              controller.cursorActive = true
              controller.focusSection = "arrangement"
              controller.selectedIndex = index
              if (dragStarted) controller.arrangementEditing = false
            }
            onMonitorSelected: controller.selectedMonitorName = modelData.name
          }
        }
      }

      Item {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.space(48)

        Text {
          anchors.left: parent.left
          anchors.right: actions.left
          anchors.rightMargin: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
          text: {
            if (controller.layoutConfirmationPending)
              return "Keep these display settings? Reverting in "
                + controller.layoutConfirmationSeconds + " seconds."
            if (controller.layoutError !== "") return controller.layoutError
            return controller.layoutDirty
              ? "Display or workspace changes are ready — click Apply."
              : "Tab selects · 0–9 assigns workspaces · Arrow keys nudge · Drag to adjust"
          }
          color: controller.layoutError !== "" ? overlay.urgent : overlay.foreground
          font.family: overlay.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Row {
          id: actions
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xs

          Button {
            width: Style.space(110)
            text: controller.layoutConfirmationPending
              ? (controller.layoutProcessAction === "revert" ? "Reverting…" : "Revert")
              : "Reset"
            enabled: !controller.layoutApplying
              && (controller.layoutConfirmationPending || controller.layoutDirty)
            foreground: overlay.foreground
            fontFamily: overlay.fontFamily
            fontSize: Style.font.caption
            bordered: true
            onClicked: controller.secondaryLayoutAction()
          }

          Button {
            width: Style.space(110)
            text: controller.layoutConfirmationPending
              ? (controller.layoutProcessAction === "keep"
                 ? "Keeping…" : "Keep (" + controller.layoutConfirmationSeconds + ")")
              : (controller.layoutApplying ? "Applying…" : "Apply")
            enabled: !controller.layoutApplying
              && (controller.layoutConfirmationPending || controller.layoutDirty)
            foreground: overlay.foreground
            fontFamily: overlay.fontFamily
            fontSize: Style.font.caption
            bordered: true
            onClicked: controller.primaryLayoutAction()
          }
        }
      }
    }
  }
}
