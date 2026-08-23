import QtQuick
import qs.Ui
import qs.Commons

Column {
  id: section

  required property string title
  required property color foreground
  required property string fontFamily
  property string summary: ""
  property bool expanded: false
  property real contentSpacing: Style.space(8)
  default property alias sectionContent: body.data

  signal toggleRequested()

  width: parent ? parent.width : implicitWidth
  spacing: expanded ? Style.space(8) : 0

  Button {
    width: parent.width
    text: section.title
    iconText: section.expanded ? "󰅀" : "󰅂"
    tooltipText: (section.expanded ? "Collapse " : "Expand ")
      + section.title.toLowerCase()
    foreground: section.foreground
    fontFamily: section.fontFamily
    fontSize: Style.font.caption
    iconSize: Style.font.body
    horizontalPadding: Style.space(8)
    verticalPadding: Style.space(7)
    leftAlign: true
    bordered: true
    selected: section.expanded
    focusable: true
    onClicked: section.toggleRequested()

    Text {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, parent.width * 0.56)
      text: section.summary
      visible: text !== ""
      color: Qt.darker(section.foreground, 1.35)
      font.family: section.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
    }
  }

  Column {
    id: body
    width: parent.width
    spacing: section.contentSpacing
    visible: section.expanded
  }
}
