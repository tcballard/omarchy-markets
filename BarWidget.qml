import QtQuick
import qs.Commons
import qs.Ui
import "MarketModel.js" as MarketModel

// The bar surface owns durable, per-instance settings and the private panel.
// Quote polling remains process-wide in Service.qml.
BarWidget {
  id: root
  moduleName: "io.github.tcballard.omarchy-markets"

  function hasOwn(value, key) {
    return value !== null && value !== undefined
      && Object.prototype.hasOwnProperty.call(value, key)
  }

  function boundedInteger(value, fallback, minimum, maximum) {
    var parsed = parseInt(String(value), 10)
    if (!isFinite(parsed)) parsed = fallback
    return Math.max(minimum, Math.min(maximum, parsed))
  }

  // Consent is deliberately strict: only the JSON boolean true enables data.
  readonly property bool dataEnabled: setting("dataEnabled", false) === true
  readonly property string profileId: {
    var normalized = MarketModel.normalizeProfileId(String(setting("profile", "")), "")
    return normalized || ""
  }
  readonly property string configuredSymbolsText: String(setting("symbols", ""))
  readonly property var configuredSymbols: MarketModel.normalizeSymbols(configuredSymbolsText)
  readonly property string requestedPrimarySymbol: {
    var normalized = MarketModel.normalizeSymbols([String(setting("primarySymbol", ""))], 1)
    return normalized.length > 0 ? normalized[0] : ""
  }
  readonly property string primarySymbol: configuredSymbols.indexOf(requestedPrimarySymbol) >= 0
    ? requestedPrimarySymbol : (configuredSymbols.length > 0 ? configuredSymbols[0] : "")
  readonly property string selectedRange: MarketModel.normalizeRange(
    String(setting("selectedRange", "1d")), "1d")
  readonly property string barMode: MarketModel.normalizeBarMode(
    String(setting("barMode", "ticker")), "ticker")
  readonly property bool showPrice: setting("showPrice", true) === true
  readonly property int tickerWidth: boundedInteger(setting("tickerWidth", 220), 220, 160, 640)
  readonly property int tickerSpeed: boundedInteger(setting("tickerSpeed", 24), 24, 0, 80)
  readonly property bool tickerPaused: setting("tickerPaused", false) === true
  readonly property int refreshInterval: boundedInteger(
    setting("refreshIntervalSec", setting("refreshInterval", 900)), 900, 300, 3600)

  readonly property color barForeground: root.bar ? root.bar.barForeground : Color.foreground
  readonly property color barBackground: root.bar ? root.bar.background : Color.background
  readonly property color positiveBright: "#30d158"
  readonly property color positiveDark: "#137333"
  readonly property color negativeBright: "#ff453a"
  readonly property color negativeDark: "#b3261e"

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
    // A translucent bar sits over arbitrary wallpaper, so only its configured
    // foreground has a dependable contrast contract.
    if (background.a < 0.85) return fallback
    var brightRatio = contrastRatio(bright, background)
    var darkRatio = contrastRatio(dark, background)
    var candidate = brightRatio >= darkRatio ? bright : dark
    return Math.max(brightRatio, darkRatio) >= 4.5 ? candidate : fallback
  }

  readonly property color positiveColor: contrastAwareColor(
    barBackground, positiveBright, positiveDark, barForeground)
  readonly property color negativeColor: contrastAwareColor(
    barBackground, negativeBright, negativeDark, barForeground)

  // Referencing _services makes the lookup reactive when the host mounts the
  // singleton after the visual widget.
  readonly property var marketService: {
    var servicesRevision = root.bar && root.bar.shell ? root.bar.shell._services : null
    if (!servicesRevision || !root.bar || !root.bar.shell
        || typeof root.bar.shell.serviceFor !== "function") return null
    return root.bar.shell.serviceFor(root.moduleName)
  }
  readonly property int serviceRevision: marketService ? marketService.revision : 0
  readonly property string serviceState: marketService ? String(marketService.state || "waiting") : "waiting"
  readonly property bool setupRequired: !dataEnabled || configuredSymbols.length === 0
  readonly property bool tickerActive: !root.vertical && barMode === "ticker"

  readonly property var validQuotes: {
    var revision = serviceRevision
    var source = marketService && Array.isArray(marketService.quotes)
      ? marketService.quotes : []
    var result = []
    for (var index = 0; index < configuredSymbols.length; index += 1) {
      var quote = MarketModel.findQuote(source, configuredSymbols[index])
      if (quote) result.push(quote)
    }
    return result
  }
  readonly property var displayQuote: marketService
    ? MarketModel.findQuote(marketService.quotes, primarySymbol) : null
  readonly property var tickerLoopQuotes: validQuotes.concat(validQuotes)

  function quoteCached(quote) {
    return !!quote && quote.cached === true
  }

  function quoteStale(quote) {
    return !!quote && (quote.stale === true || quote.cached === true || serviceState === "stale")
  }

  function anyTickerQuote(flagName) {
    for (var index = 0; index < validQuotes.length; index += 1) {
      if (flagName === "cached" && quoteCached(validQuotes[index])) return true
      if (flagName === "stale" && quoteStale(validQuotes[index])) return true
    }
    return false
  }

  readonly property bool shownCached: tickerActive
    ? anyTickerQuote("cached") : quoteCached(displayQuote)
  readonly property bool shownStale: tickerActive
    ? anyTickerQuote("stale") : quoteStale(displayQuote)
  readonly property bool hasShownQuote: tickerActive
    ? validQuotes.length > 0 : displayQuote !== null
  readonly property bool errorState: [
    "dependency-missing", "offline", "failed", "malformed", "invalid"
  ].indexOf(serviceState) >= 0

  function marketClosed(quote) {
    if (!quote) return false
    var state = String(quote.sessionState || quote.marketState || "").toLowerCase()
    return state === "closed" || state === "market_closed" || state === "regular_market_closed"
  }

  readonly property string stateText: {
    if (setupRequired || serviceState === "setup" || serviceState === "empty") return "SET UP"
    if (!marketService || ((marketService.refreshing || serviceState === "loading"
        || serviceState === "waiting") && !hasShownQuote)) return "LOADING"
    if (shownCached) return "CACHED"
    if (shownStale) return "STALE"
    if (errorState && !hasShownQuote) return "ERROR"
    if (serviceState === "partial") return "PARTIAL"
    if (!tickerActive && marketClosed(displayQuote)) return "CLOSED"
    if (serviceState === "disabled") return "PAUSED"
    if (!hasShownQuote) return marketService.lastError ? "ERROR" : "LOADING"
    return ""
  }
  readonly property color stateColor: stateText === "ERROR" || stateText === "STALE"
    ? negativeColor : barForeground

  function directionArrow(quote) {
    var direction = MarketModel.changeDirection(quote)
    if (direction === "up") return "▲"
    if (direction === "down") return "▼"
    if (direction === "flat") return "→"
    return "—"
  }

  function quoteChangeText(quote) {
    if (!quote) return "—"
    var percent = MarketModel.formatPercent(quote.changePercent)
    if (percent === "—") return "—"
    return directionArrow(quote) + " " + percent
  }

  function movementColorFor(quote) {
    var direction = MarketModel.changeDirection(quote)
    if (direction === "up") return positiveColor
    if (direction === "down") return negativeColor
    return barForeground
  }

  function stateDetail() {
    if (stateText === "SET UP") {
      return dataEnabled
        ? "Choose at least one symbol to start market data."
        : "Market data is off. Open Omarchy Markets to choose a profile or enable a custom watchlist."
    }
    if (stateText === "LOADING") return "Loading market quotes."
    if (stateText === "CACHED") return "Showing cached market data."
    if (stateText === "STALE") return "Showing stale last-known market data."
    if (stateText === "PARTIAL") return "Some watchlist quotes are unavailable."
    if (stateText === "CLOSED") return "The primary market is closed."
    if (stateText === "PAUSED") return "Market polling is paused while this widget is inactive."
    if (stateText === "ERROR") {
      return marketService && marketService.lastError
        ? String(marketService.lastError) : "Market data is unavailable."
    }
    if (displayQuote) return MarketModel.changeAccessibilityLabel(displayQuote)
      + " · " + MarketModel.formatFreshness(displayQuote.marketTime)
    return "Market data ready."
  }

  readonly property string singleBarText: {
    var pieces = [displayQuote ? String(displayQuote.symbol) : (primarySymbol || "MARKETS")]
    if (displayQuote && showPrice)
      pieces.push(MarketModel.formatPrice(displayQuote.regularMarketPrice, displayQuote.currency))
    if (displayQuote) pieces.push(quoteChangeText(displayQuote))
    if (stateText !== "") pieces.push(stateText)
    return pieces.join("  ")
  }
  readonly property string tickerBarText: validQuotes.length > 0
    ? validQuotes.map(function(quote) {
        var pieces = [String(quote.symbol)]
        if (showPrice) pieces.push(MarketModel.formatPrice(quote.regularMarketPrice, quote.currency))
        pieces.push(quoteChangeText(quote))
        return pieces.join(" ")
      }).join(" · ") + (stateText !== "" ? " · " + stateText : "")
    : (primarySymbol || "MARKETS") + "  " + stateText
  readonly property string accessibilityLabel: {
    if (tickerActive && validQuotes.length > 0) {
      var labels = []
      for (var index = 0; index < validQuotes.length; index += 1)
        labels.push(MarketModel.quoteAccessibilityLabel(validQuotes[index]))
      return "Omarchy Markets ticker. " + labels.join("; ")
        + (stateText !== "" ? ". Status: " + stateText : "")
    }
    if (displayQuote) return MarketModel.quoteAccessibilityLabel(displayQuote)
      + (stateText !== "" ? ", " + stateText.toLowerCase() : "")
    return "Omarchy Markets. " + stateDetail()
  }
  readonly property string tooltipText: stateDetail()
    + "\nLeft: open markets · Middle: refresh · "
    + (tickerActive ? "Right: pause or resume ticker · Hover: pause temporarily"
      : "Right: refresh")

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property real openPanelIndicatorWidth: root.vertical ? 0 : button.width
  readonly property real openPanelIndicatorHeight: Math.max(
    Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  function normalizedSettingsPatch(patch, entry) {
    if (!patch || typeof patch !== "object") return entry

    if (hasOwn(patch, "dataEnabled")) entry.dataEnabled = patch.dataEnabled === true
    if (hasOwn(patch, "profile")) {
      var normalizedProfile = MarketModel.normalizeProfileId(String(patch.profile || ""), "")
      entry.profile = normalizedProfile || ""
    }
    if (hasOwn(patch, "symbols")) {
      entry.symbols = MarketModel.normalizeSymbols(patch.symbols).join(", ")
      if (!hasOwn(patch, "profile")) entry.profile = ""
    }
    if (hasOwn(patch, "primarySymbol")) {
      var normalizedPrimary = MarketModel.normalizeSymbols([String(patch.primarySymbol || "")], 1)
      entry.primarySymbol = normalizedPrimary.length > 0 ? normalizedPrimary[0] : ""
    }
    if (hasOwn(patch, "selectedRange"))
      entry.selectedRange = MarketModel.normalizeRange(String(patch.selectedRange), selectedRange)
    if (hasOwn(patch, "barMode"))
      entry.barMode = MarketModel.normalizeBarMode(String(patch.barMode), barMode)
    if (hasOwn(patch, "showPrice")) entry.showPrice = patch.showPrice === true
    if (hasOwn(patch, "tickerWidth"))
      entry.tickerWidth = boundedInteger(patch.tickerWidth, tickerWidth, 160, 640)
    if (hasOwn(patch, "tickerSpeed"))
      entry.tickerSpeed = boundedInteger(patch.tickerSpeed, tickerSpeed, 0, 80)
    if (hasOwn(patch, "tickerPaused")) entry.tickerPaused = patch.tickerPaused === true
    if (hasOwn(patch, "refreshIntervalSec") || hasOwn(patch, "refreshInterval")) {
      var intervalValue = hasOwn(patch, "refreshIntervalSec")
        ? patch.refreshIntervalSec : patch.refreshInterval
      entry.refreshIntervalSec = boundedInteger(intervalValue, refreshInterval, 300, 3600)
      delete entry.refreshInterval
    }

    var finalSymbols = MarketModel.normalizeSymbols(entry.symbols || "")
    var finalPrimary = MarketModel.normalizeSymbols([String(entry.primarySymbol || "")], 1)
    entry.symbols = finalSymbols.join(", ")
    entry.primarySymbol = finalPrimary.length > 0
      && finalSymbols.indexOf(finalPrimary[0]) >= 0
      ? finalPrimary[0] : (finalSymbols.length > 0 ? finalSymbols[0] : "")
    return entry
  }

  function persistSettings(patch) {
    var entry = { id: root.moduleName }
    if (root.settings && typeof root.settings === "object") {
      for (var key in root.settings) {
        if (key !== "id" && root.hasOwn(root.settings, key)) entry[key] = root.settings[key]
      }
    }
    entry = normalizedSettingsPatch(patch, entry)
    root.settings = entry
    if (root.bar && root.bar.shell
        && typeof root.bar.shell.updateEntryInline === "function") {
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    }
    Qt.callLater(root.injectPanel)
    return entry
  }

  function applyProfile(profileValue) {
    var profile = MarketModel.profileById(profileValue)
    if (!profile) return false
    persistSettings({
      dataEnabled: true,
      profile: profile.id,
      symbols: profile.symbols,
      primarySymbol: profile.primarySymbol
    })
    return true
  }

  function setSymbols(symbolsValue) {
    var normalized = MarketModel.normalizeSymbols(symbolsValue)
    persistSettings({ profile: "", symbols: normalized })
    return normalized
  }

  function addSymbol(symbolValue) {
    var result = MarketModel.addSymbol(configuredSymbols, symbolValue)
    if (result.ok && result.changed) {
      persistSettings({
        profile: "",
        symbols: result.symbols,
        primarySymbol: primarySymbol || result.symbol
      })
    }
    return result
  }

  function removeSymbol(symbolValue) {
    var result = MarketModel.removeSymbol(configuredSymbols, symbolValue)
    if (result.ok && result.changed) {
      var nextPrimary = result.symbols.indexOf(primarySymbol) >= 0
        ? primarySymbol : (result.symbols.length > 0 ? result.symbols[0] : "")
      persistSettings({ profile: "", symbols: result.symbols, primarySymbol: nextPrimary })
    }
    return result
  }

  function moveSymbol(symbolOrIndex, destinationIndex) {
    var result = MarketModel.moveSymbol(configuredSymbols, symbolOrIndex, destinationIndex)
    if (result.ok && result.changed)
      persistSettings({ profile: "", symbols: result.symbols })
    return result
  }

  function setPrimarySymbol(symbolValue) {
    var normalized = MarketModel.normalizeSymbols([symbolValue], 1)
    if (normalized.length === 0 || configuredSymbols.indexOf(normalized[0]) < 0) return false
    persistSettings({ primarySymbol: normalized[0] })
    return true
  }

  function setRange(rangeValue) {
    var normalized = MarketModel.normalizeRange(rangeValue, selectedRange)
    persistSettings({ selectedRange: normalized })
    return normalized
  }

  function setBarMode(modeValue) {
    var normalized = MarketModel.normalizeBarMode(modeValue, barMode)
    persistSettings({ barMode: normalized })
    return normalized
  }

  function setDataEnabled(enabledValue) {
    var enabled = enabledValue === true
    persistSettings({ dataEnabled: enabled })
    return enabled
  }

  function setTickerPaused(pausedValue) {
    var paused = pausedValue === true
    persistSettings({ tickerPaused: paused })
    return paused
  }

  function configureService() {
    if (marketService && typeof marketService.configure === "function")
      marketService.configure(configuredSymbols, refreshInterval, dataEnabled)
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("marketService" in target) target.marketService = root.marketService
  }

  function open() {
    if (panelLoader.item && typeof panelLoader.item.open === "function") panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && typeof panelLoader.item.close === "function") panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item && typeof panelLoader.item.toggle === "function") panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item && typeof panelLoader.item.closeForPopoutSwitch === "function")
      panelLoader.item.closeForPopoutSwitch()
  }

  function refresh() {
    if (marketService && typeof marketService.refresh === "function") marketService.refresh()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: {
    injectPanel()
    Qt.callLater(configureService)
  }
  onSettingsChanged: {
    injectPanel()
    Qt.callLater(configureService)
  }
  onMarketServiceChanged: {
    injectPanel()
    Qt.callLater(configureService)
  }
  onConfiguredSymbolsTextChanged: Qt.callLater(configureService)
  onRefreshIntervalChanged: Qt.callLater(configureService)
  onDataEnabledChanged: Qt.callLater(configureService)
  Component.onCompleted: Qt.callLater(configureService)

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.tickerActive ? root.tickerBarText : root.singleBarText
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : (root.tickerActive
      ? root.tickerWidth
      : Math.max(Style.space(12), singleContent.implicitWidth + button.scaledHorizontalMargin * 2))
    fixedHeight: root.vertical ? Style.bar.iconSlot * 2 : -1
    horizontalMargin: 8.75
    verticalPadding: 6
    foreground: root.barForeground
    dimmed: false
    tooltipText: root.tooltipText
    Accessible.role: Accessible.Button
    Accessible.name: root.accessibilityLabel
    Accessible.description: root.tickerActive
      ? "Open Omarchy Markets; middle-click to refresh; right-click to pause or resume ticker"
      : "Open Omarchy Markets; middle-click or right-click to refresh"
    Accessible.onPressAction: root.togglePanel()

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.togglePanel()
      else if (mouseButton === Qt.RightButton && root.tickerActive)
        root.setTickerPaused(!root.tickerPaused)
      else root.refresh()
    }

    Row {
      id: singleContent
      visible: !root.vertical && !root.tickerActive
      anchors.centerIn: parent
      spacing: Style.space(6)

      Text {
        textFormat: Text.PlainText
        text: root.displayQuote ? String(root.displayQuote.symbol) : (root.primarySymbol || "MARKETS")
        color: root.barForeground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        font.bold: true
        renderType: Text.NativeRendering
      }

      Text {
        visible: root.displayQuote && root.showPrice
        textFormat: Text.PlainText
        text: root.displayQuote
          ? MarketModel.formatPrice(root.displayQuote.regularMarketPrice, root.displayQuote.currency) : ""
        color: root.barForeground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }

      Text {
        visible: root.displayQuote !== null
        textFormat: Text.PlainText
        text: root.quoteChangeText(root.displayQuote)
        color: root.movementColorFor(root.displayQuote)
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        font.bold: true
        renderType: Text.NativeRendering
      }

      Text {
        visible: root.stateText !== ""
        textFormat: Text.PlainText
        text: root.stateText
        color: root.stateColor
        font.family: button.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        renderType: Text.NativeRendering
      }
    }

    Row {
      id: tickerLayout
      visible: root.tickerActive && root.validQuotes.length > 0
      anchors.fill: parent
      anchors.leftMargin: button.scaledHorizontalMargin
      anchors.rightMargin: button.scaledHorizontalMargin
      spacing: Style.space(6)

      Text {
        id: tickerStatusLabel
        visible: root.stateText !== ""
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.stateText
        color: root.stateColor
        font.family: button.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        renderType: Text.NativeRendering
      }

      Item {
        id: tickerClip
        width: Math.max(1, tickerLayout.width
          - (tickerStatusLabel.visible ? tickerStatusLabel.implicitWidth + tickerLayout.spacing : 0))
        height: tickerLayout.height
        clip: true

        readonly property real cycleWidth: (tickerTrack.implicitWidth + tickerTrack.spacing) / 2
        readonly property bool canScroll: root.tickerSpeed > 0
          && cycleWidth > width + Style.space(4)

        Row {
          id: tickerTrack
          height: tickerClip.height
          spacing: Style.space(14)

          Repeater {
            model: root.tickerLoopQuotes

            delegate: Row {
              required property var modelData
              height: tickerTrack.height
              spacing: Style.space(5)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: String(parent.modelData.symbol)
                color: root.barForeground
                font.family: button.fontFamily
                font.pixelSize: button.fontSize
                font.bold: true
                renderType: Text.NativeRendering
              }

              Text {
                visible: root.showPrice
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: MarketModel.formatPrice(
                  parent.modelData.regularMarketPrice, parent.modelData.currency)
                color: root.barForeground
                font.family: button.fontFamily
                font.pixelSize: button.fontSize
                renderType: Text.NativeRendering
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.quoteChangeText(parent.modelData)
                color: root.movementColorFor(parent.modelData)
                font.family: button.fontFamily
                font.pixelSize: button.fontSize
                font.bold: true
                renderType: Text.NativeRendering
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "·"
                color: root.barForeground
                opacity: 0.58
                font.family: button.fontFamily
                font.pixelSize: button.fontSize
                renderType: Text.NativeRendering
              }
            }
          }

          NumberAnimation {
            id: tickerAnimation
            target: tickerTrack
            property: "x"
            from: 0
            to: -tickerClip.cycleWidth
            duration: Math.max(1000, Math.round(tickerClip.cycleWidth
              / Math.max(1, root.tickerSpeed) * 1000))
            loops: Animation.Infinite
            running: root.tickerActive && tickerClip.canScroll
            paused: root.tickerPaused || tickerHover.containsMouse
            onRunningChanged: {
              if (!running) tickerTrack.x = 0
            }
          }

          MouseArea {
            id: tickerHover
            parent: tickerClip
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            propagateComposedEvents: true
          }
        }
      }
    }

    Text {
      visible: !root.vertical && root.tickerActive && root.validQuotes.length === 0
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: (root.primarySymbol || "MARKETS") + "  " + root.stateText
      color: root.stateText === "" ? root.barForeground : root.stateColor
      font.family: button.fontFamily
      font.pixelSize: button.fontSize
      font.bold: true
      renderType: Text.NativeRendering
    }

    Column {
      visible: root.vertical
      anchors.centerIn: parent
      width: button.width
      spacing: 0

      Text {
        width: parent.width
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        text: root.primarySymbol ? root.primarySymbol.substring(0, 5) : "MKT"
        color: root.barForeground
        font.family: button.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        text: root.stateText !== "" ? root.stateText : root.quoteChangeText(root.displayQuote)
        color: root.stateText !== ""
          ? root.stateColor : root.movementColorFor(root.displayQuote)
        font.family: button.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        elide: Text.ElideRight
      }
    }
  }
}
