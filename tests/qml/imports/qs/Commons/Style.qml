pragma Singleton
import QtQuick
QtObject {
  property var font: ({family: "DejaVu Sans", caption: 11, body: 14, bodySmall: 12, title: 16, heading: 20})
  property var bar: ({iconSlot: 28})
  property int cornerRadius: 0
  function space(value) { return value }
  function spaceReal(value) { return value }
  function normalFillFor(f, a, u) { return "#303030" }
  function hoverFillFor(f, a, u) { return "#404040" }
  function selectedFillFor(f, a, u) { return "#505050" }
}
