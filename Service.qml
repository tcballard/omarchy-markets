import QtQuick
import Quickshell
import Quickshell.Io
import "MarketModel.js" as MarketModel
import "ServiceLifecycle.js" as ServiceLifecycle

// One process-wide poller shared by every bar surface. The visual widget
// configures it after Omarchy injects that widget's inline shell.json settings.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  property var configuredSymbols: []
  property int refreshIntervalSec: 900
  property bool dataEnabled: false
  property var quotes: []
  property var errors: []
  property string state: "setup"
  property bool refreshing: false
  property bool providerUnofficial: true
  property string providerLabel: "Yahoo Finance chart"
  property string lastError: ""
  property date lastUpdated: new Date(0)
  property int revision: 0
  property int consecutiveFailures: 0
  property int manualRefreshCooldownSec: 30

  // Selected-symbol history is intentionally independent from the quote poller.
  // The panel may replace this request rapidly as the user browses ranges; only
  // the latest generation is allowed to publish.
  property var historyQuote: null
  property string historySymbol: ""
  property string historyRange: "1d"
  property string historyState: "setup"
  property bool historyRefreshing: false
  property string historyError: ""
  property date historyLastUpdated: new Date(0)
  property int historyRevision: 0

  property bool _requestActive: false
  property bool _requestTimedOut: false
  property bool _discardActiveResponse: false
  property bool _refreshQueued: false
  property string _activeSymbolsKey: ""
  property int _generationCounter: 0
  property int _activeGeneration: 0
  property var _completion: ServiceLifecycle.beginCompletion(0)
  property double _lastRequestStartedMs: 0
  property var _fetchProcess: null
  property int _stopGeneration: 0
  property int _completionFallbackGeneration: 0

  property int _historyGenerationCounter: 0
  property int _activeHistoryGeneration: 0
  property string _activeHistoryKey: ""
  property bool _historyRequestActive: false
  property bool _historyTimedOut: false
  property var _historyCompletion: ServiceLifecycle.beginCompletion(0)
  property var _historyProcess: null
  property int _historyCompletionFallbackGeneration: 0
  property int _pendingHistoryGeneration: 0
  property string _pendingHistoryKey: ""
  property var _retiringHistoryProcesses: []
  property var _historyCache: ({})
  property var _historyCacheOrder: []

  readonly property string symbolsKey: configuredSymbols.join(",")
  readonly property bool hasData: quotes.length > 0
  readonly property bool processRunning: _fetchProcess
    ? _fetchProcess.running === true : false
  readonly property string sourceDirectory: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) : ""
  readonly property string helperPath: sourceDirectory !== ""
    ? sourceDirectory + "/scripts/fetch_quotes.py" : ""
  readonly property string pythonInterpreterPath: "/usr/bin/python3"
  readonly property bool firstParty: manifest && (manifest.__isFirstParty === true
    || String(manifest.id || "") === "omarchy.markets")
  readonly property bool currentlyInBar: safeInBar()
  readonly property var pollingEligibility: ServiceLifecycle.pollingDecision({
    dataEnabled: dataEnabled,
    firstParty: firstParty,
    inBar: currentlyInBar,
    symbolCount: configuredSymbols.length
  })
  readonly property bool pollingAllowed: pollingEligibility.allowed === true
  readonly property int recommendedIntervalSec:
    typeof MarketModel.recommendedRefreshInterval === "function"
      ? MarketModel.recommendedRefreshInterval(quotes, refreshIntervalSec)
      : refreshIntervalSec
  readonly property int effectiveIntervalSec: ServiceLifecycle.failureBackoffInterval(
    recommendedIntervalSec, consecutiveFailures, 3600)
  readonly property string cacheRoot: resolvedCacheRoot()
  readonly property string cacheDirectoryPath: cacheRoot !== ""
    ? cacheRoot + "/omarchy-markets" : ""
  readonly property string quoteCacheFilePath: cacheDirectoryPath !== ""
    ? cacheDirectoryPath + "/quotes-v1.json" : ""
  readonly property int historyCacheSize: _historyCacheOrder.length

  function resolvedCacheRoot() {
    var xdg = String(Quickshell.env("XDG_CACHE_HOME") || "")
    if (xdg.charAt(0) === "/") return xdg.replace(/\/$/, "")
    var home = String(Quickshell.env("HOME") || "")
    return home.charAt(0) === "/" ? home.replace(/\/$/, "") + "/.cache" : ""
  }

  function historyCacheFilePath(symbolValue, rangeValue) {
    var normalized = MarketModel.normalizeSymbols([String(symbolValue || "")], 1)
    if (cacheDirectoryPath === "" || normalized.length === 0) return ""
    var range = ServiceLifecycle.normalizeHistoryRange(rangeValue, "1d")
    return cacheDirectoryPath + "/history/" + normalized[0] + "-" + range + "-v1.json"
  }

  function helperCommand(argumentsValue) {
    if (pythonInterpreterPath !== "/usr/bin/python3" ||
        helperPath.charAt(0) !== "/") return []
    return [pythonInterpreterPath, helperPath].concat(argumentsValue || [])
  }

  function safeInBar() {
    // Reading the revision gives this binding a public reactive dependency;
    // inBar() itself is a function and otherwise would not invalidate it.
    var revision = pluginRegistry && pluginRegistry.registryRevision !== undefined
      ? pluginRegistry.registryRevision : 0
    if (!manifest || !manifest.id || !pluginRegistry ||
        typeof pluginRegistry.inBar !== "function") return false
    try {
      return pluginRegistry.inBar(String(manifest.id)) === true
    } catch (error) {
      return false
    }
  }

  function conciseError(value, fallback) {
    var text = String(value || fallback || "Market data request failed")
      .replace(/\s+/g, " ").trim()
    return text.length > 180 ? text.substring(0, 177) + "…" : text
  }

  function configure(symbolsValue, intervalValue, dataEnabledValue) {
    var nextSymbols = MarketModel.normalizeSymbols(symbolsValue)
    var parsedInterval = parseInt(String(intervalValue), 10)
    if (!isFinite(parsedInterval)) parsedInterval = 900
    parsedInterval = Math.max(300, Math.min(3600, parsedInterval))
    var nextDataEnabled = dataEnabledValue === true

    var symbolsChanged = JSON.stringify(nextSymbols) !== JSON.stringify(configuredSymbols)
    var intervalChanged = parsedInterval !== refreshIntervalSec
    var consentChanged = nextDataEnabled !== dataEnabled
    if (symbolsChanged) {
      var retained = ServiceLifecycle.filterConfiguredState(
        nextSymbols, quotes, errors)
      quotes = retained.quotes
      errors = retained.errors
      configuredSymbols = nextSymbols
      consecutiveFailures = 0
      lastError = ""
      if (historySymbol !== "" && configuredSymbols.indexOf(historySymbol) === -1)
        cancelHistoryRequest("idle", true)
      if (configuredSymbols.length > 0)
        state = quotes.length > 0 ? "stale" : "waiting"
    }
    if (intervalChanged) refreshIntervalSec = parsedInterval
    if (consentChanged) dataEnabled = nextDataEnabled

    var eligibility = currentPollingDecision()
    if (!eligibility.allowed) {
      deactivateData(eligibility.state, eligibility.reason === "consent" ||
        eligibility.reason === "symbols")
      return
    }

    if (symbolsChanged || consentChanged) refresh("configuration")
    else refreshIfStale()
  }

  function currentPollingDecision() {
    return ServiceLifecycle.pollingDecision({
      dataEnabled: dataEnabled,
      firstParty: firstParty,
      inBar: safeInBar(),
      symbolCount: configuredSymbols.length
    })
  }

  function deactivateData(nextState, clearData) {
    _refreshQueued = false
    if (_requestActive) _discardActiveResponse = true
    requestWatchdog.stop()
    refreshing = false
    requestProcessStop()
    cancelHistoryRequest(nextState, clearData === true)
    if (clearData === true) {
      quotes = []
      errors = []
      lastUpdated = new Date(0)
      consecutiveFailures = 0
      _historyCache = ({})
      _historyCacheOrder = []
    }
    lastError = ""
    state = String(nextState || "disabled")
    revision += 1
  }

  function reconcileEligibility() {
    var eligibility = currentPollingDecision()
    if (!eligibility.allowed) {
      deactivateData(eligibility.state, eligibility.reason === "consent" ||
        eligibility.reason === "symbols")
      return false
    }
    if (state === "setup" || state === "disabled" || state === "empty") {
      state = quotes.length > 0 ? "stale" : "waiting"
      revision += 1
    }
    refreshIfStale()
    return true
  }

  function refreshIfStale() {
    if (!currentPollingDecision().allowed) return
    // Several bar lifecycle bindings may converge during startup. A freshness
    // probe must not turn those idempotent configuration calls into a queued
    // duplicate request behind the first fetch.
    if (refreshing || _requestActive || processRunning) return
    var updated = lastUpdated instanceof Date ? lastUpdated.getTime() : 0
    if (updated <= 0 || Date.now() - updated >= refreshIntervalSec * 1000)
      refresh("stale")
  }

  function refresh(triggerValue) {
    var trigger = String(triggerValue || "manual")
    var now = Date.now()
    var eligibility = currentPollingDecision()
    if (!eligibility.allowed) {
      deactivateData(eligibility.state, eligibility.reason === "consent" ||
        eligibility.reason === "symbols")
      return false
    }
    var decision = ServiceLifecycle.refreshDecision(
      trigger,
      refreshing || processRunning || _requestActive,
      _lastRequestStartedMs,
      now,
      manualRefreshCooldownSec * 1000)
    if (!decision.start) {
      if (decision.queue) _refreshQueued = true
      return false
    }
    if (helperPath === "") {
      failRequest("Plugin source directory is unavailable", "failed")
      return false
    }
    if (quoteCacheFilePath === "") {
      failRequest("The XDG cache directory is unavailable", "failed")
      return false
    }

    _generationCounter += 1
    _activeGeneration = _generationCounter
    _completion = ServiceLifecycle.beginCompletion(_activeGeneration)
    refreshing = true
    _requestActive = true
    _requestTimedOut = false
    _discardActiveResponse = false
    _refreshQueued = false
    _activeSymbolsKey = symbolsKey
    _lastRequestStartedMs = now
    lastError = ""
    if (!hasData) state = "loading"

    var command = helperCommand([
      "--timeout", "8",
      "--symbols", symbolsKey,
      "--range", "1d",
      "--cache-file", quoteCacheFilePath
    ])
    if (command.length === 0) {
      failRequest("The trusted Python 3 interpreter is unavailable", "dependency-missing")
      return false
    }
    var process = fetchProcessComponent.createObject(root, {
      generationToken: _activeGeneration,
      command: command
    })
    if (!process) {
      failRequest("The market data helper could not be created", "failed")
      return false
    }
    _fetchProcess = process
    requestWatchdog.restart()
    process.running = true
    return true
  }

  function processMatches(generation, process) {
    return !!process && process === _fetchProcess
      && Number(process.generationToken) === Number(generation)
  }

  function retireProcessObject(process, force) {
    if (!process || process.retirementQueued === true) return false
    if (process.running && force !== true) return false
    process.retirementQueued = true
    if (_fetchProcess === process) _fetchProcess = null
    Qt.callLater(function() { process.destroy() })
    return true
  }

  function retireStoppedProcess(generation) {
    var process = _fetchProcess
    if (!processMatches(generation, process) || process.running) return false
    return retireProcessObject(process, false)
  }

  function requestProcessStop() {
    var process = _fetchProcess
    var generation = _activeGeneration
    if (!processMatches(generation, process)) return
    _stopGeneration = generation
    if (!process.running) {
      noteProcessStopped(generation, process)
      return
    }
    // `running = false` asks Quickshell/QProcess for a graceful SIGTERM.
    process.running = false
    terminateEscalation.restart()
  }

  function escalateProcessStop(generation) {
    var process = _fetchProcess
    if (!processMatches(generation, process) || !process.running) return
    try {
      process.signal(9)
    } catch (error) {
      // The final fallback retires the wrapper even if signal delivery itself
      // is unavailable on this Quickshell build.
    }
    killFallback.restart()
  }

  function forceStopFallback(generation) {
    var process = _fetchProcess
    if (!processMatches(generation, process)) return
    if (process.running) {
      try { process.signal(9) } catch (error) {}
    }

    // Generation-scoped forced retirement prevents late events from this
    // wrapper being mistaken for a replacement request. Destroying QProcess is
    // the final bounded cleanup after TERM and KILL have both failed to settle.
    if (_requestActive && generation === _activeGeneration) {
      if (_discardActiveResponse) {
        settleActiveRequest()
        _discardActiveResponse = false
      } else if (_requestTimedOut) {
        failRequest("Market data request timed out", "offline")
      } else {
        failRequest("The market data helper did not stop safely", "failed")
      }
    }
    retireProcessObject(process, true)
    runQueuedRefresh()
  }

  function settleStoppedGeneration(generation) {
    var process = _fetchProcess
    if (!processMatches(generation, process) || process.running) return
    var decision = ServiceLifecycle.stoppedGenerationDecision({
      generationMatches: generation === _activeGeneration,
      processRunning: process.running,
      requestActive: _requestActive,
      completion: _completion,
      discardResponse: _discardActiveResponse,
      timedOut: _requestTimedOut
    })
    if (decision === "wait") return
    if (decision === "retire") {
      retireProcessObject(process, false)
      runQueuedRefresh()
      return
    }
    if (decision === "complete") {
      maybeCompleteRequest()
      retireStoppedProcess(generation)
      runQueuedRefresh()
      return
    }

    // QProcess::FailedToStart emits only runningChanged. A short grace period
    // lets normal exit/collector signals arrive first; this fallback guarantees
    // that a generation with no signals still reaches a terminal state.
    if (decision === "discard") {
      settleActiveRequest()
      _discardActiveResponse = false
    } else if (decision === "timeout") {
      failRequest("Market data request timed out", "offline")
    } else if (decision === "start-failed") {
      failRequest("The market data helper could not be started", "dependency-missing")
    } else {
      failRequest("The market data helper stopped before returning complete output", "failed")
    }
    retireProcessObject(process, false)
    runQueuedRefresh()
  }

  function settleActiveRequest() {
    requestWatchdog.stop()
    if (_completionFallbackGeneration === _activeGeneration)
      completionFallback.stop()
    refreshing = false
    _requestActive = false
    retireStoppedProcess(_activeGeneration)
  }

  function failRequest(message, requestedState) {
    settleActiveRequest()
    consecutiveFailures = Math.min(consecutiveFailures + 1, 8)
    lastError = conciseError(message)
    state = hasData ? "stale" : String(requestedState || "failed")
    revision += 1
    syncOneDayHistory()
    runQueuedRefresh()
  }

  function mergeFreshQuotes(freshQuotes) {
    var merged = []
    var i

    for (i = 0; i < configuredSymbols.length; i++) {
      var symbol = configuredSymbols[i]
      var fresh = MarketModel.findQuote(freshQuotes, symbol)
      if (fresh) {
        var current = {}
        for (var freshKey in fresh) current[freshKey] = fresh[freshKey]
        current.stale = fresh.stale === true || fresh.cached === true
        merged.push(current)
        continue
      }
      var previous = MarketModel.findQuote(quotes, symbol)
      // A partial provider envelope is not allowed to erase last-good data.
      // Retain every configured symbol omitted from the fresh result, even if
      // the provider supplied only a global error or no exact error object.
      if (previous) {
        var retained = {}
        for (var oldKey in previous) retained[oldKey] = previous[oldKey]
        retained.stale = true
        merged.push(retained)
      }
    }
    return merged
  }

  function completePartialErrors(freshQuotes, providerErrors) {
    var source = Array.isArray(providerErrors) ? providerErrors : []
    var exact = {}
    var added = {}
    var result = []
    var i
    for (i = 0; i < source.length; i++) {
      var sourceSymbol = String(source[i].symbol || "")
      if (sourceSymbol !== "" && configuredSymbols.indexOf(sourceSymbol) !== -1
          && !exact[sourceSymbol]) exact[sourceSymbol] = source[i]
    }

    // Missing-symbol errors come first so every retained stale quote has an
    // exact explanation even when a global provider error would fill the cap.
    for (i = 0; i < configuredSymbols.length && result.length < 12; i++) {
      var symbol = configuredSymbols[i]
      if (MarketModel.findQuote(freshQuotes, symbol)) continue
      if (exact[symbol]) result.push(exact[symbol])
      else result.push({
        symbol: symbol,
        code: "missing_quote",
        message: "No fresh quote was returned for this symbol."
      })
      added[symbol] = true
    }
    for (i = 0; i < source.length && result.length < 12; i++) {
      var errorSymbol = String(source[i].symbol || "")
      if (errorSymbol !== "" && added[errorSymbol]) continue
      result.push(source[i])
      if (errorSymbol !== "") added[errorSymbol] = true
    }
    return result
  }

  function noteStdout(generation, text) {
    if (!_requestActive || generation !== _activeGeneration) return
    _completion = ServiceLifecycle.recordStdout(_completion, generation, text)
    maybeCompleteRequest()
  }

  function noteStderr(generation, text) {
    if (!_requestActive || generation !== _activeGeneration) return
    _completion = ServiceLifecycle.recordStderr(_completion, generation, text)
    maybeCompleteRequest()
  }

  function noteProcessExit(generation, exitCode) {
    if (!_requestActive || generation !== _activeGeneration) {
      runQueuedRefresh()
      return
    }
    _completion = ServiceLifecycle.recordExit(_completion, generation, exitCode)
    maybeCompleteRequest()
  }

  function noteProcessStopped(generation, process) {
    if (!processMatches(generation, process)) {
      if (process && !process.running) retireProcessObject(process, false)
      return
    }
    if (_stopGeneration === generation) {
      terminateEscalation.stop()
      killFallback.stop()
    }
    if (!_requestActive || generation !== _activeGeneration) {
      retireProcessObject(process, false)
      runQueuedRefresh()
      return
    }
    maybeCompleteRequest()
    if (!_requestActive) {
      retireProcessObject(process, false)
      runQueuedRefresh()
      return
    }
    _completionFallbackGeneration = generation
    completionFallback.restart()
  }

  function maybeCompleteRequest() {
    if (!_requestActive || !ServiceLifecycle.completionReady(_completion)) return
    var generation = _activeGeneration
    if (_discardActiveResponse) {
      settleActiveRequest()
      _discardActiveResponse = false
      runQueuedRefresh()
      return
    }
    consumeResponse(
      generation,
      _completion.exitCode,
      _completion.stdout,
      _completion.stderr)
  }

  function consumeResponse(generation, exitCode, stdoutText, stderrText) {
    if (!_requestActive || generation !== _activeGeneration) return
    settleActiveRequest()

    var stderrValue = String(stderrText || "")
    if (_requestTimedOut) {
      failRequest("Market data request timed out", "offline")
      return
    }
    if (exitCode === 127 ||
        (stderrValue.indexOf("/usr/bin/python3") !== -1 && stderrValue.indexOf("No such") !== -1)) {
      failRequest("Python 3 is required to fetch market data", "dependency-missing")
      return
    }

    var raw
    try {
      raw = JSON.parse(String(stdoutText || ""))
    } catch (error) {
      failRequest(stderrValue || "The quote provider returned malformed data", exitCode === 0 ? "failed" : "offline")
      return
    }

    var parsed = MarketModel.normalizeProviderResponse(raw, configuredSymbols)
    if (!parsed || parsed.ok !== true) {
      failRequest((parsed && parsed.error) || stderrValue || "The quote provider returned invalid data", "failed")
      return
    }

    if (_activeSymbolsKey !== symbolsKey) {
      // Configuration moved while this request was in flight. Never publish a
      // response under the new symbol list; run one coalesced follow-up.
      _refreshQueued = true
      runQueuedRefresh()
      return
    }

    providerLabel = parsed.provider || providerLabel
    var completeErrors = completePartialErrors(parsed.quotes, parsed.errors)
    errors = completeErrors
    if (parsed.quotes.length > 0) {
      quotes = mergeFreshQuotes(parsed.quotes)
      var generated = new Date(parsed.generatedAt || Date.now())
      lastUpdated = isNaN(generated.getTime()) ? new Date() : generated
      var missingCount = Math.max(0, configuredSymbols.length - parsed.quotes.length)
      var liveCount = 0
      for (var quoteIndex = 0; quoteIndex < parsed.quotes.length; quoteIndex++) {
        if (parsed.quotes[quoteIndex].stale !== true &&
            parsed.quotes[quoteIndex].cached !== true) liveCount += 1
      }
      var issueCount = Math.min(
        configuredSymbols.length,
        Math.max(missingCount, parsed.errors.length))
      state = liveCount === 0 ? "stale" : (issueCount > 0 ? "partial" : "ready")
      consecutiveFailures = ServiceLifecycle.nextFailureCount(
        consecutiveFailures,
        configuredSymbols.length,
        liveCount,
        parsed.errors.length)
      lastError = issueCount > 0
        ? issueCount + (issueCount === 1 ? " symbol could not be updated" : " symbols could not be updated")
        : ""
    } else {
      failRequest(parsed.errors.length > 0
        ? parsed.errors[0].message
        : (stderrValue || "No quotes were returned"),
        exitCode === 0 ? "failed" : "offline")
      return
    }
    revision += 1
    syncOneDayHistory()
    runQueuedRefresh()
  }

  function runQueuedRefresh() {
    if (!ServiceLifecycle.canDrainQueue(
        _refreshQueued, refreshing, _requestActive, processRunning)) return
    _refreshQueued = false
    Qt.callLater(function() { root.refresh("queued") })
  }

  function historyKey(symbolValue, rangeValue) {
    var normalized = MarketModel.normalizeSymbols([String(symbolValue || "")], 1)
    if (normalized.length === 0) return ""
    return normalized[0] + "|" + ServiceLifecycle.normalizeHistoryRange(rangeValue, "1d")
  }

  function cachedHistoryQuote(keyValue) {
    var key = String(keyValue || "")
    return key !== "" && _historyCache && _historyCache[key]
      ? _historyCache[key] : null
  }

  function historyCacheFresh(quote) {
    if (!quote || quote.stale === true || quote.cached === true) return false
    var fetched = quote.__historyFetchedAt
    var milliseconds = fetched && typeof fetched.getTime === "function"
      ? fetched.getTime() : Date.parse(String(fetched || ""))
    return isFinite(milliseconds) && milliseconds > 0
      && Date.now() - milliseconds >= 0
      && Date.now() - milliseconds < 300000
  }

  function cacheHistoryQuote(keyValue, quote) {
    var key = String(keyValue || "")
    if (key === "" || !quote || typeof quote !== "object") return
    var order = ServiceLifecycle.touchLru(_historyCacheOrder, key, 24)
    var next = ({})
    for (var index = 0; index < order.length; index++) {
      var retainedKey = order[index]
      if (retainedKey === key) next[retainedKey] = quote
      else if (_historyCache && _historyCache[retainedKey])
        next[retainedKey] = _historyCache[retainedKey]
    }
    _historyCache = next
    _historyCacheOrder = order
  }

  function publishOneDayHistory(quote) {
    historyQuote = quote || null
    historyRefreshing = false
    historyError = quote ? "" : "The one-day quote is not available yet"
    if (!quote) historyState = refreshing ? "loading" : "unavailable"
    else if (state === "stale" || quote.stale === true || quote.cached === true)
      historyState = "stale"
    else historyState = "ready"
    historyLastUpdated = lastUpdated
    historyRevision += 1
  }

  function syncOneDayHistory() {
    if (historySymbol === "" || historyRange !== "1d") return
    publishOneDayHistory(MarketModel.findQuote(quotes, historySymbol))
  }

  function requestHistory(symbolValue, rangeValue) {
    var normalized = MarketModel.normalizeSymbols([String(symbolValue || "")], 1)
    var range = ServiceLifecycle.normalizeHistoryRange(rangeValue, "1d")
    var eligibility = currentPollingDecision()

    var requestedKey = normalized.length > 0 ? historyKey(normalized[0], range) : ""
    if (eligibility.allowed && requestedKey !== ""
        && configuredSymbols.indexOf(normalized[0]) !== -1
        && range !== "1d" && requestedKey === _activeHistoryKey
        && (_historyRequestActive || historyDebounce.running)) return true

    supersedeHistoryRequest()
    _historyGenerationCounter += 1
    _activeHistoryGeneration = _historyGenerationCounter
    historyRange = range
    historyError = ""

    if (!eligibility.allowed) {
      historySymbol = normalized.length > 0 ? normalized[0] : ""
      historyQuote = null
      historyState = eligibility.state
      historyRefreshing = false
      historyRevision += 1
      return false
    }
    if (normalized.length === 0 || configuredSymbols.indexOf(normalized[0]) === -1) {
      historySymbol = normalized.length > 0 ? normalized[0] : ""
      historyQuote = null
      historyState = "unavailable"
      historyError = "Choose a symbol from the configured watchlist"
      historyRefreshing = false
      historyRevision += 1
      return false
    }

    historySymbol = normalized[0]
    _activeHistoryKey = historyKey(historySymbol, range)
    var oneDayQuote = MarketModel.findQuote(quotes, historySymbol)
    var cached = cachedHistoryQuote(_activeHistoryKey)
    var plan = ServiceLifecycle.historyRequestDecision(
      range, !!oneDayQuote, !!cached)

    if (plan.mode === "reuse") {
      publishOneDayHistory(oneDayQuote)
      return true
    }
    if (plan.mode === "wait") {
      publishOneDayHistory(null)
      return false
    }

    if (cached) {
      historyQuote = cached
      historyState = cached.stale === true || cached.cached === true ? "stale" : "ready"
      historyLastUpdated = cached.__historyFetchedAt || new Date(0)
    } else {
      historyQuote = null
      historyState = "loading"
      historyLastUpdated = new Date(0)
    }
    if (cached && historyCacheFresh(cached)) {
      historyRefreshing = false
      historyRevision += 1
      return true
    }
    historyRefreshing = true
    historyRevision += 1
    _pendingHistoryGeneration = _activeHistoryGeneration
    _pendingHistoryKey = _activeHistoryKey
    historyDebounce.restart()
    return true
  }

  function startHistoryFetch(generation, keyValue) {
    if (!ServiceLifecycle.acceptsHistoryResult(
        generation, _activeHistoryGeneration, keyValue, _activeHistoryKey)) return false
    var cachePath = historyCacheFilePath(historySymbol, historyRange)
    if (helperPath === "" || cachePath === "") {
      failHistoryRequest("Market history cannot start because its local paths are unavailable", "failed")
      return false
    }

    _historyCompletion = ServiceLifecycle.beginCompletion(generation)
    _historyRequestActive = true
    _historyTimedOut = false
    var command = helperCommand([
      "--timeout", "8",
      "--symbols", historySymbol,
      "--range", historyRange,
      "--cache-file", cachePath
    ])
    if (command.length === 0) {
      failHistoryRequest("The trusted Python 3 interpreter is unavailable", "dependency-missing")
      return false
    }
    var process = historyProcessComponent.createObject(root, {
      generationToken: generation,
      requestKey: String(keyValue),
      command: command
    })
    if (!process) {
      failHistoryRequest("The market history helper could not be created", "failed")
      return false
    }
    _historyProcess = process
    historyWatchdog.restart()
    process.running = true
    return true
  }

  function supersedeHistoryRequest() {
    historyDebounce.stop()
    _pendingHistoryGeneration = 0
    _pendingHistoryKey = ""
    historyWatchdog.stop()
    historyCompletionFallback.stop()
    _historyRequestActive = false
    _historyTimedOut = false
    var process = _historyProcess
    _historyProcess = null
    if (process) retireHistoryProcess(process)
  }

  function cancelHistoryRequest(nextState, clearData) {
    _historyGenerationCounter += 1
    _activeHistoryGeneration = _historyGenerationCounter
    _activeHistoryKey = ""
    supersedeHistoryRequest()
    historyRefreshing = false
    historyError = ""
    historyState = String(nextState || "idle")
    if (clearData === true) {
      historyQuote = null
      historySymbol = ""
      historyRange = "1d"
      historyLastUpdated = new Date(0)
    }
    historyRevision += 1
  }

  function retireHistoryProcess(process) {
    if (!process || process.retirementQueued === true) return
    process.retirementQueued = true
    if (!process.running) {
      Qt.callLater(function() { process.destroy() })
      return
    }
    var retiring = _retiringHistoryProcesses.slice(0)
    if (retiring.indexOf(process) === -1) retiring.push(process)
    _retiringHistoryProcesses = retiring
    process.running = false
    if (!historyTerminateEscalation.running) historyTerminateEscalation.start()
  }

  function finishRetiringHistoryProcess(process) {
    if (!process || process.running) return
    var next = []
    for (var index = 0; index < _retiringHistoryProcesses.length; index++) {
      if (_retiringHistoryProcesses[index] !== process)
        next.push(_retiringHistoryProcesses[index])
    }
    _retiringHistoryProcesses = next
    Qt.callLater(function() { process.destroy() })
  }

  function escalateRetiringHistoryProcesses(force) {
    var remaining = []
    for (var index = 0; index < _retiringHistoryProcesses.length; index++) {
      var process = _retiringHistoryProcesses[index]
      if (!process) continue
      if (process.running) {
        try { process.signal(9) } catch (error) {}
      }
      if (process.running && force !== true) remaining.push(process)
      else {
        try { process.destroy() } catch (destroyError) {}
      }
    }
    _retiringHistoryProcesses = remaining
    if (remaining.length > 0 && force !== true) historyKillFallback.restart()
  }

  function historyRequestMatches(generation, keyValue, process) {
    return process && process === _historyProcess &&
      ServiceLifecycle.acceptsHistoryResult(
        generation, _activeHistoryGeneration, keyValue, _activeHistoryKey)
  }

  function noteHistoryStdout(generation, keyValue, text) {
    if (!_historyRequestActive ||
        !ServiceLifecycle.acceptsHistoryResult(
          generation, _activeHistoryGeneration, keyValue, _activeHistoryKey)) return
    _historyCompletion = ServiceLifecycle.recordStdout(_historyCompletion, generation, text)
    maybeCompleteHistoryRequest()
  }

  function noteHistoryStderr(generation, keyValue, text) {
    if (!_historyRequestActive ||
        !ServiceLifecycle.acceptsHistoryResult(
          generation, _activeHistoryGeneration, keyValue, _activeHistoryKey)) return
    _historyCompletion = ServiceLifecycle.recordStderr(_historyCompletion, generation, text)
    maybeCompleteHistoryRequest()
  }

  function noteHistoryExit(generation, keyValue, exitCode) {
    if (!_historyRequestActive ||
        !ServiceLifecycle.acceptsHistoryResult(
          generation, _activeHistoryGeneration, keyValue, _activeHistoryKey)) return
    _historyCompletion = ServiceLifecycle.recordExit(_historyCompletion, generation, exitCode)
    maybeCompleteHistoryRequest()
  }

  function noteHistoryStopped(generation, keyValue, process) {
    if (!historyRequestMatches(generation, keyValue, process)) {
      finishRetiringHistoryProcess(process)
      return
    }
    maybeCompleteHistoryRequest()
    if (!_historyRequestActive) {
      _historyProcess = null
      retireHistoryProcess(process)
      return
    }
    _historyCompletionFallbackGeneration = generation
    historyCompletionFallback.restart()
  }

  function maybeCompleteHistoryRequest() {
    if (!_historyRequestActive ||
        !ServiceLifecycle.completionReady(_historyCompletion)) return
    consumeHistoryResponse(
      _activeHistoryGeneration,
      _activeHistoryKey,
      _historyCompletion.exitCode,
      _historyCompletion.stdout,
      _historyCompletion.stderr)
  }

  function settleHistoryRequest() {
    historyWatchdog.stop()
    historyCompletionFallback.stop()
    historyRefreshing = false
    _historyRequestActive = false
    var process = _historyProcess
    _historyProcess = null
    if (process) retireHistoryProcess(process)
  }

  function failHistoryRequest(message, requestedState) {
    var cached = cachedHistoryQuote(_activeHistoryKey)
    settleHistoryRequest()
    historyError = conciseError(message, "Market history request failed")
    if (cached) {
      historyQuote = cached
      historyState = "stale"
    } else {
      historyQuote = null
      historyState = String(requestedState || "failed")
    }
    historyRevision += 1
  }

  function consumeHistoryResponse(generation, keyValue, exitCode, stdoutText, stderrText) {
    if (!_historyRequestActive ||
        !ServiceLifecycle.acceptsHistoryResult(
          generation, _activeHistoryGeneration, keyValue, _activeHistoryKey)) return
    var stderrValue = String(stderrText || "")
    if (_historyTimedOut) {
      failHistoryRequest("Market history request timed out", "offline")
      return
    }
    if (exitCode === 127 ||
        (stderrValue.indexOf("/usr/bin/python3") !== -1 && stderrValue.indexOf("No such") !== -1)) {
      failHistoryRequest("Python 3 is required to fetch market history", "dependency-missing")
      return
    }

    var raw
    try {
      raw = JSON.parse(String(stdoutText || ""))
    } catch (error) {
      failHistoryRequest(stderrValue || "The history provider returned malformed data",
        exitCode === 0 ? "failed" : "offline")
      return
    }
    var parsed = MarketModel.normalizeProviderResponse(raw, [historySymbol], 240)
    if (!parsed || parsed.ok !== true) {
      failHistoryRequest((parsed && parsed.error) || stderrValue ||
        "The history provider returned invalid data", "failed")
      return
    }
    var quote = MarketModel.findQuote(parsed.quotes, historySymbol)
    if (!quote) {
      failHistoryRequest(parsed.errors.length > 0 ? parsed.errors[0].message :
        "No history was returned", exitCode === 0 ? "failed" : "offline")
      return
    }

    var stored = ({})
    for (var quoteKey in quote) stored[quoteKey] = quote[quoteKey]
    stored.__historyFetchedAt = new Date(parsed.generatedAt || Date.now())
    if (isNaN(stored.__historyFetchedAt.getTime())) stored.__historyFetchedAt = new Date()
    cacheHistoryQuote(keyValue, stored)
    settleHistoryRequest()
    historyQuote = stored
    historyLastUpdated = stored.__historyFetchedAt
    historyError = parsed.errors.length > 0 ? parsed.errors[0].message : ""
    historyState = stored.stale === true || stored.cached === true ? "stale" :
      (parsed.errors.length > 0 ? "partial" : "ready")
    historyRevision += 1
  }

  Timer {
    id: refreshTimer
    interval: root.effectiveIntervalSec * 1000
    repeat: true
    running: root.pollingAllowed
    onTriggered: root.refresh("timer")
  }

  Timer {
    id: requestWatchdog
    interval: 35000
    repeat: false
    onTriggered: {
      if (!root._requestActive) return
      root._requestTimedOut = true
      root.requestProcessStop()
      // Normal finalization waits for actual process stop plus both closed
      // streams. Failed-to-start and missing-signal cases use the bounded,
      // generation-scoped fallback below.
    }
  }

  Timer {
    id: terminateEscalation
    interval: 750
    repeat: false
    onTriggered: root.escalateProcessStop(root._stopGeneration)
  }

  Timer {
    id: killFallback
    interval: 750
    repeat: false
    onTriggered: root.forceStopFallback(root._stopGeneration)
  }

  Timer {
    id: completionFallback
    interval: 150
    repeat: false
    onTriggered: root.settleStoppedGeneration(root._completionFallbackGeneration)
  }

  Timer {
    id: historyDebounce
    interval: 180
    repeat: false
    onTriggered: {
      var generation = root._pendingHistoryGeneration
      var key = root._pendingHistoryKey
      root._pendingHistoryGeneration = 0
      root._pendingHistoryKey = ""
      root.startHistoryFetch(generation, key)
    }
  }

  Timer {
    id: historyWatchdog
    interval: 35000
    repeat: false
    onTriggered: {
      if (!root._historyRequestActive) return
      root._historyTimedOut = true
      root.failHistoryRequest("Market history request timed out", "offline")
    }
  }

  Timer {
    id: historyCompletionFallback
    interval: 150
    repeat: false
    onTriggered: {
      if (!root._historyRequestActive ||
          root._historyCompletionFallbackGeneration !== root._activeHistoryGeneration) return
      if (ServiceLifecycle.completionReady(root._historyCompletion)) {
        root.maybeCompleteHistoryRequest()
        return
      }
      var decision = ServiceLifecycle.stoppedGenerationDecision({
        generationMatches: true,
        processRunning: false,
        requestActive: root._historyRequestActive,
        completion: root._historyCompletion,
        discardResponse: false,
        timedOut: root._historyTimedOut
      })
      if (decision === "start-failed")
        root.failHistoryRequest("The market history helper could not be started", "dependency-missing")
      else if (decision === "timeout")
        root.failHistoryRequest("Market history request timed out", "offline")
      else
        root.failHistoryRequest("The market history helper stopped before returning complete output", "failed")
    }
  }

  Timer {
    id: historyTerminateEscalation
    interval: 750
    repeat: false
    onTriggered: root.escalateRetiringHistoryProcesses(false)
  }

  Timer {
    id: historyKillFallback
    interval: 750
    repeat: false
    onTriggered: root.escalateRetiringHistoryProcesses(true)
  }

  Component {
    id: fetchProcessComponent

    Process {
      id: requestProcess
      property int generationToken: 0
      property bool retirementQueued: false
      running: false
      command: []
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: root.noteStdout(requestProcess.generationToken, text)
      }
      stderr: StdioCollector {
        waitForEnd: true
        onStreamFinished: root.noteStderr(requestProcess.generationToken, text)
      }
      onExited: function(exitCode) {
        root.noteProcessExit(requestProcess.generationToken, exitCode)
      }
      onRunningChanged: {
        if (running) return
        // Capture while the wrapper is unquestionably alive. `onExited` may
        // already have scheduled its destruction, so this stop notification
        // must not dereference `requestProcess` from a later callback.
        var stoppedGeneration = requestProcess.generationToken
        var stoppedProcess = requestProcess
        root.noteProcessStopped(stoppedGeneration, stoppedProcess)
      }
    }
  }

  Component {
    id: historyProcessComponent

    Process {
      id: historyRequestProcess
      property int generationToken: 0
      property string requestKey: ""
      property bool retirementQueued: false
      running: false
      command: []
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: root.noteHistoryStdout(
          historyRequestProcess.generationToken,
          historyRequestProcess.requestKey,
          text)
      }
      stderr: StdioCollector {
        waitForEnd: true
        onStreamFinished: root.noteHistoryStderr(
          historyRequestProcess.generationToken,
          historyRequestProcess.requestKey,
          text)
      }
      onExited: function(exitCode) {
        root.noteHistoryExit(
          historyRequestProcess.generationToken,
          historyRequestProcess.requestKey,
          exitCode)
      }
      onRunningChanged: {
        if (running) return
        var stoppedGeneration = historyRequestProcess.generationToken
        var stoppedKey = historyRequestProcess.requestKey
        var stoppedProcess = historyRequestProcess
        root.noteHistoryStopped(stoppedGeneration, stoppedKey, stoppedProcess)
      }
    }
  }

  Connections {
    target: root.pluginRegistry
    enabled: root.pluginRegistry !== null
    function onPluginsChanged() { Qt.callLater(root.reconcileEligibility) }
  }

  onManifestChanged: Qt.callLater(reconcileEligibility)
  onPluginRegistryChanged: Qt.callLater(reconcileEligibility)

  IpcHandler {
    target: "io.github.tcballard.omarchy-markets"
    function refresh(): void { root.refresh() }
    function status(): string {
      return JSON.stringify({
        state: root.state,
        pollingAllowed: root.pollingAllowed,
        dataEnabled: root.dataEnabled,
        firstParty: root.firstParty,
        inBar: root.currentlyInBar,
        refreshing: root.refreshing,
        symbols: root.configuredSymbols.length,
        quotes: root.quotes.length,
        errors: root.errors.length,
        consecutiveFailures: root.consecutiveFailures,
        nextIntervalSec: root.effectiveIntervalSec,
        configuredIntervalSec: root.refreshIntervalSec,
        manualCooldownRemainingSec: Math.ceil(
          ServiceLifecycle.cooldownRemainingMs(
            root._lastRequestStartedMs,
            Date.now(),
            root.manualRefreshCooldownSec * 1000) / 1000),
        lastUpdated: root.lastUpdated.getTime() > 0 ? root.lastUpdated.toISOString() : null,
        history: {
          state: root.historyState,
          refreshing: root.historyRefreshing,
          symbol: root.historySymbol,
          range: root.historyRange,
          cacheEntries: root.historyCacheSize,
          lastUpdated: root.historyLastUpdated.getTime() > 0
            ? root.historyLastUpdated.toISOString() : null
        },
        provider: root.providerLabel,
        unofficial: root.providerUnofficial
      })
    }
  }
}
