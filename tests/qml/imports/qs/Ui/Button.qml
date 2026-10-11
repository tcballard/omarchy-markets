import QtQuick
Rectangle {
  id: root
  property string text: ""
  property string tooltipText: ""
  property string iconText: ""
  property bool iconSpinning: false
  property color foreground: "white"
  property bool bordered: false
  property bool selected: false
  property bool focusable: false
  property real horizontalPadding: 10
  property real verticalPadding: 6
  signal clicked()
  implicitWidth: label.implicitWidth + horizontalPadding * 2
  implicitHeight: label.implicitHeight + verticalPadding * 2
  color: selected ? "#505050" : "#303030"
  border.width: bordered || activeFocus ? 1 : 0
  border.color: foreground
  activeFocusOnTab: focusable
  Keys.onSpacePressed: clicked()
  Keys.onReturnPressed: clicked()
  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    textFormat: Text.PlainText
    color: root.foreground
    font.pixelSize: 12
  }
  MouseArea { anchors.fill: parent; onClicked: root.clicked() }
}
