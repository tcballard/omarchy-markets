import QtQuick
Item {
  property var anchorItem: null
  property var owner: null
  property var bar: null
  property bool open: false
  property bool centerOnBar: false
  property var focusTarget: null
  property real contentWidth: 620
  property real contentHeight: 600
  width: contentWidth
  height: contentHeight
  visible: open
  function fittedContentWidth(value) { return Math.min(780, value) }
  function fittedContentHeight(value) { return Math.min(680, value) }
  onOpenChanged: if (open && focusTarget) focusTarget.forceActiveFocus()
}
