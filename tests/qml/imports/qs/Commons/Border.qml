pragma Singleton
import QtQuick
QtObject {
  function none() { return {width: 0, color: "transparent"} }
  function controlSpec(state, foreground, accent) { return {width: 1, color: state === "focus" ? accent : foreground} }
}
