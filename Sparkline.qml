import QtQuick
import qs.Commons

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

  antialiasing: true
  renderStrategy: Canvas.Threaded

  function finitePoints() {
    var out = []
    var source = Array.isArray(points) ? points : []
    for (var i = 0; i < source.length; i++) {
      var value = Number(source[i])
      if (isFinite(value)) out.push(value)
    }
    return out
  }

  function paintChart() {
    var context = getContext("2d")
    context.reset()
    context.clearRect(0, 0, width, height)

    var values = finitePoints()
    if (values.length < 2 || width <= 2 || height <= 2) return

    var minimum = values[0]
    var maximum = values[0]
    for (var i = 1; i < values.length; i++) {
      minimum = Math.min(minimum, values[i])
      maximum = Math.max(maximum, values[i])
    }
    if (isFinite(referenceValue)) {
      minimum = Math.min(minimum, referenceValue)
      maximum = Math.max(maximum, referenceValue)
    }
    var spread = maximum - minimum
    if (spread <= 0) spread = Math.max(Math.abs(maximum) * 0.01, 1)

    var inset = Math.max(lineWidth, 1)
    var chartWidth = Math.max(1, width - inset * 2)
    var chartHeight = Math.max(1, height - inset * 2)

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

    var times = []
    if (Array.isArray(timestamps) && timestamps.length === values.length) {
      for (var t = 0; t < timestamps.length; t++) {
        var timestamp = Number(timestamps[t])
        if (!isFinite(timestamp)) {
          times = []
          break
        }
        times.push(timestamp)
      }
    }
    var timeSpan = times.length > 1 ? times[times.length - 1] - times[0] : 0

    function xFor(index) {
      if (timeSpan > 0)
        return inset + chartWidth * (times[index] - times[0]) / timeSpan
      return inset + chartWidth * index / (values.length - 1)
    }
    function yFor(value) {
      return inset + chartHeight * (1 - (value - minimum) / spread)
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
    for (var p = 0; p < values.length; p++) context.lineTo(xFor(p), yFor(values[p]))
    context.lineTo(xFor(values.length - 1), height - inset)
    context.closePath()
    context.fill()

    context.strokeStyle = lineColor
    context.lineWidth = lineWidth
    context.lineCap = "round"
    context.lineJoin = "round"
    context.beginPath()
    for (var j = 0; j < values.length; j++) {
      if (j === 0) context.moveTo(xFor(j), yFor(values[j]))
      else context.lineTo(xFor(j), yFor(values[j]))
    }
    context.stroke()
  }

  onPaint: paintChart()
  onPointsChanged: requestPaint()
  onTimestampsChanged: requestPaint()
  onLineColorChanged: requestPaint()
  onGridColorChanged: requestPaint()
  onReferenceColorChanged: requestPaint()
  onReferenceValueChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
}
