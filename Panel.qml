import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "MarketModel.js" as MarketModel

// Private, bar-attached market surface. The watchlist remains the primary
// navigation model; inspecting a row and pinning it to the bar are separate.
Panel {
  id: root
  moduleName: "io.github.tcballard.omarchy-markets"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var marketService: null
  property int selectedIndex: 0
  property int setupCursor: 0
  property bool keyboardCursor: false
  property bool managing: false
  property string managerMessage: ""
  property double nowMs: Date.now()

  readonly property var barIdentity: hostWidget || root
  readonly property bool dataEnabled: hostWidget ? hostWidget.dataEnabled === true : false
  readonly property var symbols: hostWidget && Array.isArray(hostWidget.configuredSymbols)
    ? hostWidget.configuredSymbols : []
  readonly property string primarySymbol: hostWidget ? String(hostWidget.primarySymbol || "")
    : (symbols.length > 0 ? symbols[0] : "")
  readonly property string selectedRange: hostWidget
    ? String(hostWidget.selectedRange || "1d") : "1d"
  readonly property string barMode: hostWidget ? String(hostWidget.barMode || "ticker") : "ticker"
  readonly property string profileId: hostWidget ? String(hostWidget.profileId || "") : ""
  readonly property var profile: MarketModel.profileById(profileId)
  readonly property var profiles: MarketModel.profiles()
  readonly property bool setupRequired: !dataEnabled || symbols.length === 0
  readonly property string focusedSymbol: symbols.length > 0
    ? symbols[Math.max(0, Math.min(symbols.length - 1, selectedIndex))] : ""
  readonly property var focusedQuote: MarketModel.findQuote(service.quotes, focusedSymbol)
  readonly property bool historyMatches: service.historySymbol === focusedSymbol
    && service.historyRange === selectedRange
  readonly property var detailQuote: historyMatches && service.historyQuote
    ? service.historyQuote : focusedQuote
  readonly property var rangeResult: MarketModel.rangePerformance(
    detailQuote && Array.isArray(detailQuote.sparkline) ? detailQuote.sparkline : [])
  readonly property var stats: MarketModel.statRows(detailQuote)
  readonly property color foreground: Color.popups.text
  // Muted is a global palette token, not a promise of readable popup text.
  // Fall back to the popup's text role for low contrast or translucent themes.
  readonly property color dim: popupBackground.a < 0.85 || Color.muted.a < 1
    || contrastRatio(Color.muted, popupBackground) < 4.5 ? foreground : Color.muted
  readonly property color popupBackground: Color.popups.background
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
    var index = symbols.indexOf(primarySymbol)
    selectedIndex = index >= 0 ? index : 0
    keyboardCursor = false
    if (watchlist) watchlist.currentIndex = selectedIndex
    requestFocusedHistory()
  }

  function open() {
    managing = false
    managerMessage = ""
    syncSelection()
    root.controller.show()
    panelScroll.contentY = 0
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
      Qt.callLater(root.revealSetupSelection)
      return
    }
    if (managing) {
      if (symbols.length === 0) return
      selectedIndex = (selectedIndex + delta + symbols.length) % symbols.length
      keyboardCursor = true
      Qt.callLater(root.revealManagerSelection)
      return
    }
    if (symbols.length === 0) return
    keyboardCursor = true
    selectedIndex = (selectedIndex + delta + symbols.length) % symbols.length
    watchlist.currentIndex = selectedIndex
    requestFocusedHistory()
    Qt.callLater(root.revealSelection)
  }

  function moveRange(delta) {
    if (setupRequired || managing || focusedSymbol === "") return
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
    requestFocusedHistory()
  }

  function revealItem(item) {
    if (!panelScroll) return
    if (!item) return
    var mapped = item.mapToItem(contentColumn, 0, 0)
    var top = mapped.y
    var bottom = top + item.height
    var viewportTop = panelScroll.contentY
    var viewportBottom = viewportTop + panelScroll.height
    var maximum = Math.max(0, panelScroll.contentHeight - panelScroll.height)
    if (top < viewportTop)
      panelScroll.contentY = Math.max(0, Math.min(top, maximum))
    else if (bottom > viewportBottom)
      panelScroll.contentY = Math.max(0, Math.min(bottom - panelScroll.height, maximum))
  }

  function revealSetupSelection() {
    revealItem(setupCursor < profiles.length
      ? profileRepeater.itemAt(setupCursor) : startCustomButton)
  }

  function revealSelection() {
    if (!watchlist || selectedIndex < 0) return
    revealItem(watchlist.itemAtIndex(selectedIndex))
  }

  function revealManagerSelection() {
    if (!managerRepeater || selectedIndex < 0) return
    revealItem(managerRepeater.itemAt(selectedIndex))
  }

  function inspectSymbol(symbol, index) {
    selectedIndex = index
    keyboardCursor = false
    if (watchlist) watchlist.currentIndex = index
    requestFocusedHistory()
  }

  function requestFocusedHistory() {
    if (focusedSymbol === "" || !dataEnabled) return
    if (service && typeof service.requestHistory === "function")
      service.requestHistory(focusedSymbol, selectedRange)
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
    var result = hostWidget.removeSymbol(symbol)
    managerMessage = result.message
    selectedIndex = Math.max(0, Math.min(selectedIndex, result.symbols.length - 1))
  }

  function moveManagedSymbol(symbol, destination) {
    if (!hostWidget || typeof hostWidget.moveSymbol !== "function") return
    var inspected = focusedSymbol
    var result = hostWidget.moveSymbol(symbol, destination)
    managerMessage = result.message
    if (result.ok && result.changed) {
      var nextIndex = result.symbols.indexOf(inspected)
      selectedIndex = nextIndex >= 0 ? nextIndex : 0
      Qt.callLater(root.requestFocusedHistory)
    }
  }

  function managerShortcut(text) {
    if (text === "a" || text === "A") symbolInput.forceActiveFocus()
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
    if (service.state === "partial") return "Some quotes unavailable"
    if (service.state === "dependency-missing") return "Python 3 needed"
    if (service.state === "offline") return "Offline"
    if (service.state === "failed" || service.state === "malformed") return "Unavailable"
    if (service.lastUpdated && service.lastUpdated.getTime() > 0)
      return MarketModel.formatFreshness(service.lastUpdated, nowMs)
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

  onManagingChanged: if (panelScroll) panelScroll.contentY = 0
  onSetupRequiredChanged: if (panelScroll) panelScroll.contentY = 0

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: symbolInput.activeFocus
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
        if (text === "r" || text === "R") root.refresh()
        else if (text === "o" || text === "O") root.openFocusedQuote()
        else if (text === "p" || text === "P") root.pinFocused()
        else if (text === "m" || text === "M") root.managing = true
      }

      Flickable {
        id: panelScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        onContentHeightChanged: contentY = Math.max(0, Math.min(contentY, contentHeight - height))
        onHeightChanged: contentY = Math.max(0, Math.min(contentY, contentHeight - height))

        Column {
          id: contentColumn
          // Keep a stable gutter: content height must not change its own width
          // through scrollbar visibility and trigger a wrapping/height loop.
          width: Math.max(0, panelScroll.width - Style.space(12))
          spacing: Style.space(12)

          Row {
            width: parent.width
            height: Math.max(titleBlock.implicitHeight, headerActions.implicitHeight)

            Column {
              id: titleBlock
              width: parent.width - headerActions.width - Style.space(8)
              spacing: Style.space(2)

              Text {
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
                text: root.profile ? root.profile.name + " · " + root.stateLabel() : root.stateLabel()
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
            id: marketToolbar
            visible: !root.setupRequired && !root.managing
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: MarketModel.rangeOptions()

              delegate: Button {
                id: toolbarRangeButton
                required property var modelData
                text: modelData.label
                foreground: root.foreground
                bordered: root.selectedRange === modelData.id
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(5)
                Accessible.role: Accessible.Button
                Accessible.name: "Show " + modelData.label + " price history"
                Accessible.onPressAction: root.chooseRange(toolbarRangeButton.modelData.id)
                onClicked: root.chooseRange(toolbarRangeButton.modelData.id)
              }
            }

            Item {
              width: Math.max(0, marketToolbar.width - toolbarStatus.implicitWidth
                - Style.space(180))
              height: 1
            }

            Text {
              id: toolbarStatus
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.stateLabel()
              color: root.statusIsWarning() ? root.negativeColor : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            id: setupView
            visible: root.setupRequired && !root.managing
            width: parent.width
            spacing: Style.space(12)

            BorderSurface {
              width: parent.width
              implicitHeight: setupIntro.implicitHeight + contentTopInset + contentBottomInset
              height: implicitHeight
              radius: Math.max(Style.cornerRadius, Style.space(16))
              color: Style.normalFillFor(root.foreground, Color.accent, Color.urgent)
              borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
              padding: Style.space(16)

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
                  font.pixelSize: Style.font.body
                }
              }
            }

            Repeater {
              id: profileRepeater
              model: root.profiles

              delegate: BorderSurface {
                id: profileCard
                required property var modelData
                required property int index
                width: setupView.width
                implicitHeight: profileContent.implicitHeight + contentTopInset + contentBottomInset
                height: implicitHeight
                radius: Math.max(Style.cornerRadius, Style.space(13))
                color: root.setupCursor === index
                  ? Style.selectedFillFor(root.foreground, Color.accent, Color.urgent)
                  : profileMouse.containsMouse
                  ? Style.hoverFillFor(root.foreground, Color.accent, Color.urgent)
                  : "transparent"
                borderSpec: Border.controlSpec(root.setupCursor === index ? "focus" : "normal",
                  root.foreground, Color.accent)
                padding: Style.space(12)
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
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Button {
                    id: chooseProfileButton
                    text: "Choose"
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
            visible: root.managing
            width: parent.width
            spacing: Style.space(12)

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

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "WATCHLIST MANAGER"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.1
            }

            Text {
              width: parent.width
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: "Add Yahoo-style public symbols, then reorder or remove them. Up to 12 symbols."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              BorderSurface {
                width: parent.width - addButton.width - parent.spacing
                height: Math.max(Style.space(40), addButton.height)
                radius: 0
                color: Style.normalFillFor(root.foreground, Color.accent, Color.urgent)
                borderSpec: Border.controlSpec(symbolInput.activeFocus ? "focus" : "normal",
                  root.foreground, Color.accent)
                padding: Style.space(9)

                TextInput {
                  id: symbolInput
                  anchors.fill: parent
                  anchors.leftMargin: parent.contentLeftInset
                  anchors.rightMargin: parent.contentRightInset
                  verticalAlignment: TextInput.AlignVCenter
                  color: root.foreground
                  selectionColor: Color.accent
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

            Repeater {
              id: managerRepeater
              model: root.symbols

              delegate: BorderSurface {
                id: managerRow
                required property string modelData
                required property int index
                readonly property bool selected: root.selectedIndex === index
                width: managerView.width
                height: Style.space(48)
                radius: 0
                color: selected
                  ? Style.selectedFillFor(root.foreground, Color.accent, Color.urgent)
                  : "transparent"
                borderSpec: Border.controlSpec(selected ? "focus" : "normal",
                  root.foreground, Color.accent)

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
                    text: "Remove"
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

            Text {
              width: parent.width
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: "Keyboard: ↑/↓ select · [/] reorder · P pin · X/Delete remove · A add · M back"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            id: marketsView
            visible: !root.setupRequired && !root.managing
            width: parent.width
            spacing: Style.space(12)

            Row {
              visible: false
              width: parent.width

              Text {
                width: parent.width - countLabel.width
                textFormat: Text.PlainText
                text: "WATCHLIST"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.1
              }

              Text {
                id: countLabel
                textFormat: Text.PlainText
                text: String(root.symbols.length)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            ListView {
              id: watchlist
              readonly property int rowHeight: Style.space(44)
              readonly property int rowSpacing: 0
              readonly property int rowsHeight: root.symbols.length * rowHeight
                + Math.max(0, root.symbols.length - 1) * rowSpacing
              width: parent.width
              height: rowsHeight
              clip: false
              interactive: false
              boundsBehavior: Flickable.StopAtBounds
              model: root.symbols
              currentIndex: root.selectedIndex
              spacing: rowSpacing

              delegate: BorderSurface {
                id: quoteRow
                required property string modelData
                required property int index
                property var quote: MarketModel.findQuote(service.quotes, modelData)
                readonly property bool inspected: root.selectedIndex === index
                readonly property bool pinned: modelData === root.primarySymbol
                readonly property bool stale: service.state === "stale"
                  || (quote && (quote.stale === true || quote.cached === true))
                width: ListView.view.width
                height: watchlist.rowHeight
                radius: Style.cornerRadius
                color: inspected
                  ? Style.selectedFillFor(root.foreground, Color.accent, Color.urgent)
                  : rowMouse.containsMouse
                    ? Style.hoverFillFor(root.foreground, Color.accent, Color.urgent)
                    : "transparent"
                borderSpec: root.keyboardCursor && inspected
                  ? Border.controlSpec("focus", root.foreground, Color.accent)
                  : inspected
                    ? Border.controlSpec("selected", root.foreground, Color.accent)
                    : Border.none()
                Accessible.role: Accessible.Button
                Accessible.name: quote
                  ? MarketModel.quoteAccessibilityLabel(quote, root.nowMs)
                    + (pinned ? ", pinned to bar" : "")
                  : modelData + ", quote unavailable"
                Accessible.description: "Activate to inspect. Pinning is a separate action."
                Accessible.onPressAction: root.inspectSymbol(quoteRow.modelData, quoteRow.index)

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(9)

                  Text {
                    id: rowSymbol
                    width: Style.space(64)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: quoteRow.modelData
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Text {
                    width: Math.max(Style.space(76), parent.width - rowSymbol.width
                      - rowSpark.width - rowPrice.width - rowChange.width
                      - parent.spacing * 4)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: quoteRow.quote ? quoteRow.quote.name : "Unavailable"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }

                  Sparkline {
                    id: rowSpark
                    width: Style.space(72)
                    height: Style.space(24)
                    anchors.verticalCenter: parent.verticalCenter
                    points: quoteRow.quote
                      ? quoteRow.quote.sparkline : []
                    timestamps: quoteRow.quote ? quoteRow.quote.sparklineTimestamps : []
                    referenceValue: quoteRow.quote ? quoteRow.quote.previousClose : NaN
                    lineColor: root.movementColorFor(quoteRow.quote)
                    referenceColor: root.dim
                    showGrid: false
                  }

                  Text {
                    id: rowPrice
                    width: Style.space(76)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignRight
                    text: quoteRow.quote
                      ? MarketModel.formatPrice(quoteRow.quote.regularMarketPrice,
                        quoteRow.quote.currency) : "—"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    id: rowChange
                    width: Style.space(112)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignRight
                    text: quoteRow.quote
                      ? root.directionArrow(quoteRow.quote) + " "
                        + MarketModel.formatPercent(quoteRow.quote.changePercent)
                        + (quoteRow.stale ? " · STALE" : "") : "—"
                    color: quoteRow.stale ? root.negativeColor
                      : root.movementColorFor(quoteRow.quote)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    elide: Text.ElideLeft
                  }
                }

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.inspectSymbol(quoteRow.modelData, quoteRow.index)
                }
              }
            }

            PanelSeparator { foreground: root.foreground }

            BorderSurface {
              id: detailCard
              width: parent.width
              implicitHeight: detailContent.implicitHeight + contentTopInset + contentBottomInset
              height: implicitHeight
              radius: 0
              color: "transparent"
              borderSpec: Border.none()
              padding: Style.space(8)
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
                spacing: Style.space(9)

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
                        ? root.focusedSymbol + " · " + String(root.detailQuote.currency || "")
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
                        ? MarketModel.formatPrice(root.detailQuote.regularMarketPrice,
                          root.detailQuote.currency) : "—"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      font.bold: true
                    }

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      horizontalAlignment: Text.AlignRight
                      text: root.detailQuote
                        ? root.directionArrow(root.detailQuote) + " "
                          + MarketModel.formatDelta(root.detailQuote.change,
                            root.detailQuote.currency) + "  "
                          + MarketModel.formatPercent(root.detailQuote.changePercent) + " today"
                        : "—"
                      color: root.movementColorFor(root.detailQuote)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }
                }

                Row {
                  visible: false
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
                }

                Sparkline {
                  width: parent.width
                  height: Style.space(112)
                  points: root.detailQuote
                    ? root.detailQuote.sparkline : []
                  timestamps: root.detailQuote ? root.detailQuote.sparklineTimestamps : []
                  referenceValue: root.detailQuote ? root.detailQuote.previousClose : NaN
                  lineColor: root.rangeMovementColor()
                  referenceColor: root.dim
                  showGrid: true
                }

                Row {
                  width: parent.width

                  Text {
                    width: parent.width - rangeReturn.width
                    textFormat: Text.PlainText
                    text: service.historyRefreshing && root.historyMatches
                      ? "Loading " + MarketModel.rangeLabel(root.selectedRange) + " history…"
                      : root.detailQuote
                        ? MarketModel.marketStateLabel(root.detailQuote) + " · "
                          + MarketModel.asOfLabel(root.detailQuote, root.nowMs)
                        : (service.historyError || root.errorFor(root.focusedSymbol)
                          ? (service.historyError || root.errorFor(root.focusedSymbol).message)
                          : "History unavailable")
                    color: service.historyState === "stale" ? root.negativeColor : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  Text {
                    id: rangeReturn
                    textFormat: Text.PlainText
                    text: root.rangeArrow() + " "
                      + MarketModel.formatPercent(root.rangeResult.percent) + " "
                      + MarketModel.rangeLabel(root.selectedRange)
                    color: root.rangeMovementColor()
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
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

          Text {
            visible: !root.setupRequired && !root.managing
            width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: "Yahoo Finance chart · unofficial, best effort · informational only"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }
}
