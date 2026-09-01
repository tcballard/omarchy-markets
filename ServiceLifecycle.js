.pragma library

// Pure request-lifecycle decisions shared by Service.qml and the portable
// Node test harness. Keep this file free of Qt objects and wall-clock reads.

function finiteNumber(value, fallback) {
  return typeof value === "number" && isFinite(value) ? value : fallback;
}

function boundedInteger(value, fallback, minimum, maximum) {
  var number = finiteNumber(value, fallback);
  number = Math.floor(number);
  if (number < minimum) return minimum;
  if (number > maximum) return maximum;
  return number;
}

function pollingDecision(options) {
  var value = options && typeof options === "object" ? options : {};
  var symbolCount = boundedInteger(value.symbolCount, 0, 0, 12);

  // Network data is always a strict, real-boolean opt-in. In particular, the
  // strings "true" and "1" are not consent.
  if (value.dataEnabled !== true) {
    return { allowed: false, state: "setup", reason: "consent" };
  }
  if (symbolCount === 0) {
    return { allowed: false, state: "empty", reason: "symbols" };
  }
  if (value.firstParty === true && value.inBar !== true) {
    return { allowed: false, state: "disabled", reason: "not-in-bar" };
  }
  return { allowed: true, state: "waiting", reason: "allowed" };
}

function failureBackoffInterval(baseSeconds, failureCount, maximumSeconds) {
  var base = boundedInteger(baseSeconds, 900, 1, 86400);
  var failures = boundedInteger(failureCount, 0, 0, 8);
  var maximum = boundedInteger(maximumSeconds, 3600, base, 86400);
  return Math.min(maximum, base * Math.pow(2, Math.min(failures, 3)));
}

var HISTORY_RANGES = ["1d", "5d", "1mo", "6mo", "1y"];

function normalizeHistoryRange(value, fallback) {
  var candidate = String(value || "").toLowerCase();
  var defaultRange = HISTORY_RANGES.indexOf(String(fallback || "1d").toLowerCase()) !== -1
    ? String(fallback || "1d").toLowerCase() : "1d";
  return HISTORY_RANGES.indexOf(candidate) !== -1 ? candidate : defaultRange;
}

function historyRequestDecision(rangeValue, hasOneDayQuote, hasCachedQuote) {
  var range = normalizeHistoryRange(rangeValue, "1d");
  if (range === "1d") {
    return {
      mode: hasOneDayQuote === true ? "reuse" : "wait",
      range: range,
      showCached: false
    };
  }
  return { mode: "fetch", range: range, showCached: hasCachedQuote === true };
}

function acceptsHistoryResult(resultGeneration, activeGeneration, resultKey, activeKey) {
  return boundedInteger(resultGeneration, -1, -1, 2147483647) ===
      boundedInteger(activeGeneration, -2, -2, 2147483647) &&
    String(resultKey || "") !== "" && String(resultKey || "") === String(activeKey || "");
}

function touchLru(orderValue, keyValue, maximumEntries) {
  var source = Object.prototype.toString.call(orderValue) === "[object Array]"
    ? orderValue : [];
  var key = String(keyValue || "");
  var limit = boundedInteger(maximumEntries, 24, 1, 24);
  var result = [];
  var index;

  if (key === "") return source.slice(0, limit);
  for (index = 0; index < source.length; index += 1) {
    if (String(source[index]) === key || result.indexOf(String(source[index])) !== -1) continue;
    result.push(String(source[index]));
  }
  result.push(key);
  while (result.length > limit) result.shift();
  return result;
}

function beginCompletion(generation) {
  return {
    generation: boundedInteger(generation, 0, 0, 2147483647),
    exitFinished: false,
    stdoutFinished: false,
    stderrFinished: false,
    exitCode: null,
    stdout: "",
    stderr: ""
  };
}

function copyCompletion(state) {
  if (!state || typeof state !== "object") return beginCompletion(0);
  return {
    generation: boundedInteger(state.generation, 0, 0, 2147483647),
    exitFinished: state.exitFinished === true,
    stdoutFinished: state.stdoutFinished === true,
    stderrFinished: state.stderrFinished === true,
    exitCode: state.exitCode,
    stdout: String(state.stdout || ""),
    stderr: String(state.stderr || "")
  };
}

function matchesGeneration(state, generation) {
  return state && typeof state === "object" &&
    boundedInteger(generation, -1, -1, 2147483647) === state.generation;
}

function recordExit(state, generation, exitCode) {
  if (!matchesGeneration(state, generation)) return state;
  var next = copyCompletion(state);
  next.exitFinished = true;
  next.exitCode = boundedInteger(exitCode, -1, -2147483648, 2147483647);
  return next;
}

function recordStdout(state, generation, text) {
  if (!matchesGeneration(state, generation)) return state;
  var next = copyCompletion(state);
  next.stdoutFinished = true;
  next.stdout = String(text || "");
  return next;
}

function recordStderr(state, generation, text) {
  if (!matchesGeneration(state, generation)) return state;
  var next = copyCompletion(state);
  next.stderrFinished = true;
  next.stderr = String(text || "");
  return next;
}

function completionReady(state) {
  return !!state && state.exitFinished === true &&
    state.stdoutFinished === true && state.stderrFinished === true;
}

function normalizedTrigger(value) {
  var trigger = String(value || "manual").toLowerCase();
  if (trigger === "configuration" || trigger === "timer" ||
      trigger === "stale" || trigger === "queued") return trigger;
  return "manual";
}

function manualRefreshAllowed(lastStartedMs, nowMs, cooldownMs) {
  var last = finiteNumber(lastStartedMs, 0);
  var now = finiteNumber(nowMs, 0);
  var cooldown = Math.max(0, finiteNumber(cooldownMs, 0));
  if (last <= 0 || cooldown <= 0) return true;
  // A backwards wall-clock adjustment must not lock manual refresh forever.
  if (now < last) return true;
  return now - last >= cooldown;
}

function cooldownRemainingMs(lastStartedMs, nowMs, cooldownMs) {
  if (manualRefreshAllowed(lastStartedMs, nowMs, cooldownMs)) return 0;
  return Math.max(0, cooldownMs - (nowMs - lastStartedMs));
}

function refreshDecision(triggerValue, busy, lastStartedMs, nowMs, cooldownMs) {
  var trigger = normalizedTrigger(triggerValue);
  if (busy) {
    // A request already in flight satisfies a repeated manual gesture. System
    // changes, however, need one latest-state follow-up after the child exits.
    return { start: false, queue: trigger !== "manual", reason: "busy" };
  }
  if (trigger === "manual" &&
      !manualRefreshAllowed(lastStartedMs, nowMs, cooldownMs)) {
    return { start: false, queue: false, reason: "cooldown" };
  }
  return { start: true, queue: false, reason: "start" };
}

function canDrainQueue(queued, refreshing, requestActive, processRunning) {
  return queued === true && refreshing !== true && requestActive !== true &&
    processRunning !== true;
}

function nextFailureCount(currentValue, configuredCount, freshCount, errorCount) {
  var current = boundedInteger(currentValue, 0, 0, 8);
  var total = boundedInteger(configuredCount, 0, 0, 12);
  var fresh = boundedInteger(freshCount, 0, 0, total);
  var errors = boundedInteger(errorCount, 0, 0, 12);
  var failed;

  if (total === 0) return 0;
  failed = Math.max(total - fresh, errors);
  if (failed <= 0) return 0;
  // Back off when at least half the requested watchlist failed. A mostly-good
  // partial cycle recovers cautiously rather than wiping a prior failure run.
  if (failed * 2 >= total) return Math.min(8, current + 1);
  return Math.max(0, current - 1);
}

function filterConfiguredState(nextSymbols, quotes, errors) {
  var symbols = Object.prototype.toString.call(nextSymbols) === "[object Array]"
    ? nextSymbols : [];
  var quoteSource = Object.prototype.toString.call(quotes) === "[object Array]"
    ? quotes : [];
  var errorSource = Object.prototype.toString.call(errors) === "[object Array]"
    ? errors : [];
  var retainedQuotes = [];
  var retainedErrors = [];
  var index;
  var cursor;

  for (index = 0; index < symbols.length && retainedQuotes.length < 12; index += 1) {
    for (cursor = 0; cursor < quoteSource.length; cursor += 1) {
      if (!quoteSource[cursor] ||
          String(quoteSource[cursor].symbol || "") !== String(symbols[index])) continue;
      var retained = {};
      for (var key in quoteSource[cursor]) {
        if (Object.prototype.hasOwnProperty.call(quoteSource[cursor], key))
          retained[key] = quoteSource[cursor][key];
      }
      retained.stale = true;
      retainedQuotes.push(retained);
      break;
    }
  }

  for (index = 0; index < errorSource.length && retainedErrors.length < 12; index += 1) {
    if (!errorSource[index]) continue;
    var errorSymbol = String(errorSource[index].symbol || "");
    if (errorSymbol !== "" && symbols.indexOf(errorSymbol) !== -1)
      retainedErrors.push(errorSource[index]);
  }
  return { quotes: retainedQuotes, errors: retainedErrors };
}

function stoppedGenerationDecision(options) {
  var value = options && typeof options === "object" ? options : {};
  if (value.generationMatches !== true || value.processRunning === true)
    return "wait";
  if (value.requestActive !== true) return "retire";
  if (completionReady(value.completion)) return "complete";
  if (value.discardResponse === true) return "discard";
  if (value.timedOut === true) return "timeout";
  var completion = value.completion || beginCompletion(0);
  if (!completion.exitFinished && !completion.stdoutFinished &&
      !completion.stderrFinished) return "start-failed";
  return "incomplete";
}

// Node's parser does not understand `.pragma library`; the portable harness
// removes that line before evaluating this otherwise-identical source.
if (typeof module !== "undefined" && module && module.exports) {
  module.exports = {
    beginCompletion: beginCompletion,
    recordExit: recordExit,
    recordStdout: recordStdout,
    recordStderr: recordStderr,
    completionReady: completionReady,
    manualRefreshAllowed: manualRefreshAllowed,
    cooldownRemainingMs: cooldownRemainingMs,
    pollingDecision: pollingDecision,
    failureBackoffInterval: failureBackoffInterval,
    refreshDecision: refreshDecision,
    canDrainQueue: canDrainQueue,
    nextFailureCount: nextFailureCount,
    filterConfiguredState: filterConfiguredState,
    stoppedGenerationDecision: stoppedGenerationDecision,
    HISTORY_RANGES: HISTORY_RANGES,
    normalizeHistoryRange: normalizeHistoryRange,
    historyRequestDecision: historyRequestDecision,
    acceptsHistoryResult: acceptsHistoryResult,
    touchLru: touchLru
  };
}
