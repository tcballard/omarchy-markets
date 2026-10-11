import QtQuick
Item {
  property string moduleName: ""
  property var bar: null
  property var settings: ({})
  property bool vertical: false
  function setting(name, fallback) {
    return settings[name] !== undefined && settings[name] !== null ? settings[name] : fallback
  }
}
