pragma Singleton
import QtQuick
QtObject {
  property color foreground: "#eeeeee"
  property color background: "#202020"
  property color muted: "#cccccc"
  property color accent: "#88bbff"
  property color urgent: "#ff6666"
  property QtObject popups: QtObject {
    property color text: "#eeeeee"
    property color background: "#202020"
  }
}
