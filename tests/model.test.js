#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const modelPath = path.join(__dirname, "..", "MarketModel.js");
const originalSource = fs.readFileSync(modelPath, "utf8");
assert.match(originalSource, /^\.pragma library\s*$/m, "QML library pragma is required");

// QML's pragma is intentionally not JavaScript syntax. Remove only that line,
// then evaluate the otherwise unchanged ES5 library through its guarded Node
// export. This catches syntax errors in the exact file loaded by Quickshell.
const nodeSource = originalSource.replace(/^\.pragma library\s*$/m, "");
const moduleObject = { exports: {} };
new Function("module", "exports", nodeSource)(moduleObject, moduleObject.exports);
const model = moduleObject.exports;

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

function quote(overrides) {
  return Object.assign({
    symbol: "ACME",
    name: "Acme Incorporated",
    currency: "USD",
    regularMarketPrice: 102,
    previousClose: 100,
    change: 2,
    changePercent: 2,
    marketTime: "2026-08-31T12:00:00Z",
    sparkline: [100, 101, 102]
  }, overrides || {});
}

function documentWith(quotes, errors, overrides) {
  return Object.assign({
    schemaVersion: 1,
    provider: "Fictional market fixture",
    generatedAt: "2026-08-31T12:01:00Z",
    status: "ready",
    quotes: quotes || [],
    errors: errors || []
  }, overrides || {});
}

test("normalizes familiar Yahoo symbols", () => {
  assert.deepEqual(
    model.normalizeSymbols(" aapl, ^ftse, brk-b, GBPUSD=x, 0700.hk "),
    ["AAPL", "^FTSE", "BRK-B", "GBPUSD=X", "0700.HK"]
  );
});

test("deduplicates symbols after case and whitespace normalization", () => {
  assert.deepEqual(model.normalizeSymbols("aapl,AAPL, aApL ,msft"), ["AAPL", "MSFT"]);
});

test("accepts arrays without mutating them", () => {
  const input = [" aapl ", "MSFT"];
  assert.deepEqual(model.normalizeSymbols(input), ["AAPL", "MSFT"]);
  assert.deepEqual(input, [" aapl ", "MSFT"]);
});

test("accepts the same bounded Yahoo symbol grammar as the helper", () => {
  assert.deepEqual(
    model.normalizeSymbols("AAPL,bad/name,bad name,TEST+X,TEST_X,^^,=,BTC-USD"),
    ["AAPL", "TEST+X", "TEST_X", "BTC-USD"]
  );
});

test("caps normalized watchlists at twelve unique symbols", () => {
  const symbols = Array.from({ length: 20 }, (_, index) => `sym${index}`).join(",");
  assert.equal(model.normalizeSymbols(symbols).length, 12);
  assert.deepEqual(model.normalizeSymbols(symbols, 3), ["SYM0", "SYM1", "SYM2"]);
  assert.equal(model.normalizeSymbols(symbols, 99).length, 12);
});

test("rejects empty, overlong, and malformed symbol inputs", () => {
  assert.equal(model.normalizeSymbol(""), null);
  assert.equal(model.normalizeSymbol("A".repeat(33)), null);
  assert.equal(model.normalizeSymbol(null), null);
  assert.deepEqual(model.normalizeSymbols(null), []);
  assert.deepEqual(model.normalizeSymbols({ symbols: "AAPL" }), []);
});

test("ships the six bounded Omarchy Markets profiles", () => {
  const catalog = model.profiles();
  assert.deepEqual(catalog.map((profile) => profile.id), [
    "markets", "mag7", "crypto", "meme-coins", "semiconductors", "uk"
  ]);
  assert.equal(catalog[1].name, "Magnificent 7");
  assert.equal(catalog[4].name, "AI & Semiconductors");
  assert.match(catalog[3].description, /speculative, high-volatility/i);
  assert.deepEqual(catalog[0].symbols, [
    "^GSPC", "^IXIC", "^DJI", "^RUT", "^VIX", "^FTSE", "^GDAXI", "^N225", "^HSI"
  ]);
  assert.deepEqual(catalog[2].symbols, [
    "BTC-USD", "ETH-USD", "SOL-USD", "XRP-USD", "BNB-USD", "ADA-USD",
    "LINK-USD", "AVAX-USD"
  ]);
  assert.ok(catalog.every((profile) => profile.symbols.length <= model.MAX_SYMBOLS));
  assert.ok(catalog.every((profile) => profile.symbols.includes(profile.primarySymbol)));
  assert.ok(catalog.every((profile) =>
    model.normalizeSymbols(profile.symbols).length === profile.symbols.length));
});

test("profile accessors return defensive copies", () => {
  const firstCatalog = model.profiles();
  firstCatalog[0].name = "Changed";
  firstCatalog[0].symbols.push("BAD");
  firstCatalog.push({ id: "extra" });
  assert.equal(model.profiles().length, 6);
  assert.equal(model.profileById("markets").name, "Markets");
  assert.equal(model.symbolsForProfile("markets").includes("BAD"), false);

  const symbols = model.symbolsForProfile("mag7");
  symbols.shift();
  assert.equal(model.symbolsForProfile("mag7")[0], "NVDA");
});

test("normalizes, resolves, and detects profile selections", () => {
  assert.equal(model.normalizeProfileId(" MEME-COINS "), "meme-coins");
  assert.equal(model.normalizeProfileId("missing"), null);
  assert.equal(model.normalizeProfileId("missing", "crypto"), "crypto");
  assert.equal(model.profileById(" MAG7 ").primarySymbol, "NVDA");
  assert.equal(model.profileById("unknown"), null);
  assert.deepEqual(model.symbolsForProfile("unknown"), []);

  const reordered = ["TSLA", "AAPL", "MSFT", "META", "GOOGL", "NVDA", "AMZN"];
  assert.equal(model.profileForSymbols(reordered).id, "mag7");
  assert.equal(model.profileForSymbols(reordered.concat("AMD")), null);
  const detected = model.profileForSymbols(reordered);
  detected.symbols.length = 0;
  assert.equal(model.profileForSymbols(reordered).symbols.length, 7);
});

test("normalizes bar modes and exposes defensive chart range options", () => {
  assert.equal(model.normalizeBarMode(" TICKER "), "ticker");
  assert.equal(model.normalizeBarMode("compact"), "single");
  assert.equal(model.normalizeBarMode(null, "ticker"), "ticker");
  assert.deepEqual(model.rangeOptions(), [
    { id: "1d", label: "1D", interval: "5m" },
    { id: "5d", label: "5D", interval: "15m" },
    { id: "1mo", label: "1M", interval: "1d" },
    { id: "6mo", label: "6M", interval: "1d" },
    { id: "1y", label: "1Y", interval: "1wk" }
  ]);
  const changed = model.rangeOptions();
  changed[0].id = "bad";
  changed.push({ id: "2y" });
  assert.equal(model.rangeOptions().length, 5);
  assert.equal(model.rangeOptions()[0].id, "1d");
});

test("normalizes and labels supported chart ranges", () => {
  assert.equal(model.normalizeRange(" 6MO "), "6mo");
  assert.equal(model.normalizeRange("1month"), "1mo");
  assert.equal(model.normalizeRange("bad"), "1d");
  assert.equal(model.normalizeRange("bad", "1y"), "1y");
  assert.equal(model.rangeLabel("1mo"), "1M");
  assert.equal(model.rangeLabel("bad"), "1D");
  assert.equal(model.rangeInterval("5d"), "15m");
  assert.equal(model.rangeInterval("1y"), "1wk");
});

test("stores selected chart ranges per symbol without mutating input", () => {
  const selections = { aapl: "5d", MSFT: "1mo", "bad/name": "1y" };
  assert.equal(model.selectedRange(selections, "aapl"), "5d");
  assert.equal(model.selectedRange(selections, "NVDA", "6mo"), "6mo");
  assert.equal(model.selectedRange("1y", "AAPL"), "1y");
  assert.equal(model.selectedRangeForSymbol(selections, "MSFT"), "1mo");
  const updated = model.withSelectedRange(selections, "nvda", "1y");
  assert.deepEqual(updated, { AAPL: "5d", MSFT: "1mo", NVDA: "1y" });
  assert.deepEqual(selections, { aapl: "5d", MSFT: "1mo", "bad/name": "1y" });
  assert.deepEqual(model.setSelectedRange({}, "AAPL", "bad"), { AAPL: "1d" });
});

test("adds symbols with validation, deduplication, and limits", () => {
  const input = ["AAPL", "MSFT"];
  const added = model.addSymbol(input, " nvda ");
  assert.deepEqual(added, {
    ok: true, changed: true, code: "added", message: "NVDA was added.",
    symbols: ["AAPL", "MSFT", "NVDA"], symbol: "NVDA", fromIndex: null, toIndex: 2
  });
  assert.deepEqual(input, ["AAPL", "MSFT"]);
  const duplicate = model.addSymbol(input, "aapl");
  assert.equal(duplicate.ok, true);
  assert.equal(duplicate.changed, false);
  assert.equal(duplicate.code, "already_present");
  assert.deepEqual(duplicate.symbols, input);
  assert.equal(model.addSymbol(input, "bad/name").code, "invalid_symbol");
  assert.equal(model.addSymbol(input, "NVDA", 2).code, "limit_reached");
});

test("removes symbols without mutating the source watchlist", () => {
  const input = ["AAPL", "MSFT", "NVDA"];
  const removed = model.removeSymbol(input, "msft");
  assert.equal(removed.ok, true);
  assert.equal(removed.changed, true);
  assert.equal(removed.code, "removed");
  assert.deepEqual(removed.symbols, ["AAPL", "NVDA"]);
  assert.deepEqual(input, ["AAPL", "MSFT", "NVDA"]);
  assert.equal(model.removeSymbol(input, "TSLA").code, "not_found");
  assert.equal(model.removeSymbol(input, "bad/name").code, "invalid_symbol");
  assert.deepEqual(model.removeSymbol(["AAPL"], "AAPL").symbols, []);
});

test("moves symbols by name or source index with bounded destinations", () => {
  const input = ["AAPL", "MSFT", "NVDA"];
  assert.deepEqual(model.moveSymbol(input, "NVDA", 0).symbols, ["NVDA", "AAPL", "MSFT"]);
  assert.deepEqual(model.moveSymbol(input, 0, 2).symbols, ["MSFT", "NVDA", "AAPL"]);
  assert.equal(model.moveSymbol(input, "MSFT", 1).code, "unchanged");
  assert.equal(model.moveSymbol(input, "TSLA", 0).code, "not_found");
  assert.equal(model.moveSymbol(input, "AAPL", -1).code, "invalid_position");
  assert.equal(model.moveSymbol(input, "AAPL", 1.5).code, "invalid_position");
  assert.deepEqual(model.moveSymbol(["0", "AAPL"], "0", 1).symbols, ["AAPL", "0"]);
  assert.deepEqual(input, ["AAPL", "MSFT", "NVDA"]);
});

test("formats prices with useful precision, grouping, and currency", () => {
  assert.equal(model.formatPrice(1234.567, "USD"), "$1,234.57");
  assert.equal(model.formatPrice(99, "GBP"), "£99.00");
  assert.equal(model.formatPrice(123.45, "GBp"), "123.45p");
  assert.equal(model.formatPrice(42, "CHF"), "42.00 CHF");
  assert.equal(model.formatPrice(0.123456), "0.1235");
  assert.equal(model.formatPrice(0.0012345), "0.001234");
  assert.equal(model.formatCurrency(8, "EUR"), "€8.00");
});

test("does not turn missing or malformed prices into zero", () => {
  [null, undefined, true, false, "", "   ", "12x", NaN, Infinity, {}, []]
    .forEach((value) => assert.equal(model.formatPrice(value, "USD"), "—"));
  assert.equal(model.formatPrice(0, "USD"), "$0.00");
  assert.equal(model.formatPrice("12.5", "USD"), "$12.50");
});

test("formats signed deltas without inventing signs for flat values", () => {
  assert.equal(model.formatDelta(1.25), "+1.25");
  assert.equal(model.formatDelta(-1.25), "−1.25");
  assert.equal(model.formatDelta(1.25, "USD"), "+$1.25");
  assert.equal(model.formatDelta(1.25, "", false), "1.25");
  assert.equal(model.formatDelta(0), "0.00");
  assert.equal(model.formatDelta(null), "—");
});

test("formats percentages with explicit movement", () => {
  assert.equal(model.formatPercent(1.236), "+1.24%");
  assert.equal(model.formatPercent(-1.236), "−1.24%");
  assert.equal(model.formatPercent(0), "0.00%");
  assert.equal(model.formatPercent(1.236, false), "1.24%");
  assert.equal(model.formatPercent(null), "—");
});

test("formats freshness from ISO, epoch seconds, milliseconds, and Date", () => {
  const now = Date.parse("2026-08-31T12:10:00Z");
  assert.equal(model.formatFreshness("2026-08-31T12:09:31Z", now), "Just now");
  assert.equal(model.formatFreshness("2026-08-31T12:09:00Z", now), "1 min ago");
  assert.equal(model.formatFreshness(now / 1000 - 120, now), "2 mins ago");
  assert.equal(model.formatFreshness(now - 3600 * 1000, now), "1 hour ago");
  assert.equal(model.formatFreshness(new Date(now - 2 * 86400 * 1000), now), "2 days ago");
});

test("reports unavailable freshness and safely clamps future clock skew", () => {
  const now = Date.parse("2026-08-31T12:10:00Z");
  assert.equal(model.formatFreshness(null, now), "Update time unavailable");
  assert.equal(model.formatFreshness("not-a-date", now), "Update time unavailable");
  assert.equal(model.formatFreshness(now + 5000, now), "Just now");
});

test("downsamples evenly while preserving endpoints", () => {
  const values = Array.from({ length: 100 }, (_, index) => index);
  assert.deepEqual(model.downsampleSparkline(values, 5), [0, 25, 50, 74, 99]);
  assert.deepEqual(model.downsampleSparkline(values, 2), [0, 99]);
  assert.deepEqual(model.downsampleSparkline(values, 1), [99]);
  assert.deepEqual(model.downsampleSparkline(values, 0), []);
});

test("downsampling filters invalid values without manufacturing zeroes", () => {
  assert.deepEqual(
    model.downsampleSparkline([null, undefined, false, "", NaN, 0, 1, 2], 10),
    [0, 1, 2]
  );
  assert.deepEqual(model.downsampleSparkline(null, 10), []);
});

test("computes selected-range performance from first to last finite point", () => {
  assert.deepEqual(model.rangePerformance([100, null, 105, 110]), {
    change: 10, percent: 10, direction: "up"
  });
  assert.deepEqual(model.rangePerformance([{ value: 20 }, { close: 15 }]), {
    change: -5, percent: -25, direction: "down"
  });
  assert.deepEqual(model.rangePerformance([[1, 4], [2, 4]]), {
    change: 0, percent: 0, direction: "flat"
  });
  assert.deepEqual(model.rangePerformance([0, 5]), {
    change: 5, percent: null, direction: "up"
  });
});

test("reports unavailable range performance without two finite observations", () => {
  const unavailable = { change: null, percent: null, direction: "unknown" };
  assert.deepEqual(model.rangePerformance(null), unavailable);
  assert.deepEqual(model.rangePerformance([]), unavailable);
  assert.deepEqual(model.rangePerformance([null, 5]), unavailable);
  assert.deepEqual(model.rangePerformance([false, "", NaN]), unavailable);
});

test("sanitizes a valid helper document to the stable quote schema", () => {
  const result = model.normalizeProviderResponse(documentWith([quote()]));
  assert.equal(result.ok, true);
  assert.equal(result.status, "ready");
  assert.equal(result.provider, "Fictional market fixture");
  assert.equal(result.generatedAt, "2026-08-31T12:01:00.000Z");
  assert.deepEqual(Object.keys(result.quotes[0]), [
    "symbol", "name", "currency", "regularMarketPrice", "previousClose",
    "change", "changePercent", "marketTime", "sparkline", "sparklineTimestamps",
    "range", "exchange", "exchangeTimezone", "instrumentType", "marketState",
    "sessionState", "regularMarketOpen", "dayLow", "dayHigh", "fiftyTwoWeekLow",
    "fiftyTwoWeekHigh", "volume", "cached", "cacheAgeSec", "stale"
  ]);
  assert.deepEqual(result.quotes[0], quote({
    marketTime: "2026-08-31T12:00:00.000Z",
    sparklineTimestamps: [],
    range: "1d",
    exchange: null,
    exchangeTimezone: null,
    instrumentType: null,
    marketState: null,
    sessionState: "unknown",
    regularMarketOpen: null,
    dayLow: null,
    dayHigh: null,
    fiftyTwoWeekLow: null,
    fiftyTwoWeekHigh: null,
    volume: null,
    cached: false,
    cacheAgeSec: null,
    stale: false
  }));
});

test("sanitization uppercases symbols and bounds provider-controlled text", () => {
  const result = model.normalizeProviderResponse(documentWith([
    quote({
      symbol: "acme",
      name: "  Acme\n\tHoldings  ",
      currency: "usd"
    })
  ], [], { provider: "  Demo\n provider  " }));
  assert.equal(result.provider, "Demo provider");
  assert.equal(result.quotes[0].symbol, "ACME");
  assert.equal(result.quotes[0].name, "Acme Holdings");
  assert.equal(result.quotes[0].currency, "USD");
});

test("sanitizes extended market metadata and cache state", () => {
  const result = model.normalizeProviderResponse(documentWith([
    quote({
      exchange: "  NasdaqGS\n ",
      exchangeTimezone: "America/New_York",
      instrumentType: "EQUITY",
      marketState: "regular",
      sessionState: "open",
      regularMarketOpen: 99,
      dayLow: 98,
      dayHigh: 104,
      fiftyTwoWeekLow: 60,
      fiftyTwoWeekHigh: 120,
      volume: 1234567,
      sparkline: [100, null, 101, 102],
      sparklineTimestamps: [1700000000, 1700000300, 1700000600, 1700000900],
      range: "5d",
      cached: "yes",
      cacheAgeSec: "47.9",
      stale: 1
    })
  ]));
  const normalized = result.quotes[0];
  assert.equal(normalized.exchange, "NasdaqGS");
  assert.equal(normalized.exchangeTimezone, "America/New_York");
  assert.equal(normalized.instrumentType, "EQUITY");
  assert.equal(normalized.marketState, "REGULAR");
  assert.equal(normalized.sessionState, "open");
  assert.equal(normalized.regularMarketOpen, 99);
  assert.equal(normalized.dayLow, 98);
  assert.equal(normalized.dayHigh, 104);
  assert.equal(normalized.fiftyTwoWeekLow, 60);
  assert.equal(normalized.fiftyTwoWeekHigh, 120);
  assert.equal(normalized.volume, 1234567);
  assert.deepEqual(normalized.sparkline, [100, 101, 102]);
  assert.deepEqual(normalized.sparklineTimestamps, [
    1700000000000,
    1700000600000,
    1700000900000
  ]);
  assert.equal(normalized.range, "5d");
  assert.equal(normalized.cached, true);
  assert.equal(normalized.cacheAgeSec, 47);
  assert.equal(normalized.stale, true);
});

test("reads extended Yahoo chart metadata and aligned history timestamps", () => {
  const result = model.normalizeProviderResponse({
    chart: {
      result: [{
        meta: {
          symbol: "BTC-USD",
          shortName: "Bitcoin USD",
          currency: "USD",
          regularMarketPrice: 65000,
          previousClose: 64000,
          exchangeName: "CCC",
          exchangeTimezoneName: "UTC",
          instrumentType: "CRYPTOCURRENCY",
          regularMarketDayLow: 63000,
          regularMarketDayHigh: 66000,
          fiftyTwoWeekLow: 30000,
          fiftyTwoWeekHigh: 70000,
          regularMarketVolume: 12300000000,
          regularMarketTime: 1700000900
        },
        timestamp: [1700000000, 1700000300, 1700000600],
        indicators: {
          quote: [{ close: [64000, null, 65000], open: [63900, null, 64500] }]
        }
      }],
      error: null
    }
  });
  const normalized = result.quotes[0];
  assert.equal(normalized.exchange, "CCC");
  assert.equal(normalized.exchangeTimezone, "UTC");
  assert.equal(normalized.sessionState, "continuous");
  assert.equal(normalized.regularMarketOpen, 63900);
  assert.equal(normalized.dayLow, 63000);
  assert.equal(normalized.dayHigh, 66000);
  assert.equal(normalized.fiftyTwoWeekLow, 30000);
  assert.equal(normalized.fiftyTwoWeekHigh, 70000);
  assert.equal(normalized.volume, 12300000000);
  assert.deepEqual(normalized.sparkline, [64000, 65000]);
  assert.deepEqual(normalized.sparklineTimestamps, [
    1700000000000, 1700000600000
  ]);
});

test("accepts legacy quote aliases while producing the stable schema", () => {
  const result = model.normalizeProviderResponse(documentWith([{
    symbol: "ACME",
    name: "Acme",
    currency: "USD",
    price: 12,
    prevClose: 10,
    changePct: 20,
    series: [{ t: 1700000000, c: 10 }, { t: 1700000600, c: 12 }]
  }]));
  assert.equal(result.quotes[0].regularMarketPrice, 12);
  assert.equal(result.quotes[0].previousClose, 10);
  assert.equal(result.quotes[0].change, 2);
  assert.equal(result.quotes[0].changePercent, 20);
  assert.deepEqual(result.quotes[0].sparkline, [10, 12]);
  assert.deepEqual(result.quotes[0].sparklineTimestamps, [
    1700000000000, 1700000600000
  ]);
});

test("derives change only from real price and previous-close inputs", () => {
  const result = model.normalizeProviderResponse(documentWith([
    quote({ regularMarketPrice: 105, previousClose: 100, change: null, changePercent: null }),
    quote({ symbol: "ZERO", regularMarketPrice: 0, previousClose: 0,
      change: null, changePercent: null, sparkline: [0] })
  ]));
  assert.equal(result.quotes[0].change, 5);
  assert.equal(result.quotes[0].changePercent, 5);
  assert.equal(result.quotes[1].regularMarketPrice, 0);
  assert.equal(result.quotes[1].change, 0);
  assert.equal(result.quotes[1].changePercent, null);
});

test("rejects a provider document containing only price-less quotes", () => {
  const result = model.normalizeProviderResponse(documentWith([
    quote({ symbol: "NONE", regularMarketPrice: null, previousClose: null,
      change: null, changePercent: null, sparkline: [] })
  ]));
  assert.equal(result.ok, false);
  assert.equal(result.status, "failed");
  assert.deepEqual(result.quotes, []);
  assert.match(result.error, /usable prices/);
});

test("uses the last finite sparkline value only when price is absent", () => {
  const result = model.normalizeProviderResponse(documentWith([
    quote({ regularMarketPrice: null, previousClose: null, change: null,
      changePercent: null, sparkline: [null, "", 10, false, 11] })
  ]));
  assert.equal(result.quotes[0].regularMarketPrice, 11);
  assert.deepEqual(result.quotes[0].sparkline, [10, 11]);
  assert.equal(result.quotes[0].change, null);
});

test("caps and downsamples provider sparklines", () => {
  const values = Array.from({ length: 100 }, (_, index) => index);
  const result = model.normalizeProviderResponse(documentWith([
    quote({ sparkline: values })
  ]), null, 5);
  assert.deepEqual(result.quotes[0].sparkline, [0, 25, 50, 74, 99]);
});

test("filters and orders quotes by an optional normalized request list", () => {
  const result = model.normalizeProviderResponse(documentWith([
    quote({ symbol: "MSFT" }),
    quote({ symbol: "AAPL" }),
    quote({ symbol: "NVDA" }),
    quote({ symbol: "AAPL", regularMarketPrice: 999 })
  ]), "aapl,msft");
  assert.deepEqual(result.quotes.map((item) => item.symbol), ["AAPL", "MSFT"]);
  assert.equal(result.quotes[0].regularMarketPrice, 102);
});

test("an unmatched optional filter does not misclassify valid prices", () => {
  const result = model.normalizeProviderResponse(
    documentWith([quote({ symbol: "AAPL" })]),
    "MSFT"
  );
  assert.equal(result.ok, true);
  assert.equal(result.status, "empty");
  assert.deepEqual(result.quotes, []);
});

test("sanitizes partial errors and recomputes status from usable content", () => {
  const result = model.normalizeProviderResponse(documentWith([quote()], [
    { symbol: "msft", code: "HTTP Error!", message: "  Provider\nfailed  " },
    { symbol: "bad/name", code: "", message: "" }
  ], { status: "ready" }));
  assert.equal(result.status, "partial");
  assert.deepEqual(result.errors[0], {
    symbol: "MSFT", code: "http_error", message: "Provider failed"
  });
  assert.deepEqual(result.errors[1], {
    symbol: null, code: "unknown_error", message: "Quote unavailable."
  });
});

test("returns a safe failure envelope for malformed provider documents", () => {
  [null, "", "not-json", [], {}, { schemaVersion: 2, quotes: [], errors: [] },
    { schemaVersion: 1, quotes: {} }, { schemaVersion: 1, quotes: [], errors: {} }]
    .forEach((value) => {
      const result = model.normalizeProviderResponse(value);
      assert.equal(result.ok, false);
      assert.equal(result.status, "failed");
      assert.deepEqual(result.quotes, []);
      assert.deepEqual(result.errors, []);
      assert.ok(result.error.length > 0);
    });
});

test("normalizes a raw Yahoo chart payload defensively", () => {
  const result = model.normalizeProviderResponse({
    chart: {
      result: [{
        meta: {
          symbol: "AAPL",
          shortName: "Apple Inc.",
          currency: "USD",
          regularMarketPrice: 102,
          chartPreviousClose: 100,
          regularMarketTime: 1700000000
        },
        indicators: { quote: [{ close: [100, null, 101, 102] }] }
      }],
      error: null
    }
  });
  assert.equal(result.ok, true);
  assert.equal(result.quotes[0].symbol, "AAPL");
  assert.deepEqual(result.quotes[0].sparkline, [100, 101, 102]);
  assert.equal(result.quotes[0].change, 2);
  assert.equal(result.quotes[0].marketTime, "2023-11-14T22:13:20.000Z");
});

test("findQuote is case-insensitive and accepts arrays or envelopes", () => {
  const quotes = [quote({ symbol: "AAPL" }), null, quote({ symbol: "MSFT" })];
  assert.equal(model.findQuote(quotes, " aapl ").symbol, "AAPL");
  assert.equal(model.findQuote({ quotes }, "msft").symbol, "MSFT");
  assert.equal(model.findQuote(quotes, "NVDA"), null);
  assert.equal(model.findQuote(null, "AAPL"), null);
  assert.equal(model.findQuote(quotes, "bad/name"), null);
});

test("maps numeric and quote changes to stable directions", () => {
  assert.equal(model.changeDirection(1), "up");
  assert.equal(model.changeDirection(-1), "down");
  assert.equal(model.changeDirection(0), "flat");
  assert.equal(model.changeDirection(null), "unknown");
  assert.equal(model.changeDirection({ change: null, changePercent: 0.1 }), "up");
  assert.equal(model.changeDirection({ change: -0.1, changePercent: 5 }), "down");
  assert.equal(model.directionForChange({ change: 0 }), "flat");
});

test("builds movement labels that do not rely on color or sign glyphs", () => {
  assert.equal(
    model.changeAccessibilityLabel({ change: 2, changePercent: 1.25, currency: "USD" }),
    "Up by $2.00, 1.25 percent"
  );
  assert.equal(
    model.changeAccessibilityLabel({ change: -2, changePercent: -1.25, currency: "GBP" }),
    "Down by £2.00, 1.25 percent"
  );
  assert.equal(model.changeAccessibilityLabel({ change: 0 }), "Unchanged");
  assert.equal(model.changeAccessibilityLabel({ change: null, changePercent: null }), "Change unavailable");
});

test("builds a complete quote accessibility summary when data exists", () => {
  assert.equal(
    model.quoteAccessibilityLabel(quote(), Date.parse("2026-08-31T12:02:00Z")),
    "Acme Incorporated, $102.00, Up by $2.00, 2.00 percent, Updated 2 mins ago"
  );
  assert.equal(model.quoteAccessibilityLabel(null), "Quote unavailable");
});

test("formats volume and the four stable detail-stat rows", () => {
  assert.equal(model.formatVolume(null), "—");
  assert.equal(model.formatVolume(-1), "—");
  assert.equal(model.formatVolume(0), "0");
  assert.equal(model.formatVolume(999), "999");
  assert.equal(model.formatVolume(1234), "1.2K");
  assert.equal(model.formatVolume(1234567), "1.2M");
  assert.equal(model.formatVolume(1234567890), "1.23B");
  assert.equal(model.formatVolume(1234567890123), "1.23T");
  assert.deepEqual(model.statRows({
    currency: "GBP",
    regularMarketOpen: 10,
    dayLow: 9,
    dayHigh: 12,
    fiftyTwoWeekLow: 5,
    fiftyTwoWeekHigh: 15,
    volume: 1234567
  }), [
    { id: "open", label: "Open", value: "£10.00" },
    { id: "day-range", label: "Day range", value: "£9.00 – £12.00" },
    { id: "52-week-range", label: "52-week range", value: "£5.00 – £15.00" },
    { id: "volume", label: "Volume", value: "1.2M" }
  ]);
  assert.ok(model.statRows(null).every((row) => row.value === "—"));
});

test("labels market sessions without relying on provider-specific tokens", () => {
  assert.equal(model.marketStateLabel("REGULAR"), "Market open");
  assert.equal(model.marketStateLabel("PRE_MARKET"), "Pre-market");
  assert.equal(model.marketStateLabel("POST"), "After hours");
  assert.equal(model.marketStateLabel("CLOSED"), "Market closed");
  assert.equal(model.marketStateLabel("24/7"), "Open 24 hours");
  assert.equal(model.marketStateLabel("HALTED"), "Trading halted");
  assert.equal(model.marketStateLabel({ instrumentType: "CRYPTOCURRENCY" }), "Open 24 hours");
  assert.equal(model.marketStateLabel(null), "Market status unavailable");
});

test("builds cache- and stale-aware as-of labels", () => {
  const now = Date.parse("2026-08-31T12:10:00Z");
  assert.equal(model.asOfLabel("2026-08-31T12:08:00Z", now), "As of 2 mins ago");
  assert.equal(model.asOfLabel({
    marketTime: "2026-08-31T12:08:00Z", cached: true
  }, now), "Cached as of 2 mins ago");
  assert.equal(model.asOfLabel({
    marketTime: "2026-08-31T12:08:00Z", cached: true, stale: true
  }, now), "Stale as of 2 mins ago");
  assert.equal(model.asOfLabel({ marketTime: null }, now), "As of unavailable");
  assert.equal(model.asOfLabel({
    marketTime: null, updatedAt: "2026-08-31T12:09:00Z"
  }, now), "As of 1 min ago");
});

test("recommends configured refresh while any market is open or continuous", () => {
  assert.equal(model.recommendedRefreshInterval([
    { sessionState: "closed" }, { sessionState: "open" }
  ], 300), 300);
  assert.equal(model.recommendedRefreshInterval([
    { instrumentType: "CRYPTOCURRENCY" }, { sessionState: "closed" }
  ], 120), 120);
  assert.equal(model.recommendedRefreshInterval({
    quotes: [{ marketState: "REGULAR" }]
  }, 450), 450);
});

test("backs off refreshes for pre/post and wholly closed watchlists", () => {
  assert.equal(model.recommendedRefreshInterval([
    { sessionState: "pre" }, { sessionState: "post" }
  ], 300), 900);
  assert.equal(model.recommendedRefreshInterval([
    { sessionState: "closed" }, { marketState: "HALTED" }
  ], 300), 3600);
  assert.equal(model.recommendedRefreshInterval([
    { sessionState: "closed" }
  ], 7200), 7200);
});

test("keeps the configured refresh for unknown state and safe fallback input", () => {
  assert.equal(model.recommendedRefreshInterval([
    { sessionState: "closed" }, {}
  ], 300), 300);
  assert.equal(model.recommendedRefreshInterval([], 75), 75);
  assert.equal(model.recommendedRefreshInterval(null, 120), 120);
  assert.equal(model.recommendedRefreshInterval([{}], "bad"), 900);
});

test("strengthens quote accessibility for session, venue, and stale data", () => {
  const accessibleQuote = quote({
    exchange: "NasdaqGS",
    sessionState: "post",
    cached: true,
    stale: true
  });
  assert.equal(
    model.quoteAccessibilityLabel(accessibleQuote, Date.parse("2026-08-31T12:02:00Z")),
    "Acme Incorporated, $102.00, Up by $2.00, 2.00 percent, Exchange NasdaqGS, " +
      "After hours, Stale quote, Updated 2 mins ago"
  );
});

if (failures.length > 0) {
  for (const failure of failures) {
    process.stderr.write(`not ok - ${failure.name}\n${failure.error.stack}\n`);
  }
  process.stderr.write(`${passed} passed; ${failures.length} failed\n`);
  process.exit(1);
}

process.stdout.write(`${passed} MarketModel tests passed.\n`);
