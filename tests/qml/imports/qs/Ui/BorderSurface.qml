import QtQuick
Rectangle {
  property real padding: 0
  property var borderSpec: ({width: 0, color: "transparent"})
  readonly property real contentLeftInset: padding + border.width
  readonly property real contentRightInset: contentLeftInset
  readonly property real contentTopInset: contentLeftInset
  readonly property real contentBottomInset: contentLeftInset
  border.width: borderSpec.width
  border.color: borderSpec.color
}
