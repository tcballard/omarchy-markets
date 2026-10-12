import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Commons as Omarchy
import qs.Ui
import "MarketModel.js" as MarketModel
import "WatchlistModel.js" as WatchlistModel

// Private, bar-attached market surface. The watchlist remains the primary
// navigation model; inspecting a row and pinning it to the bar are separate.
Panel {
  id: root
  objectName: "marketsPanel"
  moduleName: "io.github.tcballard.omarchy-markets"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var marketService: null
  property string selectedSymbol: ""
  property int setupCursor: 0
  property bool keyboardCursor: false
  property bool managing: false
  property string managerSection: "symbols"
  property bool chartView: false
  readonly property bool detailsExpanded: hostWidget ? hostWidget.chartVisible : true
  readonly property bool displayingDetails: chartView && detailsExpanded
  property string managerMessage: ""
  property double nowMs: Date.now()

  readonly property var barIdentity: hostWidget || root
  readonly property bool dataEnabled: hostWidget ? hostWidget.dataEnabled === true : false
  readonly property var symbols: hostWidget && Array.isArray(hostWidget.configuredSymbols)
    ? hostWidget.configuredSymbols : []
  readonly property string sortMode: hostWidget ? hostWidget.sortMode : "saved"
  readonly property var displaySymbols: WatchlistModel.sortSymbols(symbols, service.quotes, sortMode)
  readonly property var watchlistLibrary: hostWidget ? hostWidget.watchlistLibrary
    : ({ lists: [], activeId: "" })
  readonly property string watchlistName: {
    var index = WatchlistModel.indexOf(watchlistLibrary.lists, watchlistLibrary.activeId)
    return index >= 0 ? watchlistLibrary.lists[index].name : "Current watchlist"
  }
  readonly property string primarySymbol: hostWidget ? String(hostWidget.primarySymbol || "")
    : (symbols.length > 0 ? symbols[0] : "")
  readonly property string selectedRange: hostWidget
    ? String(hostWidget.selectedRange || "1d") : "1d"
  readonly property string barMode: hostWidget ? String(hostWidget.barMode || "ticker") : "ticker"
  readonly property string profileId: hostWidget ? String(hostWidget.profileId || "") : ""
  readonly property var profile: MarketModel.profileById(profileId)
  readonly property var profiles: MarketModel.profiles()
  readonly property bool setupRequired: !dataEnabled || symbols.length === 0
  readonly property string focusedSymbol: symbols.indexOf(selectedSymbol) >= 0
    ? selectedSymbol : primarySymbol
  readonly property int selectedIndex: symbols.indexOf(focusedSymbol)
  readonly property var focusedQuote: MarketModel.findQuote(service.quotes, focusedSymbol)
  readonly property bool historyMatches: service.historySymbol === focusedSymbol
    && service.historyRange === selectedRange
  // Quote totals always describe the quote snapshot. History is a separate
  // series and must never inherit a different range while a request is pending.
  readonly property var detailQuote: focusedQuote
  readonly property var chartQuote: MarketModel.chartQuoteFor(
    focusedQuote, service.historyQuote, historyMatches, selectedRange)
  readonly property var rangeResult: MarketModel.rangePerformance(
    chartQuote && Array.isArray(chartQuote.sparkline) ? chartQuote.sparkline : [])
  readonly property var stats: MarketModel.statRows(detailQuote)
  readonly property color foreground: Omarchy.Color.popups.text
  // Muted is a global palette token, not a promise of readable popup text.
  // Fall back to the popup's text role for low contrast or translucent themes.
  readonly property color dim: popupBackground.a < 0.85 || Omarchy.Color.muted.a < 1
    || contrastRatio(Omarchy.Color.muted, popupBackground) < 4.5 ? foreground : Omarchy.Color.muted
  readonly property color popupBackground: Omarchy.Color.popups.background
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color positiveBright: "#30d158"
  readonly property color positiveDark: "#137333"
  readonly property color negativeBright: "#ff453a"
  readonly property color negativeDark: "#b3261e"
  readonly property color positiveColor: contrastAwareColor(
    popupBackground, positiveBright, positiveDark, foreground)
  readonly property color negativeColor: contrastAwareColor(
    popupBackground, negativeBright, negativeDark, foreground)

  QtObject {
    id: dummyService
    property var quotes: []
    property var errors: []
    property string state: "waiting"
    property bool refreshing: false
    property string providerLabel: "Yahoo Finance chart"
    property string lastError: ""
    property date lastUpdated: new Date(0)
    property var historyQuote: null
    property string historySymbol: ""
    property string historyRange: "1d"
    property string historyState: "setup"
    property bool historyRefreshing: false
    property string historyError: ""
    property int historyRevision: 0
    function refresh() {}
    function refreshIfStale() {}
    function requestHistory(symbol, range) {}
  }

  readonly property var service: marketService || dummyService

  function linearChannel(value) {
    return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4)
  }

  function relativeLuminance(value) {
    return 0.2126 * linearChannel(value.r)
      + 0.7152 * linearChannel(value.g)
      + 0.0722 * linearChannel(value.b)
  }

  function contrastRatio(first, second) {
    var one = relativeLuminance(first)
    var two = relativeLuminance(second)
    return (Math.max(one, two) + 0.05) / (Math.min(one, two) + 0.05)
  }

  function contrastAwareColor(background, bright, dark, fallback) {
    if (background.a < 0.85) return fallback
    var brightRatio = contrastRatio(bright, background)
    var darkRatio = contrastRatio(dark, background)
    var candidate = brightRatio >= darkRatio ? bright : dark
    return Math.max(brightRatio, darkRatio) >= 4.5 ? candidate : fallback
  }

  function movementColorFor(quote) {
    var direction = MarketModel.changeDirection(quote)
    if (direction === "up") return positiveColor
    if (direction === "down") return negativeColor
    return foreground
  }

  function rangeMovementColor() {
    if (rangeResult.direction === "up") return positiveColor
    if (rangeResult.direction === "down") return negativeColor
    return foreground
  }

  function directionArrow(quote) {
    var direction = MarketModel.changeDirection(quote)
    if (direction === "up") return "▲"
    if (direction === "down") return "▼"
    if (direction === "flat") return "→"
    return "—"
  }

  function rangeArrow() {
    if (rangeResult.direction === "up") return "▲"
    if (rangeResult.direction === "down") return "▼"
    if (rangeResult.direction === "flat") return "→"
    return "—"
  }

  function syncSelection() {
    selectedSymbol = primarySymbol
    keyboardCursor = false
    requestFocusedHistory()
  }

  function open() {
    nowMs = Date.now()
    managing = false
    chartView = false
    managerMessage = ""
    syncSelection()
    root.controller.show()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    if (service && typeof service.refreshIfStale === "function") service.refreshIfStale()
  }

  function close() {
    root.controller.hide()
    keyboardCursor = false
    managing = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function handleClose() {
    if (managing && !setupRequired) {
      managing = false
      managerMessage = ""
      return
    }
    if (displayingDetails) {
      chartView = false
      return
    }
    close()
  }

  function switchPanel(directionValue) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, directionValue)
    return false
  }

  function moveSelection(delta) {
    if (setupRequired && !managing) {
      var setupCount = profiles.length + 1
      setupCursor = (setupCursor + delta + setupCount) % setupCount
      return
    }
    if (managing) {
      managerSection = "symbols"
      if (symbols.length === 0) return
      selectedSymbol = symbols[(selectedIndex + delta + symbols.length) % symbols.length]
      keyboardCursor = true
      return
    }
    if (symbols.length === 0) return
    keyboardCursor = true
    var index = displaySymbols.indexOf(focusedSymbol)
    selectedSymbol = displaySymbols[(index + delta + displaySymbols.length) % displaySymbols.length]
    requestFocusedHistory()
  }

  function moveRange(delta) {
    if (setupRequired || managing || focusedSymbol === "") return
    setDetailsExpanded(true)
    chartView = true
    var options = MarketModel.rangeOptions()
    var index = 0
    for (var cursor = 0; cursor < options.length; cursor += 1) {
      if (options[cursor].id === selectedRange) index = cursor
    }
    index = (index + delta + options.length) % options.length
    chooseRange(options[index].id)
  }

  function activateCurrent() {
    if (setupRequired && !managing) {
      if (setupCursor < profiles.length) chooseProfile(profiles[setupCursor].id)
      else startCustom()
      return
    }
    if (managing) {
      symbolInput.forceActiveFocus()
      return
    }
    chartView = true
    setDetailsExpanded(true)
    requestFocusedHistory()
  }

  function inspectSymbol(symbol) {
    selectedSymbol = symbol
    keyboardCursor = false
    requestFocusedHistory()
  }

  function requestFocusedHistory() {
    if (!displayingDetails || focusedSymbol === "" || !dataEnabled) return
    if (service && typeof service.requestHistory === "function")
      service.requestHistory(focusedSymbol, selectedRange)
  }

  function setDetailsExpanded(expanded) {
    if (detailsExpanded !== expanded && hostWidget
        && typeof hostWidget.setChartVisible === "function")
      hostWidget.setChartVisible(expanded)
  }

  function toggleDetails() {
    var expanded = !displayingDetails
    chartView = expanded
    setDetailsExpanded(expanded)
    if (expanded) Qt.callLater(root.requestFocusedHistory)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function inspectChart() {
    if (setupRequired || managing) return
    var wasExpanded = displayingDetails
    chartView = true
    setDetailsExpanded(true)
    Qt.callLater(function() {
      if (!wasExpanded) root.requestFocusedHistory()
      historyChart.focusChart()
    })
  }

  function cycleSort() {
    var modes = ["saved", "gainers", "losers"]
    if (hostWidget) hostWidget.setSortMode(modes[(modes.indexOf(sortMode) + 1) % modes.length])
  }

  function handleWatchlistResult(result) {
    managerMessage = result.message
    if (result.ok) Qt.callLater(root.syncSelection)
  }

  function selectWatchlist(id) {
    if (hostWidget) handleWatchlistResult(hostWidget.selectWatchlist(id))
  }

  function cycleWatchlist(direction) {
    var lists = watchlistLibrary.lists
    if (lists.length < 2) return
    var index = WatchlistModel.indexOf(lists, watchlistLibrary.activeId)
    var step = direction === -1 ? -1 : 1
    selectWatchlist(lists[(index + step + lists.length) % lists.length].id)
  }

  function pinFocused() {
    if (focusedSymbol === "" || !hostWidget
        || typeof hostWidget.setPrimarySymbol !== "function") return
    hostWidget.setPrimarySymbol(focusedSymbol)
  }

  function chooseRange(rangeValue) {
    if (hostWidget && typeof hostWidget.setRange === "function")
      hostWidget.setRange(rangeValue)
    if (service && typeof service.requestHistory === "function")
      service.requestHistory(focusedSymbol, rangeValue)
  }

  function chooseProfile(profileValue) {
    if (!hostWidget || typeof hostWidget.applyProfile !== "function") return
    if (hostWidget.applyProfile(profileValue)) {
      managing = false
      managerMessage = "Profile applied. You can edit it at any time."
      Qt.callLater(root.syncSelection)
    }
  }

  function startCustom() {
    managing = true
    managerMessage = "Add your first public market symbol. Saving it enables market requests."
    Qt.callLater(function() { symbolInput.forceActiveFocus() })
  }

  function addEnteredSymbol() {
    if (!hostWidget || typeof hostWidget.addSymbol !== "function") return
    var result = hostWidget.addSymbol(symbolInput.text)
    managerMessage = result.message
    if (result.ok && result.changed) {
      symbolInput.text = ""
      if (!dataEnabled && typeof hostWidget.setDataEnabled === "function")
        hostWidget.setDataEnabled(true)
      Qt.callLater(root.syncSelection)
    }
  }

  function removeManagedSymbol(symbol) {
    if (!hostWidget || typeof hostWidget.removeSymbol !== "function") return
    var previousIndex = selectedIndex
    var inspected = focusedSymbol
    var result = hostWidget.removeSymbol(symbol)
    managerMessage = result.message
    if (result.ok && result.changed) {
      selectedSymbol = result.symbols.indexOf(inspected) >= 0 ? inspected
        : (result.symbols[Math.max(0, Math.min(previousIndex, result.symbols.length - 1))] || "")
      Qt.callLater(root.requestFocusedHistory)
    }
  }

  function moveManagedSymbol(symbol, destination) {
    if (!hostWidget || typeof hostWidget.moveSymbol !== "function") return
    var inspected = focusedSymbol
    var result = hostWidget.moveSymbol(symbol, destination)
    managerMessage = result.message
    if (result.ok && result.changed) {
      selectedSymbol = result.symbols.indexOf(inspected) >= 0 ? inspected : (result.symbols[0] || "")
      Qt.callLater(root.requestFocusedHistory)
    }
  }

  function managerShortcut(text) {
    if (text === "a" || text === "A") {
      managerSection = "symbols"
      Qt.callLater(function() { symbolInput.forceActiveFocus() })
    }
    else if (text === "n" || text === "N") {
      managerSection = "lists"
      Qt.callLater(function() { watchlistEditor.focusName() })
    }
    else if (text === "x" || text === "X") root.removeManagedSymbol(root.focusedSymbol)
    else if (text === "[") root.moveManagedSymbol(root.focusedSymbol, root.selectedIndex - 1)
    else if (text === "]") root.moveManagedSymbol(root.focusedSymbol, root.selectedIndex + 1)
    else if (text === "b" || text === "B") {
      if (root.hostWidget) root.hostWidget.setBarMode(root.barMode === "ticker" ? "single" : "ticker")
    } else if (text === "c" || text === "C") {
      if (root.hostWidget && root.symbols.length > 0)
        root.hostWidget.setDataEnabled(!root.dataEnabled)
    } else if (text === "t" || text === "T") {
      if (root.hostWidget && root.barMode === "ticker")
        root.hostWidget.setTickerPaused(!root.hostWidget.tickerPaused)
    } else if (text === "m" || text === "M") {
      root.managing = false
      root.managerMessage = ""
    } else if (text === "p" || text === "P") root.pinFocused()
  }

  function refresh() {
    if (service && typeof service.refresh === "function") service.refresh()
  }

  function openFocusedQuote() {
    if (focusedSymbol === "") return
    Qt.openUrlExternally("https://finance.yahoo.com/quote/" + encodeURIComponent(focusedSymbol))
  }

  function errorFor(symbol) {
    var source = Array.isArray(service.errors) ? service.errors : []
    for (var index = 0; index < source.length; index += 1) {
      if (String(source[index].symbol || "") === String(symbol)) return source[index]
    }
    return null
  }

  function stateLabel() {
    if (!dataEnabled) return "Market data is off"
    if (symbols.length === 0) return "Choose a profile or add a symbol"
    if (service.refreshing && service.quotes.length === 0) return "Updating…"
    if (service.state === "disabled") return "Polling paused"
    if (service.state === "stale") return "Stale data"
    if (service.state === "partial") return "Some quotes not current"
    if (service.state === "dependency-missing") return "Python 3 needed"
    if (service.state === "offline") return "Offline"
    if (service.state === "failed" || service.state === "malformed") return "Unavailable"
    if (service.lastUpdated && service.lastUpdated.getTime() > 0)
      return "Fetched " + MarketModel.formatFreshness(service.lastUpdated, nowMs).toLowerCase()
    return "Waiting"
  }

  function statusIsWarning() {
    return ["stale", "partial", "dependency-missing", "offline", "failed", "malformed"]
      .indexOf(String(service.state)) >= 0
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    onTriggered: root.nowMs = Date.now()
  }

  onSelectedRangeChanged: {
    if (root.opened && !root.setupRequired && !root.managing)
      Qt.callLater(root.requestFocusedHistory)
  }

  onManagingChanged: if (managing) managerSection = "symbols"
  onDisplayingDetailsChanged: if (!displayingDetails && root.opened) {
    historyChart.finishInspection()
  }

  KeyboardPanel {
    id: panel
    objectName: "marketsPopup"
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(620))
    // Views fit separately; never stack the full watchlist above chart details.
    readonly property real maximumPopupHeight: Math.min(Style.space(560),
      panel.availableCardHeight > 0 ? Math.floor(panel.availableCardHeight * 0.75) : Style.space(560))
    contentHeight: Math.min(maximumPopupHeight,
      panel.fittedContentHeight(contentColumn.implicitHeight + footerReserve))
    readonly property real footerReserve: dataFooter.visible
      ? dataFooter.implicitHeight + Style.space(12) : 0

    PanelKeyCatcher {
      id: keyCatcher
      objectName: "panelKeys"
      anchors.fill: parent
      blocked: symbolInput.activeFocus || watchlistEditor.activeFocus || historyChart.activeFocus
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveRange(dx)
        if (dy !== 0) root.moveSelection(dy)
      }
      onActivateRequested: root.activateCurrent()
      onDeleteRequested: {
        if (root.managing) root.removeManagedSymbol(root.focusedSymbol)
      }
      onCloseRequested: root.handleClose()
      onTabRequested: function(directionValue) { root.switchPanel(directionValue) }
      onTextKey: function(text) {
        if (text === "w" || text === "W") {
          root.cycleWatchlist()
          return
        }
        if (root.managing) {
          root.managerShortcut(text)
          return
        }
        if (root.setupRequired) {
          var number = parseInt(text, 10)
          if (number >= 1 && number <= root.profiles.length)
            root.chooseProfile(root.profiles[number - 1].id)
          else if (text === "c" || text === "C") root.startCustom()
          return
        }
        if (text === "d" || text === "D") root.toggleDetails()
        else if (text === "i" || text === "I") root.inspectChart()
        else if (text === "s" || text === "S") root.cycleSort()
        else if (text === "r" || text === "R") root.refresh()
        else if (text === "o" || text === "O") root.openFocusedQuote()
        else if (text === "p" || text === "P") root.pinFocused()
        else if (text === "m" || text === "M") root.managing = true
      }

      Item {
        id: panelContent
        objectName: "marketsContent"
        anchors.fill: parent
        anchors.bottomMargin: panel.footerReserve
        clip: true

        Column {
          id: contentColumn
          objectName: "marketsContentColumn"
          width: panelContent.width
          spacing: Style.space(8)

          Row {
            objectName: "marketHeader"
            width: parent.width
            height: Math.max(titleBlock.implicitHeight, headerActions.implicitHeight)

            Column {
              id: titleBlock
              width: parent.width - headerActions.width - Style.space(8)
              spacing: Style.space(2)

              Text {
                visible: !root.displayingDetails
                textFormat: Text.PlainText
                text: "Omarchy Markets"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.watchlistName + " · " + root.stateLabel()
                color: root.statusIsWarning() ? root.negativeColor : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                Accessible.name: "Market data status: " + text
              }
            }

            Row {
              id: headerActions
              spacing: Style.space(4)

              Button {
                text: root.managing ? "Done" : "Manage"
                foreground: root.foreground
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(6)
                tooltipText: root.managing ? "Return to markets" : "Manage watchlist (M)"
                Accessible.role: Accessible.Button
                Accessible.name: root.managing ? "Finish managing watchlist" : "Manage watchlist"
                Accessible.onPressAction: root.managing = !root.managing
                onClicked: {
                  root.managing = !root.managing
                  root.managerMessage = ""
                }
              }

              Button {
                iconText: "󰑐"
                iconSpinning: service.refreshing
                foreground: root.foreground
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(6)
                enabled: root.dataEnabled && root.symbols.length > 0
                opacity: enabled ? 1 : 0.4
                tooltipText: "Refresh quotes (R)"
                Accessible.role: Accessible.Button
                Accessible.name: service.refreshing ? "Refreshing market quotes" : "Refresh market quotes"
                Accessible.onPressAction: root.refresh()
                onClicked: root.refresh()
              }
            }
          }

          Row {
            visible: root.watchlistLibrary.lists.length > 1 && !root.displayingDetails
            width: parent.width
            spacing: Style.space(6)
            Button {
              text: "‹"
              foreground: root.foreground
              Accessible.name: "Previous watchlist"
              onClicked: root.cycleWatchlist(-1)
              Accessible.onPressAction: root.cycleWatchlist(-1)
            }
            Button {
              text: "Watchlist: " + (root.watchlistName.length > 24
                ? root.watchlistName.slice(0, 23) + "…" : root.watchlistName)
              foreground: root.foreground
              tooltipText: "Next watchlist (W)"
              Accessible.name: root.watchlistName + ". Next watchlist."
              onClicked: root.cycleWatchlist()
              Accessible.onPressAction: root.cycleWatchlist()
            }
            Button {
              text: "›"
              foreground: root.foreground
              Accessible.name: "Next watchlist"
              onClicked: root.cycleWatchlist()
              Accessible.onPressAction: root.cycleWatchlist()
            }
          }

          Text {
            visible: !root.managing && root.managerMessage !== ""
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: root.managerMessage
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Column {
            id: setupView
            visible: root.setupRequired && !root.managing
            width: parent.width
            spacing: Style.space(8)

            BorderSurface {
              width: parent.width
              implicitHeight: setupIntro.implicitHeight + contentTopInset + contentBottomInset
              height: implicitHeight
              radius: Math.max(Style.cornerRadius, Style.space(16))
              color: Style.normalFillFor(root.foreground, Omarchy.Color.accent, Omarchy.Color.urgent)
              borderSpec: Border.controlSpec("normal", root.foreground, Omarchy.Color.accent)
              padding: Style.space(10)

              Column {
                id: setupIntro
                anchors.fill: parent
                anchors.topMargin: parent.contentTopInset
                anchors.rightMargin: parent.contentRightInset
                anchors.bottomMargin: parent.contentBottomInset
                anchors.leftMargin: parent.contentLeftInset
                spacing: Style.space(5)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "Choose your first market view"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }

                Text {
                  width: parent.width
                  wrapMode: Text.Wrap
                  textFormat: Text.PlainText
                  text: "Profiles are editable starting points. Choosing one enables direct best-effort requests for its public symbols; there are no accounts or trades."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }

            Grid {
              width: parent.width
              columns: 2
              columnSpacing: Style.space(8)
              rowSpacing: Style.space(8)
              Repeater {
              id: profileRepeater
              model: root.profiles

              delegate: BorderSurface {
                id: profileCard
                required property var modelData
                required property int index
                width: (setupView.width - Style.space(8)) / 2
                implicitHeight: profileContent.implicitHeight + contentTopInset + contentBottomInset
                height: implicitHeight
                radius: Math.max(Style.cornerRadius, Style.space(13))
                color: root.setupCursor === index
                  ? Style.selectedFillFor(root.foreground, Omarchy.Color.accent, Omarchy.Color.urgent)
                  : profileMouse.containsMouse
                  ? Style.hoverFillFor(root.foreground, Omarchy.Color.accent, Omarchy.Color.urgent)
                  : "transparent"
                borderSpec: Border.controlSpec(root.setupCursor === index ? "focus" : "normal",
                  root.foreground, Omarchy.Color.accent)
                padding: Style.space(8)
                Accessible.role: Accessible.Button
                Accessible.name: modelData.name + ". " + modelData.description
                Accessible.description: "Choose this profile and enable market data"
                Accessible.onPressAction: root.chooseProfile(profileCard.modelData.id)

                Row {
                  id: profileContent
                  anchors.fill: parent
                  anchors.topMargin: profileCard.contentTopInset
                  anchors.rightMargin: profileCard.contentRightInset
                  anchors.bottomMargin: profileCard.contentBottomInset
                  anchors.leftMargin: profileCard.contentLeftInset
                  spacing: Style.space(10)

                  Column {
                    width: parent.width - chooseProfileButton.width - parent.spacing
                    spacing: Style.space(3)

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: profileCard.modelData.name
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }

                    Text {
                      width: parent.width
                      wrapMode: Text.Wrap
                      textFormat: Text.PlainText
                      text: profileCard.modelData.description
                        + (profileCard.modelData.id === "meme-coins" ? " Highly speculative." : "")
                      maximumLineCount: 1
                      elide: Text.ElideRight
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Button {
                    id: chooseProfileButton
                    text: "Choose"
                    tooltipText: profileCard.modelData.description
                      + (profileCard.modelData.id === "meme-coins" ? " Highly speculative." : "")
                    foreground: root.foreground
                    bordered: true
                    Accessible.role: Accessible.Button
                    Accessible.name: "Choose " + profileCard.modelData.name
                    Accessible.onPressAction: root.chooseProfile(profileCard.modelData.id)
                    onClicked: root.chooseProfile(profileCard.modelData.id)
                  }
                }

                MouseArea {
                  id: profileMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  z: -1
                  onClicked: root.chooseProfile(profileCard.modelData.id)
                }
              }
            }
            }

            Button {
              id: startCustomButton
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Start custom"
              foreground: root.foreground
              bordered: root.setupCursor === root.profiles.length
              tooltipText: "Build a custom watchlist"
              Accessible.role: Accessible.Button
              Accessible.name: "Start a custom watchlist"
              Accessible.onPressAction: root.startCustom()
              onClicked: root.startCustom()
            }
          }

          Column {
            id: managerView
            objectName: "marketManager"
            visible: root.managing
            width: parent.width
            spacing: Style.space(8)

            Row {
              spacing: Style.space(6)
              Repeater {
                model: ["symbols", "lists", "preferences"]
                Button {
                  required property string modelData
                  text: modelData === "symbols" ? "Symbols" : modelData === "lists" ? "Watchlists" : "Preferences"
                  foreground: root.foreground
                  selected: root.managerSection === modelData
                  onClicked: root.managerSection = modelData
                  Accessible.name: "Manage " + modelData
                  Accessible.onPressAction: root.managerSection = modelData
                }
              }
            }

            Column {
              visible: root.managerSection === "lists"
              width: parent.width
              spacing: Style.space(8)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              text: "WATCHLISTS · " + root.watchlistLibrary.lists.length + "/8"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              text: "Edits are saved to " + root.watchlistName + ". Give a new list or copy a name, or rename this list."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            WatchlistEditor {
              id: watchlistEditor
              width: parent.width
              hostWidget: root.hostWidget
              foreground: root.foreground
              fontFamily: root.fontFamily
              onResultReady: function(result) { root.handleWatchlistResult(result) }
              onReturnFocus: keyCatcher.forceActiveFocus()
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "STARTING PROFILES"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.1
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)
              height: childrenRect.height

              Repeater {
                model: root.profiles

                Button {
                  required property var modelData
                  text: modelData.name
                  foreground: root.foreground
                  bordered: root.profileId === modelData.id
                  tooltipText: "Replace this watchlist with " + modelData.name
                  Accessible.role: Accessible.Button
                  Accessible.name: "Apply " + modelData.name + " starting profile"
                  Accessible.onPressAction: root.chooseProfile(modelData.id)
                  onClicked: root.chooseProfile(modelData.id)
                }
              }
            }

            PanelSeparator { foreground: root.foreground }

            }

            Column {
              visible: root.managerSection === "symbols"
              width: parent.width
              spacing: Style.space(6)
            Text {
              width: parent.width
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: "Add Yahoo-style public symbols, then reorder or remove them. Up to 12 symbols."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              id: symbolEntry
              width: parent.width
              height: Math.max(Style.space(40), addButton.implicitHeight)
              spacing: Style.space(8)

              BorderSurface {
                width: parent.width - addButton.width - parent.spacing
                height: symbolEntry.height
                radius: 0
                color: Style.normalFillFor(root.foreground, Omarchy.Color.accent, Omarchy.Color.urgent)
                borderSpec: Border.controlSpec(symbolInput.activeFocus ? "focus" : "normal",
                  root.foreground, Omarchy.Color.accent)
                padding: Style.space(9)

                TextInput {
                  id: symbolInput
                  anchors.fill: parent
                  anchors.leftMargin: parent.contentLeftInset
                  anchors.rightMargin: parent.contentRightInset
                  verticalAlignment: TextInput.AlignVCenter
                  color: root.foreground
                  selectionColor: Omarchy.Color.accent
                  selectedTextColor: root.popupBackground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  maximumLength: 32
                  inputMethodHints: Qt.ImhUppercaseOnly | Qt.ImhNoPredictiveText
                  Accessible.name: "Market symbol"
                  onAccepted: root.addEnteredSymbol()
                  Keys.onEscapePressed: function(event) {
                    symbolInput.focus = false
                    keyCatcher.forceActiveFocus()
                    event.accepted = true
                  }
                  Keys.onTabPressed: function(event) {
                    symbolInput.focus = false
                    keyCatcher.forceActiveFocus()
                    event.accepted = true
                  }

                  Text {
                    visible: symbolInput.text === "" && !symbolInput.activeFocus
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: "Symbol, e.g. AAPL or BTC-USD"
                    color: root.dim
                    font: symbolInput.font
                  }
                }
              }

              Button {
                id: addButton
                height: symbolEntry.height
                text: "Add"
                foreground: root.foreground
                bordered: true
                Accessible.role: Accessible.Button
                Accessible.name: "Add symbol to watchlist"
                Accessible.onPressAction: root.addEnteredSymbol()
                onClicked: root.addEnteredSymbol()
              }
            }

            Text {
              visible: root.managerMessage !== ""
              width: parent.width
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: root.managerMessage
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              Accessible.name: text
            }

            Grid {
              width: parent.width
              columns: root.symbols.length > 4 ? 3 : 1
              columnSpacing: Style.space(6)
              rowSpacing: Style.space(4)
              Repeater {
              id: managerRepeater
              model: root.symbols

              delegate: BorderSurface {
                id: managerRow
                required property string modelData
                required property int index
                readonly property bool selected: root.selectedIndex === index
                width: (managerView.width - (parent.columns - 1) * parent.columnSpacing) / parent.columns
                height: Style.space(40)
                radius: 0
                color: selected
                  ? Style.selectedFillFor(root.foreground, Omarchy.Color.accent, Omarchy.Color.urgent)
                  : "transparent"
                borderSpec: Border.controlSpec(selected ? "focus" : "normal",
                  root.foreground, Omarchy.Color.accent)

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(6)
                  spacing: Style.space(4)

                  Text {
                    width: parent.width - upButton.width - downButton.width - removeButton.width
                      - parent.spacing * 3
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: managerRow.modelData
                      + (managerRow.modelData === root.primarySymbol ? "  ·  PINNED" : "")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Button {
                    id: upButton
                    anchors.verticalCenter: parent.verticalCenter
                    text: "▲"
                    foreground: root.foreground
                    enabled: managerRow.index > 0
                    opacity: enabled ? 1 : 0.35
                    tooltipText: "Move " + managerRow.modelData + " up"
                    Accessible.role: Accessible.Button
                    Accessible.name: "Move " + managerRow.modelData + " up"
                    Accessible.onPressAction: root.moveManagedSymbol(managerRow.modelData, managerRow.index - 1)
                    onClicked: root.moveManagedSymbol(managerRow.modelData, managerRow.index - 1)
                  }

                  Button {
                    id: downButton
                    anchors.verticalCenter: parent.verticalCenter
                    text: "▼"
                    foreground: root.foreground
                    enabled: managerRow.index < root.symbols.length - 1
                    opacity: enabled ? 1 : 0.35
                    tooltipText: "Move " + managerRow.modelData + " down"
                    Accessible.role: Accessible.Button
                    Accessible.name: "Move " + managerRow.modelData + " down"
                    Accessible.onPressAction: root.moveManagedSymbol(managerRow.modelData, managerRow.index + 1)
                    onClicked: root.moveManagedSymbol(managerRow.modelData, managerRow.index + 1)
                  }

                  Button {
                    id: removeButton
                    anchors.verticalCenter: parent.verticalCenter
                    text: "×"
                    foreground: root.negativeColor
                    tooltipText: "Remove " + managerRow.modelData
                    Accessible.role: Accessible.Button
                    Accessible.name: "Remove " + managerRow.modelData + " from watchlist"
                    Accessible.onPressAction: root.removeManagedSymbol(managerRow.modelData)
                    onClicked: root.removeManagedSymbol(managerRow.modelData)
                  }
                }
              }
            }
            }
            }

            Column {
              visible: root.managerSection === "preferences"
              width: parent.width
              spacing: Style.space(8)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "BAR PRESENTATION"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.1
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                text: "Single quote"
                foreground: root.foreground
                bordered: root.barMode === "single"
                Accessible.role: Accessible.Button
                Accessible.name: "Use single quote bar mode"
                Accessible.onPressAction: if (root.hostWidget) root.hostWidget.setBarMode("single")
                onClicked: if (root.hostWidget) root.hostWidget.setBarMode("single")
              }

              Button {
                text: "Ticker"
                foreground: root.foreground
                bordered: root.barMode === "ticker"
                Accessible.role: Accessible.Button
                Accessible.name: "Use scrolling ticker bar mode"
                Accessible.onPressAction: if (root.hostWidget) root.hostWidget.setBarMode("ticker")
                onClicked: if (root.hostWidget) root.hostWidget.setBarMode("ticker")
              }

              Button {
                visible: root.barMode === "ticker"
                text: root.hostWidget && root.hostWidget.tickerPaused ? "Resume" : "Pause"
                foreground: root.foreground
                Accessible.role: Accessible.Button
                Accessible.name: text + " scrolling ticker"
                Accessible.onPressAction: if (root.hostWidget)
                  root.hostWidget.setTickerPaused(!root.hostWidget.tickerPaused)
                onClicked: if (root.hostWidget)
                  root.hostWidget.setTickerPaused(!root.hostWidget.tickerPaused)
              }
            }

            Row {
              width: parent.width

              Button {
                text: root.dataEnabled ? "Pause market data" : "Enable market data"
                foreground: root.dataEnabled ? root.negativeColor : root.foreground
                enabled: root.symbols.length > 0
                opacity: enabled ? 1 : 0.4
                Accessible.role: Accessible.Button
                Accessible.name: text
                Accessible.onPressAction: if (root.hostWidget)
                  root.hostWidget.setDataEnabled(!root.dataEnabled)
                onClicked: if (root.hostWidget)
                  root.hostWidget.setDataEnabled(!root.dataEnabled)
              }
            }

            }

            Text {
              width: parent.width
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: "↑/↓ select · [/] reorder · P pin · Delete remove · A add · N name"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            id: marketsView
            visible: !root.setupRequired && !root.managing
            width: parent.width
            spacing: Style.space(8)

            Flow {
              width: parent.width
              spacing: Style.space(8)

              Button {
                visible: !root.displayingDetails
                text: "Order: " + (root.sortMode === "gainers" ? "Gainers first"
                  : root.sortMode === "losers" ? "Losers first" : "Saved")
                foreground: root.foreground
                tooltipText: "Cycle saved order, daily gainers and daily losers (S)"
                Accessible.role: Accessible.Button
                Accessible.name: text + ". Change watchlist sort order."
                Accessible.onPressAction: root.cycleSort()
                onClicked: root.cycleSort()
              }

              Button {
                objectName: "chartViewButton"
                text: root.displayingDetails ? "← Watchlist" : "Chart · " + root.focusedSymbol
                foreground: root.foreground
                tooltipText: "Switch between watchlist and chart (D)"
                Accessible.name: text
                onClicked: root.toggleDetails()
                Accessible.onPressAction: root.toggleDetails()
              }
            }

            GridView {
              id: watchlist
              objectName: "marketWatchlist"
              visible: !root.displayingDetails
              readonly property int columns: root.symbols.length > 6 ? 2 : 1
              readonly property int rowHeight: Style.space(48)
              width: parent.width
              cellWidth: width / columns
              cellHeight: rowHeight
              height: Math.ceil(root.symbols.length / columns) * rowHeight
              clip: false
              interactive: false
              boundsBehavior: Flickable.StopAtBounds
              model: root.displaySymbols
              currentIndex: root.displaySymbols.indexOf(root.focusedSymbol)

              delegate: BorderSurface {
                id: quoteRow
                required property string modelData
                required property int index
                property var quote: MarketModel.findQuote(service.quotes, modelData)
                readonly property bool inspected: root.focusedSymbol === modelData
                readonly property bool pinned: modelData === root.primarySymbol
                readonly property bool stale: service.state === "stale"
                  || (quote && (quote.stale === true || quote.cached === true))
                width: watchlist.cellWidth
                height: watchlist.rowHeight
                radius: Style.cornerRadius
                color: inspected
                  ? Style.selectedFillFor(root.foreground, Omarchy.Color.accent, Omarchy.Color.urgent)
                  : rowMouse.containsMouse
                    ? Style.hoverFillFor(root.foreground, Omarchy.Color.accent, Omarchy.Color.urgent)
                    : "transparent"
                borderSpec: root.keyboardCursor && inspected
                  ? Border.controlSpec("focus", root.foreground, Omarchy.Color.accent)
                  : inspected
                    ? Border.controlSpec("selected", root.foreground, Omarchy.Color.accent)
                    : Border.none()
                Accessible.role: Accessible.Button
                Accessible.name: quote
                  ? MarketModel.quoteAccessibilityLabel(quote, root.nowMs)
                    + (pinned ? ", pinned to bar" : "")
                  : modelData + ", quote unavailable"
                Accessible.description: "Activate to inspect. Pinning is a separate action."
                Accessible.onPressAction: root.inspectSymbol(quoteRow.modelData)

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(14)

                  Column {
                    width: Math.max(0, parent.width - rowNumbers.width
                      - (rowSpark.visible ? rowSpark.width + parent.spacing : 0)
                      - parent.spacing)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(3)

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: quoteRow.modelData
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: quoteRow.quote ? quoteRow.quote.name : "Unavailable"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  Sparkline {
                    id: rowSpark
                    visible: quoteRow.width >= Style.space(420)
                    width: Style.space(92)
                    height: Style.space(28)
                    anchors.verticalCenter: parent.verticalCenter
                    points: quoteRow.quote ? quoteRow.quote.sparkline : []
                    timestamps: quoteRow.quote ? quoteRow.quote.sparklineTimestamps : []
                    referenceValue: {
                      var value = quoteRow.quote ? MarketModel.finiteNumber(quoteRow.quote.previousClose) : null
                      return value === null ? NaN : value
                    }
                    lineColor: root.movementColorFor(quoteRow.quote)
                    referenceColor: root.dim
                    showGrid: false
                  }

                  Column {
                    id: rowNumbers
                    width: Math.min(Style.space(150), parent.width * 0.45)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(3)

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      horizontalAlignment: Text.AlignRight
                      text: quoteRow.quote
                        ? MarketModel.formatQuotePrice(quoteRow.quote.regularMarketPrice,
                          quoteRow.quote) : "—"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideLeft
                    }

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      horizontalAlignment: Text.AlignRight
                      text: quoteRow.quote
                        ? root.directionArrow(quoteRow.quote) + " "
                          + MarketModel.formatPercent(quoteRow.quote.changePercent)
                          + (quoteRow.stale ? " · STALE" : " vs close") : "—"
                      color: quoteRow.stale ? root.negativeColor
                        : root.movementColorFor(quoteRow.quote)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      elide: Text.ElideLeft
                    }
                  }
                }

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.inspectSymbol(quoteRow.modelData)
                }
              }
            }

            PanelSeparator { visible: !root.displayingDetails; foreground: root.foreground }

            Text {
              objectName: "selectedQuoteTime"
              width: parent.width
              visible: root.focusedQuote !== null
              textFormat: Text.PlainText
              text: root.focusedQuote ? root.focusedSymbol + " · "
                + MarketModel.quoteSessionLabel(root.focusedQuote) + " · "
                + MarketModel.quoteTimeLabel(root.focusedQuote, root.nowMs) : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              Accessible.name: text
            }

            BorderSurface {
              id: detailCard
              objectName: "marketDetails"
              visible: root.displayingDetails
              width: parent.width
              implicitHeight: detailContent.implicitHeight + contentTopInset + contentBottomInset
              height: implicitHeight
              radius: 0
              color: "transparent"
              borderSpec: Border.none()
              padding: Style.space(4)
              Accessible.name: root.detailQuote
                ? MarketModel.quoteAccessibilityLabel(root.detailQuote, root.nowMs)
                : root.focusedSymbol + ", history unavailable"

              Column {
                id: detailContent
                anchors.fill: parent
                anchors.topMargin: detailCard.contentTopInset
                anchors.rightMargin: detailCard.contentRightInset
                anchors.bottomMargin: detailCard.contentBottomInset
                anchors.leftMargin: detailCard.contentLeftInset
                spacing: Style.space(4)

                Row {
                  width: parent.width
                  height: Math.max(detailIdentity.implicitHeight, detailPrice.implicitHeight)

                  Column {
                    id: detailIdentity
                    width: parent.width * 0.48
                    spacing: Style.space(2)

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: root.detailQuote
                        ? (root.detailQuote.name || root.focusedSymbol) : (root.focusedSymbol || "—")
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: root.detailQuote
                        ? root.focusedSymbol + " · " + MarketModel.quoteUnitLabel(root.detailQuote)
                          + " · " + MarketModel.marketStateLabel(root.detailQuote)
                        : "Quote unavailable"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  Column {
                    id: detailPrice
                    width: parent.width - detailIdentity.width
                    spacing: Style.space(2)

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      horizontalAlignment: Text.AlignRight
                      text: root.detailQuote
                        ? MarketModel.formatQuotePrice(root.detailQuote.regularMarketPrice,
                          root.detailQuote) : "—"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      font.bold: true
                      elide: Text.ElideLeft
                    }

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      horizontalAlignment: Text.AlignRight
                      text: root.detailQuote
                        ? root.directionArrow(root.detailQuote) + " "
                          + MarketModel.formatQuoteDelta(root.detailQuote.change,
                            root.detailQuote) + "  "
                          + MarketModel.formatPercent(root.detailQuote.changePercent) + " vs close"
                        : "—"
                      color: root.movementColorFor(root.detailQuote)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                  }
                }

                Flow {
                  id: marketToolbar
                  width: parent.width
                  spacing: Style.space(5)

                  Repeater {
                    model: MarketModel.rangeOptions()

                    delegate: Button {
                      id: rangeButton
                      required property var modelData
                      text: modelData.label
                      foreground: root.foreground
                      bordered: root.selectedRange === modelData.id
                      horizontalPadding: Style.space(8)
                      verticalPadding: Style.space(5)
                      Accessible.role: Accessible.Button
                      Accessible.name: "Show " + modelData.label + " price history"
                      Accessible.onPressAction: root.chooseRange(rangeButton.modelData.id)
                      onClicked: root.chooseRange(rangeButton.modelData.id)
                    }
                  }

                  Button {
                    text: "Inspect chart"
                    foreground: root.foreground
                    enabled: historyChart.canInspect
                    opacity: enabled ? 1 : 0.4
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(5)
                    tooltipText: "Inspect prices with Left/Right, Home/End; Escape returns (I)"
                    Accessible.role: Accessible.Button
                    Accessible.name: "Inspect chart values"
                    Accessible.onPressAction: root.inspectChart()
                    onClicked: root.inspectChart()
                  }
                }

                Item {
                  width: parent.width
                  height: historyChart.implicitHeight

                  HistoryChart {
                    id: historyChart
                    objectName: "historyChart"
                    plotHeight: Style.space(100)
                    anchors.fill: parent
                    visible: root.rangeResult.direction !== "unknown"
                    points: root.chartQuote ? root.chartQuote.sparkline : []
                    timestamps: root.chartQuote ? root.chartQuote.sparklineTimestamps : []
                    referenceValue: root.rangeResult.first === null ? NaN : root.rangeResult.first
                    lineColor: root.rangeMovementColor()
                    referenceColor: root.dim
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    currency: root.chartQuote ? String(root.chartQuote.currency || "") : ""
                    instrumentType: root.chartQuote ? String(root.chartQuote.instrumentType || "") : ""
                    symbol: root.focusedSymbol
                    seriesKey: root.focusedSymbol + ":" + root.selectedRange
                    onReturnFocus: keyCatcher.forceActiveFocus()
                  }

                  Text {
                    anchors.centerIn: parent
                    width: parent.width
                    visible: root.rangeResult.direction === "unknown"
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: service.historyRefreshing
                      ? "Loading " + MarketModel.rangeLabel(root.selectedRange) + " history…"
                      : "History unavailable for this range"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: MarketModel.rangeLabel(root.selectedRange) + " · "
                    + root.rangeArrow() + " " + MarketModel.formatPercent(root.rangeResult.percent)
                    + " from first plotted price"
                  color: root.rangeMovementColor()
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  wrapMode: Text.Wrap
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: service.historyRefreshing
                    ? "Updating " + MarketModel.rangeLabel(root.selectedRange) + " history…"
                    : root.chartQuote
                      ? MarketModel.asOfLabel(root.chartQuote, root.nowMs)
                        + (service.historyState === "stale" && root.historyMatches ? " · Cached history" : "")
                      : (service.historyError || "Try another range or refresh quotes")
                  color: service.historyState === "stale" ? root.negativeColor : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.Wrap
                }

                Grid {
                  width: parent.width
                  columns: 2
                  columnSpacing: Style.space(14)
                  rowSpacing: Style.space(6)

                  Repeater {
                    model: root.stats

                    delegate: Row {
                      id: statRow
                      required property var modelData
                      width: (detailContent.width - parent.columnSpacing) / 2

                      Text {
                        width: parent.width * 0.45
                        textFormat: Text.PlainText
                        text: statRow.modelData.label
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }

                      Text {
                        width: parent.width * 0.55
                        textFormat: Text.PlainText
                        horizontalAlignment: Text.AlignRight
                        text: statRow.modelData.value
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        elide: Text.ElideLeft
                      }
                    }
                  }
                }

                Row {
                  width: parent.width
                  spacing: Style.space(8)

                  Button {
                    text: root.focusedSymbol === root.primarySymbol ? "Pinned to bar" : "Pin to bar"
                    foreground: root.foreground
                    bordered: root.focusedSymbol !== root.primarySymbol
                    enabled: root.focusedSymbol !== "" && root.focusedSymbol !== root.primarySymbol
                    opacity: enabled ? 1 : 0.55
                    tooltipText: "Pin selected symbol to the bar (P)"
                    Accessible.role: Accessible.Button
                    Accessible.name: text
                    Accessible.onPressAction: root.pinFocused()
                    onClicked: root.pinFocused()
                  }

                  Button {
                    text: "Open quote ↗"
                    foreground: root.foreground
                    enabled: root.focusedSymbol !== ""
                    opacity: enabled ? 1 : 0.4
                    tooltipText: "Open Yahoo Finance (O)"
                    Accessible.role: Accessible.Button
                    Accessible.name: "Open " + (root.focusedSymbol || "quote") + " on Yahoo Finance"
                    Accessible.onPressAction: root.openFocusedQuote()
                    onClicked: root.openFocusedQuote()
                  }
                }
              }
            }
          }

        }
      }

      // Keep the provider footer visible beneath the current compact view.
      Text {
        id: dataFooter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: !root.setupRequired && !root.managing
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: "Yahoo Finance · Unofficial data · Quotes may be delayed"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }
}
