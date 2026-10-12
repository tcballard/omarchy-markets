import QtQuick
import qs.Commons
import qs.Commons as Omarchy
import "ChartModel.js" as ChartModel
import "MarketModel.js" as MarketModel

FocusScope {
  id: root
  property alias points: plot.points
  property alias timestamps: plot.timestamps
  property alias referenceValue: plot.referenceValue
  property alias lineColor: plot.lineColor
  property alias referenceColor: plot.referenceColor
  property color foreground: Omarchy.Color.popups.text
  property string fontFamily: Style.font.family
  property string currency: ""
  property string instrumentType: ""
  property string symbol: ""
  property string seriesKey: ""
  property real plotHeight: Style.space(160)
  property int keyboardIndex: -1
  readonly property bool canInspect: plot.samples.length >= 2
  readonly property real pointerX: hover.point.position.x
  readonly property int inspectedIndex: !canInspect ? -1
    : keyboardIndex >= 0 && keyboardIndex < plot.samples.length ? keyboardIndex
    : hover.hovered ? ChartModel.nearest(plot.samples, (pointerX - plot.inset) / plot.chartWidth) : -1
  readonly property var inspectedSample: inspectedIndex >= 0 ? plot.samples[inspectedIndex] : null
  readonly property string readoutText: inspectedSample
    ? MarketModel.formatQuotePrice(inspectedSample.value,
        {currency: currency, instrumentType: instrumentType, symbol: symbol})
      + " · " + ChartModel.timestampLabel(inspectedSample.time)
    : "Hover for values or press I to inspect"
  signal returnFocus()
  signal leaveView()

  implicitHeight: plot.height + Style.space(6) + readout.height
  height: implicitHeight
  activeFocusOnTab: canInspect
  Accessible.role: Accessible.Graphic
  Accessible.name: "Price history for " + symbol
  Accessible.description: readoutText + ". Left and Right move between points. Home and End jump. Escape returns to the panel."
  onPointerXChanged: if (hover.hovered) keyboardIndex = -1
  onSeriesKeyChanged: keyboardIndex = -1
  onActiveFocusChanged: if (!activeFocus) keyboardIndex = -1
  onVisibleChanged: if (!visible) {
    keyboardIndex = -1
    if (activeFocus) root.returnFocus()
  }
  onCanInspectChanged: if (!canInspect && activeFocus) finishInspection()

  function focusChart() {
    if (!canInspect) return
    keyboardIndex = plot.samples.length - 1
    forceActiveFocus()
  }

  function finishInspection() {
    keyboardIndex = -1
    root.returnFocus()
  }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      if (event.key === Qt.Key_Escape) root.leaveView()
      finishInspection()
      event.accepted = true
    } else if (canInspect && (event.key === Qt.Key_Left || event.key === Qt.Key_Right
        || event.key === Qt.Key_Home || event.key === Qt.Key_End)) {
      var index = inspectedIndex >= 0 ? inspectedIndex : plot.samples.length - 1
      if (event.key === Qt.Key_Home) index = 0
      else if (event.key === Qt.Key_End) index = plot.samples.length - 1
      else index += event.key === Qt.Key_Left ? -1 : 1
      keyboardIndex = Math.max(0, Math.min(plot.samples.length - 1, index))
      event.accepted = true
    }
  }

  Sparkline {
    id: plot
    objectName: "historyPlot"
    width: parent.width
    height: root.plotHeight
    clip: true
    onSamplesChanged: root.keyboardIndex = -1

    HoverHandler {
      id: hover
      enabled: root.canInspect
      cursorShape: Qt.CrossCursor
      onHoveredChanged: if (hovered) root.keyboardIndex = -1
    }

    TapHandler {
      enabled: root.canInspect
      onTapped: {
        root.keyboardIndex = ChartModel.nearest(plot.samples, (point.position.x - plot.inset) / plot.chartWidth)
        root.forceActiveFocus()
      }
    }

    Rectangle {
      anchors.fill: parent
      color: "transparent"
      border.color: root.foreground
      border.width: root.activeFocus ? 1 : 0
    }

    Rectangle {
      visible: root.inspectedSample !== null
      x: visible ? plot.xFor(root.inspectedIndex) : 0
      y: plot.inset
      width: 1
      height: plot.chartHeight
      color: root.foreground
    }

    Rectangle {
      visible: root.inspectedSample !== null
      width: Style.space(7)
      height: width
      radius: width / 2
      x: visible ? plot.xFor(root.inspectedIndex) - width / 2 : 0
      y: visible ? plot.yFor(root.inspectedSample.value) - height / 2 : 0
      color: root.foreground
    }
  }

  Text {
    id: readout
    objectName: "historyReadout"
    y: plot.height + Style.space(6)
    width: parent.width
    // Reserve two lines so inspecting points never moves the panel underneath the pointer.
    height: readoutMetrics.height * 2
    textFormat: Text.PlainText
    text: root.readoutText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
    Accessible.name: text
  }

  FontMetrics { id: readoutMetrics; font: readout.font }
}
