#!/usr/bin/env node
"use strict";

// Exercise shipped transitions and QML JS methods, without claiming Qt rendering.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const read = name => fs.readFileSync(path.join(__dirname, "..", name), "utf8");
const plain = value => JSON.parse(JSON.stringify(value));
const market = {};
vm.runInNewContext(read("MarketModel.js").replace(/^\.pragma.*$/gm, ""), market);
const model = {MarketModel: market};
vm.runInNewContext(read("WatchlistModel.js").replace(/^\.(pragma|import).*$/gm, ""), model);

function methods(source, names, context) {
  vm.createContext(context);
  context.root = context;
  for (const name of names) {
    const match = source.match(new RegExp("^  function " + name + "\\([^]*?\\n  }", "m"));
    assert.ok(match, "production method exists: " + name);
    vm.runInContext(match[0], context);
  }
  return context;
}

function widget(settings) {
  const context = {
    settings: plain(settings), moduleName: "io.github.tcballard.omarchy-markets",
    MarketModel: market, WatchlistModel: model, writes: [],
    Qt: {callLater() {}}, injectPanel() {},
    selectedRange: "1d", barMode: "ticker", tickerWidth: 220,
    tickerSpeed: 24, refreshInterval: 900,
  };
  Object.defineProperties(context, {
    configuredSymbols: {get() { return market.normalizeSymbols(context.settings.symbols); }},
    primarySymbol: {get() { return model.snapshot(context.settings).primarySymbol; }},
  });
  context.bar = {shell: {updateEntryInline(id, entry) {
    assert.equal(id, context.moduleName);
    context.writes.push(plain(entry));
  }}};
  return methods(read("BarWidget.qml"), [
    "hasOwn", "boundedInteger", "normalizedSettingsPatch", "persistSettings",
    "applyProfile", "addSymbol", "removeSymbol", "moveSymbol", "setPrimarySymbol",
    "setChartVisible", "setSortMode", "setDataEnabled", "applyWatchlistResult",
    "createWatchlist", "selectWatchlist", "renameWatchlist", "deleteWatchlist",
  ], context);
}

const legacy = {
  symbols: "ACME, NORTH, LUMA", primarySymbol: "NORTH", profile: "",
  dataEnabled: false, selectedRange: "1mo", tickerPaused: true,
  refreshIntervalSec: 1800, tickerWidth: 260, customFutureSetting: "preserve me",
};
const original = plain(legacy);
const initial = plain(model.libraryForSettings(legacy));
assert.equal(initial.lists[0].name, "My watchlist");
assert.deepEqual(initial.lists[0].symbols, ["ACME", "NORTH", "LUMA"]);
assert.equal(initial.lists[0].primarySymbol, "NORTH");
assert.deepEqual(legacy, original, "reading old settings never migrates or mutates them");

const bar = widget(legacy);
assert.equal(bar.createWatchlist("Work", false).ok, true);
const work = bar.settings.activeWatchlistId;
assert.equal(bar.settings.watchlists.length, 2, "first copy preserves the legacy list");
assert.equal(bar.settings.dataEnabled, false, "saving a list is not network consent");
assert.equal(bar.settings.customFutureSetting, "preserve me");
assert.equal(bar.addSymbol("DELTA").ok, true);
assert.equal(bar.setPrimarySymbol("DELTA"), true);
bar.moveSymbol("DELTA", 0);
const workSymbols = "DELTA, ACME, NORTH, LUMA";
assert.equal(bar.settings.symbols, workSymbols);
assert.equal(bar.settings.watchlists[0].symbols.includes("DELTA"), false);

assert.equal(bar.createWatchlist("Crypto", true).ok, true);
const crypto = bar.settings.activeWatchlistId;
assert.equal(bar.settings.symbols, "");
bar.addSymbol("BTC-USD");
assert.equal(bar.selectWatchlist(work).ok, true);
assert.equal(bar.settings.symbols, workSymbols);
assert.equal(bar.settings.primarySymbol, "DELTA");
assert.equal(bar.selectWatchlist(crypto).ok, true);
assert.equal(bar.settings.symbols, "BTC-USD");
assert.equal(bar.settings.primarySymbol, "BTC-USD");
assert.equal(bar.settings.dataEnabled, false);

const reloaded = widget(bar.settings); // JSON boundary used by inline shell.json.
reloaded.selectWatchlist(work);
assert.equal(reloaded.settings.symbols, workSymbols);
assert.equal(reloaded.renameWatchlist("Research").ok, true);
assert.equal(reloaded.settings.activeWatchlistId, work, "renaming preserves identity");
assert.equal(reloaded.createWatchlist("research", false).ok, false);
assert.equal(reloaded.renameWatchlist("Crypto").ok, false);
assert.equal(reloaded.createWatchlist("x".repeat(33), false).ok, false);
assert.equal(reloaded.createWatchlist("   ", false).ok, false);
assert.equal(reloaded.settings.customFutureSetting, "preserve me");

reloaded.applyProfile("uk");
assert.equal(reloaded.settings.profile, "uk");
assert.equal(reloaded.settings.activeWatchlistId, work);
reloaded.selectWatchlist(crypto);
assert.equal(reloaded.settings.symbols, "BTC-USD", "a starting profile changes only the active list");
assert.equal(reloaded.deleteWatchlist(crypto).ok, true);
assert.equal(reloaded.settings.activeWatchlistId, work);
assert.equal(reloaded.settings.profile, "uk");
assert.equal(reloaded.settings.primarySymbol, "^FTSE");
reloaded.deleteWatchlist(work);
const beforeRefusal = plain(reloaded.settings);
assert.equal(reloaded.deleteWatchlist(reloaded.settings.activeWatchlistId).ok, false);
assert.deepEqual(plain(reloaded.settings), beforeRefusal, "last list cannot be deleted");

for (let i = 2; i <= 8; i++) assert.equal(reloaded.createWatchlist("List " + i, true).ok, true);
const beforeLimit = plain(reloaded.settings);
assert.equal(reloaded.createWatchlist("Overflow", true).ok, false);
assert.deepEqual(plain(reloaded.settings), beforeLimit);
assert.equal(reloaded.writes.length > 0, true, "changes use the host's updateEntryInline API");

const corrupted = plain(beforeLimit);
corrupted.activeWatchlistId = "missing";
assert.equal(model.select(corrupted, corrupted.watchlists[0].id).ok, false);
assert.deepEqual(plain(model.saveActive(plain(corrupted))), corrupted,
  "an invalid active ID must not overwrite another saved list");
const hostile = [{id: "__proto__", name: "No", symbols: "ACME"},
  {id: "watchlist-1", name: "<b>literal</b>", symbols: ["ACME", "bad/path"], primarySymbol: "missing"},
  {id: "watchlist-2", name: "<b>literal</b>", symbols: "NORTH"}];
const normalized = plain(model.normalizeLists(hostile));
assert.equal(normalized.length, 1);
assert.equal(normalized[0].name, "<b>literal</b>");
assert.equal(normalized[0].primarySymbol, "ACME");
assert.deepEqual(normalized[0].symbols, ["ACME"]);

const symbols = ["ACME", "NORTH", "LUMA", "UNKNOWN", "ZERO"];
const quotes = [
  {symbol: "ACME", changePercent: 3}, {symbol: "NORTH", changePercent: -2},
  {symbol: "LUMA", changePercent: 3}, {symbol: "ZERO", changePercent: 0},
];
assert.deepEqual(plain(model.sortSymbols(symbols, quotes, "gainers")), ["ACME", "LUMA", "ZERO", "NORTH", "UNKNOWN"]);
assert.deepEqual(plain(model.sortSymbols(symbols, quotes, "losers")), ["NORTH", "ZERO", "ACME", "LUMA", "UNKNOWN"]);
assert.deepEqual(plain(model.sortSymbols(symbols, quotes, "saved")), symbols);
assert.deepEqual(plain(model.sortSymbols(symbols, [], "gainers")), symbols);
assert.equal(model.normalizeSort("invalid"), "saved");
const savedOrder = reloaded.settings.symbols;
reloaded.setSortMode("gainers");
reloaded.setChartVisible(false);
const restarted = widget(reloaded.settings);
assert.equal(restarted.settings.sortMode, "gainers");
assert.equal(restarted.settings.chartVisible, false);
assert.equal(restarted.settings.symbols, savedOrder, "sorting does not rewrite configured symbols");

const panel = {
  symbols, quotes, sortMode: "gainers", selectedSymbol: "ACME", primarySymbol: "ACME",
  setupRequired: false, managing: false, keyboardCursor: false,
  Qt: {callLater() {}}, requestFocusedHistory() {},
};
Object.defineProperties(panel, {
  focusedSymbol: {get() { return panel.symbols.includes(panel.selectedSymbol) ? panel.selectedSymbol : panel.primarySymbol; }},
  selectedIndex: {get() { return panel.symbols.indexOf(panel.focusedSymbol); }},
  displaySymbols: {get() { return model.sortSymbols(panel.symbols, panel.quotes, panel.sortMode); }},
});
methods(read("Panel.qml"), ["moveSelection", "inspectSymbol", "pinFocused", "removeManagedSymbol"], panel);
panel.moveSelection(1);
assert.equal(panel.focusedSymbol, "LUMA", "keyboard moves through displayed ranking");
panel.quotes = [{symbol: "NORTH", changePercent: 20}, {symbol: "LUMA", changePercent: -8}];
assert.equal(panel.focusedSymbol, "LUMA", "refreshing rankings keeps selection on the same symbol");
let pinned;
panel.hostWidget = {setPrimarySymbol(symbol) { pinned = symbol; }};
panel.pinFocused();
assert.equal(pinned, "LUMA", "pin acts on the inspected instrument after reordering");
panel.managing = true;
panel.moveSelection(-1);
assert.equal(panel.focusedSymbol, "NORTH", "manager navigation uses saved order");
panel.hostWidget.removeSymbol = symbol => {
  const result = market.removeSymbol(panel.symbols, symbol);
  if (result.ok) panel.symbols = result.symbols;
  return result;
};
panel.removeManagedSymbol("NORTH");
assert.equal(panel.focusedSymbol, "LUMA", "removing the selected row keeps the adjacent row selected");
panel.removeManagedSymbol("UNKNOWN");
assert.equal(panel.focusedSymbol, "LUMA", "removing another row preserves the inspected symbol");
assert.deepEqual(symbols, ["ACME", "NORTH", "LUMA", "UNKNOWN", "ZERO"]);

console.log("Named watchlist migration, persistence, isolation, limits, sorting and selection regressions passed.");
