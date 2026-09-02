#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const lifecyclePath = path.join(__dirname, "..", "ServiceLifecycle.js");
const originalSource = fs.readFileSync(lifecyclePath, "utf8");
assert.match(originalSource, /^\.pragma library\s*$/m,
  "QML library pragma is required");
const nodeSource = originalSource.replace(/^\.pragma library\s*$/m, "");
const moduleObject = { exports: {} };
new Function("module", "exports", nodeSource)(moduleObject, moduleObject.exports);
const lifecycle = moduleObject.exports;

let passed = 0;
const failures = [];

function test(name, body) {
  try {
    body();
    passed += 1;
  } catch (error) {
    failures.push({ name, error });
  }
}

test("exit-first completion waits for both closed streams", () => {
  let state = lifecycle.beginCompletion(7);
  state = lifecycle.recordExit(state, 7, 0);
  assert.equal(lifecycle.completionReady(state), false);
  state = lifecycle.recordStdout(state, 7, '{"status":"ready"}');
  assert.equal(lifecycle.completionReady(state), false);
  state = lifecycle.recordStderr(state, 7, "");
  assert.equal(lifecycle.completionReady(state), true);
  assert.equal(state.exitCode, 0);
  assert.equal(state.stdout, '{"status":"ready"}');
});

test("collector-first completion waits for process exit", () => {
  let state = lifecycle.beginCompletion(8);
  state = lifecycle.recordStderr(state, 8, "warning");
  state = lifecycle.recordStdout(state, 8, "{}");
  assert.equal(lifecycle.completionReady(state), false);
  state = lifecycle.recordExit(state, 8, 1);
  assert.equal(lifecycle.completionReady(state), true);
  assert.equal(state.stderr, "warning");
});

test("Service wires all process signals through the generation gate", () => {
  const service = fs.readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8");
  assert.match(service, /recordStdout\(_completion, generation, text\)/);
  assert.match(service, /recordStderr\(_completion, generation, text\)/);
  assert.match(service, /recordExit\(_completion, generation, exitCode\)/);
  assert.match(service, /!ServiceLifecycle\.completionReady\(_completion\)/);
  assert.doesNotMatch(service, /onExited[\s\S]{0,180}consumeResponse\s*\(/);
  assert.match(service, /property int generationToken: 0/);
  assert.match(service, /settleStoppedGeneration\(root\._completionFallbackGeneration\)/);
  assert.match(service, /ServiceLifecycle\.stoppedGenerationDecision\(\{/);
  assert.match(service, /helper could not be started/);
  assert.doesNotMatch(service,
    /onRunningChanged[\s\S]{0,220}Qt\.callLater[\s\S]{0,120}requestProcess/);
});

test("Service has bounded TERM to KILL escalation and forced retirement", () => {
  const service = fs.readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8");
  assert.match(service, /process\.running = false/);
  assert.match(service, /process\.signal\(9\)/);
  assert.match(service, /id: terminateEscalation/);
  assert.match(service, /id: killFallback/);
  assert.match(service, /retireProcessObject\(process, true\)/);
});

test("Service gates polling on consent and safe first-party placement", () => {
  const service = fs.readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8");
  assert.match(service, /function configure\(symbolsValue, intervalValue, dataEnabledValue\)/);
  assert.match(service, /var nextDataEnabled = dataEnabledValue === true/);
  assert.match(service, /typeof pluginRegistry\.inBar !== "function"/);
  assert.match(service, /pluginRegistry\.inBar\(String\(manifest\.id\)\) === true/);
  assert.match(service, /String\(manifest\.id \|\| ""\) === "omarchy\.markets"/);
  assert.match(service, /function deactivateData\(nextState, clearData\)/);
  assert.match(service, /running: root\.pollingAllowed/);
});

test("Service quote and history polling use separate fixed XDG cache files", () => {
  const service = fs.readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8");
  assert.match(service, /Quickshell\.env\("XDG_CACHE_HOME"\)/);
  assert.match(service, /cacheRoot \+ "\/omarchy-markets"/);
  assert.match(service, /cacheDirectoryPath \+ "\/quotes-v1\.json"/);
  assert.match(service, /function historyCacheFilePath\(symbolValue, rangeValue\)/);
  assert.match(service, /cacheDirectoryPath \+ "\/history\/" \+ normalized\[0\] \+ "-" \+ range \+ "-v1\.json"/);
  assert.match(service, /"--symbols", symbolsKey,[\s\S]{0,100}"--range", "1d",[\s\S]{0,100}"--cache-file", quoteCacheFilePath/);
  assert.match(service, /"--symbols", historySymbol,[\s\S]{0,100}"--range", historyRange,[\s\S]{0,100}"--cache-file", cachePath/);
  assert.match(service, /MarketModel\.recommendedRefreshInterval\(quotes, refreshIntervalSec\)/);
  assert.match(service, /ServiceLifecycle\.failureBackoffInterval\(/);
});

test("quote and history workers ignore hostile PATH interpreter shadows", () => {
  const service = fs.readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8");
  assert.match(service, /readonly property string pythonInterpreterPath: "\/usr\/bin\/python3"/);
  assert.match(service, /function helperCommand\(argumentsValue\)/);
  assert.match(service, /pythonInterpreterPath !== "\/usr\/bin\/python3"/);
  assert.equal((service.match(/var command = helperCommand\(\[/g) || []).length, 2,
    "both quote and history workers must use the trusted command builder");
  assert.doesNotMatch(service, /"\/usr\/bin\/env"\s*,\s*"python3"/);
  assert.doesNotMatch(service, /Quickshell\.env\("PATH"\)/);
});

test("Service history is independently generated, watched, cached, and last-request-wins", () => {
  const service = fs.readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8");
  assert.match(service, /function requestHistory\(symbolValue, rangeValue\)/);
  assert.match(service, /id: historyProcessComponent/);
  assert.match(service, /id: historyWatchdog/);
  assert.match(service, /property int _activeHistoryGeneration: 0/);
  assert.match(service, /ServiceLifecycle\.acceptsHistoryResult\(/);
  assert.match(service, /ServiceLifecycle\.touchLru\(_historyCacheOrder, key, 24\)/);
  assert.match(service, /function historyCacheFresh\(quote\)/);
  assert.match(service, /id: historyDebounce/);
  assert.match(service, /if \(!historyTerminateEscalation\.running\) historyTerminateEscalation\.start\(\)/);
  assert.match(service, /historyRequestDecision\(\s*range, !!oneDayQuote, !!cached\)/);
  assert.match(service, /"--symbols", historySymbol,[\s\S]{0,100}"--range", historyRange/);
  assert.doesNotMatch(service, /function requestHistory[\s\S]{0,600}root\.refresh\(/);
});

test("Service exposes only the renamed bounded IPC status", () => {
  const service = fs.readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8");
  assert.match(service, /target: "io\.github\.tcballard\.omarchy-markets"/);
  assert.doesNotMatch(service, /io\.github\.tcballard\.market-watch/);
  assert.match(service, /cacheEntries: root\.historyCacheSize/);
  assert.doesNotMatch(service, /historyQuote:\s*root\.historyQuote/);
});

test("stale generation signals cannot mutate the active completion", () => {
  const active = lifecycle.beginCompletion(12);
  assert.strictEqual(lifecycle.recordExit(active, 11, 0), active);
  assert.strictEqual(lifecycle.recordStdout(active, 11, "stale"), active);
  assert.strictEqual(lifecycle.recordStderr(active, 13, "future"), active);
  assert.equal(lifecycle.completionReady(active), false);
});

test("stopped generations have executable terminal fallback decisions", () => {
  const empty = lifecycle.beginCompletion(21);
  const base = {
    generationMatches: true,
    processRunning: false,
    requestActive: true,
    completion: empty,
    discardResponse: false,
    timedOut: false
  };
  assert.equal(lifecycle.stoppedGenerationDecision(base), "start-failed");
  assert.equal(lifecycle.stoppedGenerationDecision({ ...base, timedOut: true }), "timeout");
  assert.equal(lifecycle.stoppedGenerationDecision({ ...base, discardResponse: true }), "discard");
  assert.equal(lifecycle.stoppedGenerationDecision({ ...base, requestActive: false }), "retire");
  assert.equal(lifecycle.stoppedGenerationDecision({ ...base, processRunning: true }), "wait");

  let partial = lifecycle.recordStdout(empty, 21, "{}");
  assert.equal(lifecycle.stoppedGenerationDecision({ ...base, completion: partial }), "incomplete");
  partial = lifecycle.recordStderr(partial, 21, "");
  partial = lifecycle.recordExit(partial, 21, 0);
  assert.equal(lifecycle.stoppedGenerationDecision({ ...base, completion: partial }), "complete");
});

test("manual refresh is ignored while busy and does not queue", () => {
  assert.deepEqual(
    lifecycle.refreshDecision("manual", true, 0, 1000, 30000),
    { start: false, queue: false, reason: "busy" }
  );
});

test("network data requires strict consent and first-party bar placement", () => {
  assert.deepEqual(
    lifecycle.pollingDecision({ dataEnabled: "true", firstParty: false, inBar: true, symbolCount: 4 }),
    { allowed: false, state: "setup", reason: "consent" }
  );
  assert.deepEqual(
    lifecycle.pollingDecision({ dataEnabled: true, firstParty: true, inBar: false, symbolCount: 4 }),
    { allowed: false, state: "disabled", reason: "not-in-bar" }
  );
  assert.deepEqual(
    lifecycle.pollingDecision({ dataEnabled: true, firstParty: true, inBar: true, symbolCount: 4 }),
    { allowed: true, state: "waiting", reason: "allowed" }
  );
  assert.deepEqual(
    lifecycle.pollingDecision({ dataEnabled: true, firstParty: false, inBar: false, symbolCount: 4 }),
    { allowed: true, state: "waiting", reason: "allowed" }
  );
  assert.deepEqual(
    lifecycle.pollingDecision({ dataEnabled: true, firstParty: false, inBar: true, symbolCount: 0 }),
    { allowed: false, state: "empty", reason: "symbols" }
  );
});

test("recommended interval receives bounded exponential failure backoff", () => {
  assert.equal(lifecycle.failureBackoffInterval(300, 0, 3600), 300);
  assert.equal(lifecycle.failureBackoffInterval(300, 1, 3600), 600);
  assert.equal(lifecycle.failureBackoffInterval(900, 2, 3600), 3600);
  assert.equal(lifecycle.failureBackoffInterval(3600, 8, 3600), 3600);
});

test("history planning reuses one-day quotes and fetches longer ranges", () => {
  assert.deepEqual(
    lifecycle.historyRequestDecision("1d", true, false),
    { mode: "reuse", range: "1d", showCached: false }
  );
  assert.deepEqual(
    lifecycle.historyRequestDecision("1d", false, true),
    { mode: "wait", range: "1d", showCached: false }
  );
  assert.deepEqual(
    lifecycle.historyRequestDecision("6MO", true, true),
    { mode: "fetch", range: "6mo", showCached: true }
  );
  assert.equal(lifecycle.normalizeHistoryRange("junk", "1mo"), "1mo");
});

test("history results are last-request-wins by generation and cache key", () => {
  assert.equal(lifecycle.acceptsHistoryResult(8, 8, "AAPL|1y", "AAPL|1y"), true);
  assert.equal(lifecycle.acceptsHistoryResult(7, 8, "AAPL|1y", "AAPL|1y"), false);
  assert.equal(lifecycle.acceptsHistoryResult(8, 8, "MSFT|1y", "AAPL|1y"), false);
  assert.equal(lifecycle.acceptsHistoryResult(8, 8, "", ""), false);
});

test("history LRU is unique, recent-first bounded, and immutable", () => {
  const original = ["A|1y", "B|1y", "C|1y"];
  assert.deepEqual(lifecycle.touchLru(original, "B|1y", 3), ["A|1y", "C|1y", "B|1y"]);
  assert.deepEqual(original, ["A|1y", "B|1y", "C|1y"]);
  assert.deepEqual(lifecycle.touchLru(original, "D|1y", 3), ["B|1y", "C|1y", "D|1y"]);
});

test("system refresh coalesces one follow-up while busy", () => {
  ["configuration", "timer", "stale", "queued"].forEach((trigger) => {
    assert.deepEqual(
      lifecycle.refreshDecision(trigger, true, 0, 1000, 30000),
      { start: false, queue: true, reason: "busy" }
    );
  });
});

test("manual cooldown has an exact boundary and tolerates clock rollback", () => {
  assert.equal(lifecycle.manualRefreshAllowed(1000, 30999, 30000), false);
  assert.equal(lifecycle.manualRefreshAllowed(1000, 31000, 30000), true);
  assert.equal(lifecycle.manualRefreshAllowed(1000, 900, 30000), true);
  assert.equal(lifecycle.cooldownRemainingMs(1000, 16000, 30000), 15000);
});

test("queued work drains only after request and process are both settled", () => {
  assert.equal(lifecycle.canDrainQueue(true, false, false, true), false);
  assert.equal(lifecycle.canDrainQueue(true, false, true, false), false);
  assert.equal(lifecycle.canDrainQueue(true, true, false, false), false);
  assert.equal(lifecycle.canDrainQueue(true, false, false, false), true);
});

test("high partial-failure ratios increase backoff", () => {
  assert.equal(lifecycle.nextFailureCount(0, 12, 1, 11), 1);
  assert.equal(lifecycle.nextFailureCount(1, 12, 6, 6), 2);
  assert.equal(lifecycle.nextFailureCount(8, 12, 0, 12), 8);
});

test("mostly-good partial cycles recover cautiously", () => {
  assert.equal(lifecycle.nextFailureCount(3, 12, 11, 1), 2);
  assert.equal(lifecycle.nextFailureCount(0, 12, 11, 1), 0);
  assert.equal(lifecycle.nextFailureCount(5, 12, 12, 0), 0);
});

test("symbol reconfiguration drops unrelated old state", () => {
  const retained = lifecycle.filterConfiguredState(
    ["NEW"],
    [{ symbol: "OLD", regularMarketPrice: 10, stale: false }],
    [{ symbol: "OLD", code: "timeout", message: "Old failed" }]
  );
  assert.deepEqual(retained, { quotes: [], errors: [] });
  // A failed NEW fetch will therefore see hasData=false, rather than treating
  // OLD as stale data for the new watchlist.
  assert.equal(retained.quotes.length > 0, false);
});

test("symbol reconfiguration retains only matching quotes as stale", () => {
  const oldQuote = { symbol: "KEEP", regularMarketPrice: 10, stale: false };
  const retained = lifecycle.filterConfiguredState(
    ["KEEP", "NEW"],
    [oldQuote, { symbol: "DROP", regularMarketPrice: 20 }],
    [
      { symbol: "KEEP", code: "timeout", message: "Keep failed" },
      { symbol: "DROP", code: "timeout", message: "Drop failed" },
      { symbol: null, code: "global", message: "Old global error" }
    ]
  );
  assert.deepEqual(retained.quotes, [
    { symbol: "KEEP", regularMarketPrice: 10, stale: true }
  ]);
  assert.deepEqual(retained.errors, [
    { symbol: "KEEP", code: "timeout", message: "Keep failed" }
  ]);
  assert.equal(oldQuote.stale, false, "filter must not mutate last-good input");
});

if (failures.length > 0) {
  for (const failure of failures) {
    process.stderr.write(`not ok - ${failure.name}\n${failure.error.stack}\n`);
  }
  process.stderr.write(`${passed} passed; ${failures.length} failed\n`);
  process.exit(1);
}

process.stdout.write(`${passed} ServiceLifecycle tests passed.\n`);
