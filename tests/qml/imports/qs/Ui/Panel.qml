import QtQuick
Item {
  property string moduleName: ""
  property bool manageIpc: true
  property var bar: null
  property var settings: ({})
  readonly property bool opened: controller.opened
  readonly property bool popoutSwitchClosing: false
  property QtObject controller: QtObject {
    property bool opened: false
    function show() { opened = true }
    function hide() { opened = false }
  }
  function closeForPopoutSwitch() { controller.hide() }
}
