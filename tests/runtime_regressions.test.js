#!/usr/bin/env node
"use strict";

// Execute production JS functions from QML; this does not claim QML rendering.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const vm = require("node:vm");
const {spawnSync} = require("node:child_process");
const root = path.resolve(__dirname, "..");
const read = name => fs.readFileSync(path.join(root, name), "utf8");
const service = read("Service.qml");
const panel = read("Panel.qml");
const bar = read("BarWidget.qml");

function functions(source, names, context) {
  vm.createContext(context);
  for (const name of names) {
    const match = source.match(new RegExp("^  function " + name + "\\([^]*?\\n  }", "m"));
    assert.ok(match, "production function exists: " + name);
    vm.runInContext(match[0], context);
  }
  return context;
}

const commandContext = functions(service, ["helperCommand"], {
  pythonInterpreterPath: "/usr/bin/python3",
  helperPath: path.join(root, "scripts/fetch_quotes.py"),
});
const command = Array.from(commandContext.helperCommand([
  "--fixture", path.join(root, "demo/fixtures/quotes.json"),
]));
assert.deepEqual(command.slice(0, 4), ["/usr/bin/python3", "-I", "-S", commandContext.helperPath]);
assert.equal((service.match(/clearEnvironment: true/g) || []).length, 2);
assert.equal((service.match(/environment: \(\{ LANG: "C.UTF-8", LC_ALL: "C.UTF-8" \}\)/g) || []).length, 2);
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "markets-startup-"));
try {
  fs.writeFileSync(path.join(temporary, "sitecustomize.py"), 'print("UNEXPECTED_STARTUP")\n');
  fs.writeFileSync(path.join(temporary, "json.py"), 'raise RuntimeError("shadowed stdlib")\n');
  // Even if a future launch accidentally inherits the host environment, -I/-S
  // must reject Python path hooks. Test the actual command produced by QML.
  for (const env of [
    {LANG: "C.UTF-8", LC_ALL: "C.UTF-8"},
    {...process.env, PYTHONPATH: temporary, PYTHONHOME: "/missing", PYTHONUSERBASE: temporary},
  ]) {
    const result = spawnSync(command[0], command.slice(1), {
      env, cwd: temporary, encoding: "utf8", timeout: 3000,
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stderr, "");
    assert.ok(JSON.parse(result.stdout).quotes.length > 0);
  }
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}

const colors = functions(panel, ["linearChannel", "relativeLuminance", "contrastRatio"], {});
const color = (r, g, b, a = 1) => ({r, g, b, a});
const dimExpression = panel.match(/readonly property color dim: ([^]*?)(?=\n  readonly property)/)[1];
for (const sample of [
  {bg: color(0.06, 0.07, 0.08), muted: color(.2, .2, .2), fg: color(.9, .9, .9), fallback: true},
  {bg: color(.98, .98, .98), muted: color(.8, .8, .8), fg: color(.1, .1, .1), fallback: true},
  {bg: color(0, 0, 0), muted: color(.65, .65, .65), fg: color(1, 1, 1), fallback: false},
  {bg: color(0, 0, 0, .5), muted: color(.65, .65, .65), fg: color(1, 1, 1), fallback: true},
]) {
  colors.popupBackground = sample.bg;
  colors.Omarchy = {Color: {muted: sample.muted}};
  colors.foreground = sample.fg;
  const result = vm.runInContext(dimExpression, colors);
  assert.equal(result, sample.fallback ? sample.fg : sample.muted);
  if (sample.bg.a === 1) assert.ok(colors.contrastRatio(result, sample.bg) >= 4.5);
}

const model = {};
vm.runInNewContext(read("MarketModel.js").replace(/^\.pragma library\s*/, ""), model);
const watchlists = {MarketModel: model};
vm.runInNewContext(read("WatchlistModel.js").replace(/^\.(?:pragma|import).*$/gm, ""), watchlists);
const settings = functions(bar, ["hasOwn", "boundedInteger", "normalizedSettingsPatch"], {
  MarketModel: model, WatchlistModel: watchlists, selectedRange: "1d", barMode: "ticker", tickerWidth: 220,
  tickerSpeed: 24, refreshInterval: 900,
});
const previous = JSON.parse(read("tests/fixtures/v0.3.3-state.json")).settings;
const preserved = settings.normalizedSettingsPatch({}, structuredClone(previous));
assert.deepEqual(JSON.parse(JSON.stringify(preserved)), previous);
const paused = settings.normalizedSettingsPatch({tickerPaused: false}, structuredClone(previous));
assert.deepEqual(JSON.parse(JSON.stringify(paused)), {...previous, tickerPaused: false});
const disabled = {...previous, dataEnabled: false};
assert.equal(settings.normalizedSettingsPatch({}, disabled).dataEnabled, false);
console.log("Helper isolation, popup contrast and v0.3.3 settings regressions passed.");

const detailState = functions(panel, ["setDetailsExpanded", "toggleDetails", "requestFocusedHistory"], {
  detailsExpanded: true, focusedSymbol: "ACME", dataEnabled: true, selectedRange: "1mo",
  chartView: true, Qt: {callLater: callback => callback()},
  keyCatcher: {forceActiveFocus() {}},
  service: {calls: [], requestHistory(symbol, range) { this.calls.push([symbol, range]); }},
});
detailState.root = detailState;
Object.defineProperty(detailState, "displayingDetails", {get() { return this.chartView && this.detailsExpanded; }});
detailState.hostWidget = {setChartVisible(value) { detailState.detailsExpanded = value; }};
detailState.toggleDetails();
assert.equal(detailState.detailsExpanded, false);
assert.equal(detailState.chartView, false, "returning to the watchlist replaces the chart view");
detailState.requestFocusedHistory();
assert.equal(detailState.service.calls.length, 0, "collapsed selection does not request history");
detailState.focusedSymbol = "OTHER";
detailState.toggleDetails();
assert.equal(detailState.detailsExpanded, true);
assert.equal(detailState.chartView, true);
assert.deepEqual(detailState.service.calls, [["OTHER", "1mo"]], "expanding loads the current selection");
console.log("Chart collapse and expansion regressions passed.");

// Run the shipped service response/age paths with a deterministic clock. No
// process or network is started; these are provider snapshots, not live prices.
let quoteClock = Date.parse("2026-10-12T15:00:00Z");
class QuoteClock extends Date { static now() { return quoteClock; } }
const lifecycle = {};
vm.runInNewContext(read("ServiceLifecycle.js").replace(/^\.pragma library\s*/, ""), lifecycle);
const quoteService = functions(service, ["mergeFreshQuotes", "completePartialErrors", "consumeResponse",
  "expireQuoteAges", "failRequest", "conciseError"], {
  Date: QuoteClock, MarketModel: model, ServiceLifecycle: lifecycle,
  _requestActive: true, _activeGeneration: 1, _requestTimedOut: false,
  _activeSymbolsKey: "ACME", symbolsKey: "ACME", configuredSymbols: ["ACME"],
  quotes: [], refreshIntervalSec: 900, pollingAllowed: true, consecutiveFailures: 0, revision: 0,
  settleActiveRequest() {}, syncOneDayHistory() {}, runQueuedRefresh() {},
});
Object.defineProperty(quoteService, "hasData", {get: () => quoteService.quotes.length > 0});
const oldQuote = {symbol: "ACME", currency: "USD", regularMarketPrice: 123,
  marketTime: "2026-10-09T20:00:00Z", sessionState: "regular",
  regularSessionStart: "2026-10-12T13:30:00Z", regularSessionEnd: "2026-10-12T20:00:00Z"};
function deliverQuotes(quotes, errors = []) {
  quoteService.consumeResponse(1, 0, JSON.stringify({schemaVersion: 1, provider: "Fictional fixture",
    generatedAt: new Date(quoteClock).toISOString(), quotes, errors}), "");
}
deliverQuotes([oldQuote]);
assert.equal(quoteService.state, "stale", "successful fetch cannot make a three-day-old open-market quote fresh");
assert.equal(quoteService.quotes[0].stale, true);
assert.match(quoteService.lastError, /older than expected/);
assert.equal(quoteService.consecutiveFailures, 0, "quote age is not a transport failure");
const freshQuote = {...oldQuote, marketTime: "2026-10-12T14:59:00Z"};
deliverQuotes([freshQuote]);
assert.equal(quoteService.state, "ready", "a new quote clears the stale flag");
assert.equal(quoteService.quotes[0].stale, false);
const status = functions(panel, ["stateLabel"], {
  MarketModel: model, dataEnabled: true, symbols: ["ACME"], service: quoteService, nowMs: quoteClock,
});
assert.equal(status.stateLabel(), "Fetched just now", "the header describes fetch time explicitly");
quoteClock += 31 * 60 * 1000;
quoteService.expireQuoteAges();
assert.equal(quoteService.state, "stale", "aging/resume marks an old quote without another fetch");
assert.equal(quoteService.quotes[0].stale, true);
quoteClock = Date.parse("2026-10-12T15:00:00Z");
quoteService.configuredSymbols = ["ACME", "OTHER"];
quoteService.symbolsKey = quoteService._activeSymbolsKey = "ACME,OTHER";
deliverQuotes([freshQuote, {...oldQuote, symbol: "OTHER"}]);
assert.equal(quoteService.state, "partial");
assert.deepEqual(Array.from(quoteService.quotes, q => q.stale), [false, true]);
deliverQuotes([freshQuote], [{symbol: "OTHER", code: "offline", message: "Offline"}]);
assert.equal(quoteService.state, "partial");
assert.equal(quoteService.quotes[1].regularMarketPrice, 123, "partial errors preserve last-good values");
quoteService.failRequest("Offline", "offline");
quoteService.expireQuoteAges();
assert.equal(quoteService.state, "stale", "the age timer cannot recover a failed fetch");
quoteService.configuredSymbols = ["ACME"];
quoteService.symbolsKey = quoteService._activeSymbolsKey = "ACME";
deliverQuotes([{...oldQuote, sessionState: "closed", regularSessionStart: "2026-10-09T13:30:00Z",
  regularSessionEnd: "2026-10-09T20:00:00Z"}]);
assert.equal(quoteService.state, "ready", "last completed session does not expire over a weekend");
assert.equal(quoteService.quotes[0].stale, false);
console.log("Quote age, fetch labeling, partial responses, recovery and closed-session regressions passed.");
