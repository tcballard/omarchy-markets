import QtQuick
Item {
  id: root
  property var bar: null
  property string text: ""
  property bool labelVisible: true
  property bool hasVisualContent: false
  property real fixedWidth: -1
  property real fixedHeight: -1
  property real horizontalMargin: 8
  property real verticalPadding: 6
  property color foreground: "white"
  property bool dimmed: false
  property string tooltipText: ""
  property string fontFamily: "DejaVu Sans"
  property int fontSize: 12
  readonly property real scaledHorizontalMargin: horizontalMargin
  readonly property bool hovered: mouse.containsMouse
  signal pressed(int mouseButton)
  implicitWidth: fixedWidth >= 0 ? fixedWidth : 220
  implicitHeight: fixedHeight >= 0 ? fixedHeight : 28
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onPressed: function(event) { root.pressed(event.button) }
  }
}
