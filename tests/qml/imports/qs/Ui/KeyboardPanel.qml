import QtQuick
Item {
  id: root
  default property alias contentItem: contentHolder.children
  property var anchorItem: null
  property var owner: null
  property var bar: null
  property bool open: false
  property bool centerOnBar: false
  property var focusTarget: null
  property real contentWidth: 620
  property real contentHeight: 600
  property real availableCardHeight: 680
  readonly property real verticalContentInset: 24
  property Item testContentHolder: Item {
    id: contentHolder
    parent: root
    anchors.fill: parent
    anchors.margins: root.verticalContentInset / 2
  }
  width: contentWidth
  height: contentHeight
  visible: open
  function fittedContentWidth(value) { return Math.min(780, value) }
  function fittedContentHeight(value) { return Math.min(availableCardHeight, value + verticalContentInset) }
  onOpenChanged: if (open && focusTarget) focusTarget.forceActiveFocus()
}
