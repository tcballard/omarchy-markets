import QtQuick
import qs.Commons
import "ChartModel.js" as ChartModel

// Lightweight domain chart: a thin line and subtle area fill. Direction is
// also conveyed by signed text elsewhere; color is never the sole signal.
Canvas {
  id: root

  property var points: []
  property var timestamps: []
  property color lineColor: Color.accent
  property color gridColor: Util.alpha(Color.muted, 0.20)
  property color referenceColor: Util.alpha(Color.muted, 0.48)
  property real lineWidth: Math.max(1, Style.spaceReal(1.75))
  property bool showGrid: true
  property real referenceValue: NaN
  readonly property var samples: ChartModel.samples(points, timestamps)
  readonly property var domain: ChartModel.bounds(samples, referenceValue)
  readonly property real inset: Math.max(lineWidth, 1)
  readonly property real chartWidth: Math.max(1, width - inset * 2)
  readonly property real chartHeight: Math.max(1, height - inset * 2)

  antialiasing: true
  renderStrategy: Canvas.Threaded

  function xFor(index) {
    return inset + chartWidth * samples[index].position
  }

  function yFor(value) {
    return inset + chartHeight * (1 - (value - domain.minimum) / domain.spread)
  }

  function paintChart() {
    var context = getContext("2d")
    context.reset()
    context.clearRect(0, 0, width, height)

    var values = samples
    if (values.length < 2 || width <= 2 || height <= 2) return

    if (showGrid) {
      context.strokeStyle = gridColor
      context.lineWidth = 1
      for (var g = 1; g <= 2; g++) {
        var gy = Math.round(height * g / 3) + 0.5
        context.beginPath()
        context.moveTo(0, gy)
        context.lineTo(width, gy)
        context.stroke()
      }
    }

    if (isFinite(referenceValue)) {
      var referenceY = yFor(referenceValue)
      context.strokeStyle = referenceColor
      context.lineWidth = 1
      context.setLineDash([Style.spaceReal(3), Style.spaceReal(3)])
      context.beginPath()
      context.moveTo(0, referenceY)
      context.lineTo(width, referenceY)
      context.stroke()
      context.setLineDash([])
    }

    var gradient = context.createLinearGradient(0, 0, 0, height)
    gradient.addColorStop(0, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.22))
    gradient.addColorStop(1, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.01))
    context.fillStyle = gradient
    context.beginPath()
    context.moveTo(xFor(0), height - inset)
    for (var p = 0; p < values.length; p++) context.lineTo(xFor(p), yFor(values[p].value))
    context.lineTo(xFor(values.length - 1), height - inset)
    context.closePath()
    context.fill()

    context.strokeStyle = lineColor
    context.lineWidth = lineWidth
    context.lineCap = "round"
    context.lineJoin = "round"
    context.beginPath()
    for (var j = 0; j < values.length; j++) {
      if (j === 0) context.moveTo(xFor(j), yFor(values[j].value))
      else context.lineTo(xFor(j), yFor(values[j].value))
    }
    context.stroke()
  }

  onPaint: paintChart()
  onSamplesChanged: requestPaint()
  onLineColorChanged: requestPaint()
  onGridColorChanged: requestPaint()
  onReferenceColorChanged: requestPaint()
  onReferenceValueChanged: requestPaint()
  onLineWidthChanged: requestPaint()
  onShowGridChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
}
