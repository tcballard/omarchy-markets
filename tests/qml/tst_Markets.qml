import QtQuick
import QtTest
import "../.." as Markets
import "../../ChartModel.js" as ChartModel

Item {
  id: scene
  width: 900
  height: 760
  Item { id: focusSink }
  Component { id: chartComponent; Markets.HistoryChart {} }
  Component { id: widgetComponent; Markets.BarWidget {} }
  Component { id: panelComponent; Markets.Panel {} }

  QtObject {
    id: fixtureService
    property var quotes: [{symbol: "ACME", name: "Acme", currency: "USD", change: 1, changePercent: 1,
      regularMarketPrice: 102, marketTime: 1700000600000, sessionState: "regular",
      sparkline: [100, 101, 102], sparklineTimestamps: [1700000000000, 1700000060000, 1700000600000]}]
    property var errors: []
    property int revision: 0
    property string state: "ready"
    property bool refreshing: false
    property string lastError: ""
    property date lastUpdated: new Date(1700000600000)
    property var historyQuote: null
    property string historySymbol: ""
    property string historyRange: "1d"
    property string historyState: "ready"
    property bool historyRefreshing: false
    property string historyError: ""
    property int historyRevision: 0
    property int historyCalls: 0
    function configure(symbols, interval, enabled) {}
    function refreshIfStale() {}
    function requestHistory(symbol, range) { historyCalls++ }
  }
  QtObject {
    id: barFixture
    property color barForeground: "#eeeeee"
    property color background: "#202020"
    property string fontFamily: "DejaVu Sans"
    property QtObject shell: QtObject {
      function serviceFor(id) { return fixtureService }
      function updateEntryInline(id, entry) {}
    }
  }

  TestCase {
    id: tests
    name: "MarketsQmlSmoke"
    when: windowShown

    function init() {
      failOnWarning(/.*/)
      fixtureService.historyCalls = 0
      focusSink.forceActiveFocus()
      mouseMove(scene, 850, 730)
    }

    function chart() {
      var item = createTemporaryObject(chartComponent, scene, {
        width: 600, currency: "USD", symbol: "ACME",
        points: [10, 20, 30], timestamps: [1700000000, 1700000060, 1700000600]
      })
      verify(item !== null)
      item.returnFocus.connect(function() { focusSink.forceActiveFocus() })
      return item
    }

    function widget() {
      var item = createTemporaryObject(widgetComponent, scene, {y: 710})
      verify(item !== null)
      // Exercise late host injection and the production Loader as well as direct panel creation.
      item.bar = barFixture
      item.settings = {symbols: "ACME", primarySymbol: "ACME", dataEnabled: true, tickerPaused: true}
      tryVerify(function() { return findChild(item, "marketsPanel") !== null })
      return item
    }

    function test_coordinatesKeepPricesAndTimesPaired() {
      var samples = ChartModel.samples([10, null, 30], [1700000000, 1700000060, 1700000600])
      compare(samples.length, 2)
      compare(samples[1].value, 30)
      compare(samples[1].time, 1700000600000)
      compare(samples[1].position, 1)
      compare(ChartModel.samples([0, 1], [])[0].value, 0)
      compare(ChartModel.samples([10, 20, 30], [1700000000])[1].time, null)
      compare(ChartModel.timestampLabel(null), "Time unavailable")
      var invalidOrder = ChartModel.samples([10, 20, 30], [1700000600, 1700000000, 1700000060])
      compare(invalidOrder[1].position, 0.5)
      compare(ChartModel.bounds(samples, 0).minimum, 0)
      verify(ChartModel.bounds(ChartModel.samples([7, 7], []), NaN).spread > 0)
    }

    function test_hoverUsesTimeCoordinatesAndRenders() {
      var item = chart()
      var plot = findChild(item, "historyPlot")
      verify(waitForRendering(plot))
      compare(plot.samples[1].position, 0.1)
      mouseMove(plot, plot.inset + plot.chartWidth * 0.6, 70)
      tryCompare(item, "inspectedIndex", 2)
      verify(item.readoutText.indexOf("$30.00") >= 0)
      verify(item.readoutText.indexOf("2023-11-14 22:23:20 UTC") >= 0)
      var heightBefore = item.height
      mouseMove(scene, 850, 730)
      tryCompare(item, "inspectedIndex", -1)
      compare(item.height, heightBefore, "the pointer readout cannot shift the layout")
      mouseClick(plot, plot.inset + plot.chartWidth * 0.1, 70)
      tryCompare(item, "activeFocus", true)
      compare(item.inspectedIndex, 1)
      keyClick(Qt.Key_Escape)
      tryCompare(focusSink, "activeFocus", true)
    }

    function test_keyboardBoundsExitAndChangedData() {
      var item = chart()
      item.focusChart()
      tryCompare(item, "activeFocus", true)
      compare(item.inspectedIndex, 2)
      keyClick(Qt.Key_Home)
      compare(item.inspectedIndex, 0)
      keyClick(Qt.Key_Left)
      compare(item.inspectedIndex, 0)
      keyClick(Qt.Key_Right)
      compare(item.inspectedIndex, 1)
      keyClick(Qt.Key_End)
      compare(item.inspectedIndex, 2)
      item.points = [40, 50]
      compare(item.inspectedIndex, -1, "new data clears the previous marker")
      keyClick(Qt.Key_Home)
      verify(item.readoutText.indexOf("Time unavailable") >= 0)
      keyClick(Qt.Key_Escape)
      tryCompare(focusSink, "activeFocus", true)
      compare(item.keyboardIndex, -1)
      item.points = []
      compare(item.canInspect, false)
      compare(item.inspectedSample, null)
      item.focusChart()
      compare(item.activeFocus, false)
    }

    function test_chartQuotesRetainTinyPricesAndIndexUnits() {
      var item = chart()
      item.points = [0.000000122, 0.000000123]
      item.focusChart()
      verify(item.readoutText.indexOf("$0.0000001230") >= 0)
      item.instrumentType = "INDEX"
      item.points = [5995, 6000]
      item.focusChart()
      verify(item.readoutText.indexOf("6,000.00 pts") >= 0)
      compare(item.readoutText.indexOf("$"), -1)
      item.finishInspection()
    }

    function test_panelLoadsAndChartKeysDoNotChangeRange() {
      var host = widget()
      var panel = createTemporaryObject(panelComponent, scene, {hostWidget: host, marketService: fixtureService})
      verify(panel !== null)
      panel.open()
      var keys = findChild(panel, "panelKeys")
      tryCompare(keys, "activeFocus", true)
      var calls = fixtureService.historyCalls
      keyClick(Qt.Key_I)
      var inspector = findChild(panel, "historyChart")
      tryCompare(inspector, "activeFocus", true)
      compare(keys.blocked, true)
      keyClick(Qt.Key_Left)
      compare(inspector.inspectedIndex, 1)
      compare(panel.selectedRange, "1d")
      compare(fixtureService.historyCalls, calls, "inspection reuses already loaded history")
      host.setChartVisible(false)
      tryCompare(keys, "activeFocus", true, 1000, "a hidden chart cannot keep panel keys blocked")
      host.setChartVisible(true)
      keyClick(Qt.Key_I)
      tryCompare(inspector, "activeFocus", true)
      keyClick(Qt.Key_Escape)
      tryCompare(keys, "activeFocus", true)
      compare(panel.opened, true)
      compare(keys.blocked, false)
      keyClick(Qt.Key_Right)
      compare(host.selectedRange, "5d", "normal panel arrows retain their range action")
      host.setChartVisible(false)
      compare(panel.detailsExpanded, false)
      var quoteTime = findChild(panel, "selectedQuoteTime")
      verify(quoteTime.visible, "quote age stays available when the chart is hidden")
      verify(quoteTime.text.indexOf("Regular-session quote") >= 0)
      verify(quoteTime.text.indexOf("As of") >= 0)
      verify(panel.stateLabel().indexOf("Fetched ") === 0)
      panel.managing = true
      keyClick(Qt.Key_N)
      tryCompare(keys, "blocked", true)
      keyClick(Qt.Key_Escape)
      tryCompare(keys, "activeFocus", true)
      panel.close()
      compare(panel.opened, false)
    }

    function test_widgetNamedListsAndSetupReactToSettings() {
      var host = widget()
      verify(host.createWatchlist("Work", false).ok)
      var work = host.settings.activeWatchlistId
      verify(host.createWatchlist("Empty", true).ok)
      compare(host.setupRequired, true)
      verify(host.selectWatchlist(work).ok)
      compare(host.setupRequired, false)
      compare(host.primarySymbol, "ACME")
      host.setSortMode("gainers")
      host.setChartVisible(false)
      var restored = createTemporaryObject(widgetComponent, scene, {settings: JSON.parse(JSON.stringify(host.settings))})
      verify(restored !== null)
      compare(restored.watchlistLibrary.activeId, work)
      compare(restored.sortMode, "gainers")
      compare(restored.chartVisible, false)
      verify(restored.selectWatchlist("watchlist-1").ok)
      compare(restored.configuredSymbols.join(","), "ACME", "inactive list arrays survive Qt injection")
    }
  }
}
