.pragma library

// Pure data handling shared by the service and the visual surfaces. Keep this
// file free of Qt objects so it can also be exercised by the portable tests.

var MAX_SYMBOLS = 12;
var MAX_SYMBOL_LENGTH = 32;
var DEFAULT_SPARKLINE_POINTS = 78;
var MAX_SPARKLINE_POINTS = 240;
var MISSING_VALUE = "\u2014";
var MINUS_SIGN = "\u2212";

// Presets are deliberately small enough to remain useful in both bar modes.
// Keep the source private: every public accessor below returns fresh objects
// and arrays so QML callers cannot mutate the catalog for another surface.
var BUILT_IN_PROFILES = [
  {
    id: "markets",
    name: "Markets",
    description: "Major equity indices across the US, Europe and Asia.",
    primarySymbol: "^GSPC",
    symbols: ["^GSPC", "^IXIC", "^DJI", "^RUT", "^VIX", "^FTSE", "^GDAXI", "^N225", "^HSI"]
  },
  {
    id: "mag7",
    name: "Magnificent 7",
    description: "The seven US mega-cap technology leaders.",
    primarySymbol: "NVDA",
    symbols: ["NVDA", "MSFT", "AAPL", "GOOGL", "AMZN", "META", "TSLA"]
  },
  {
    id: "crypto",
    name: "Crypto",
    description: "A broad view of leading cryptocurrency markets.",
    primarySymbol: "BTC-USD",
    symbols: ["BTC-USD", "ETH-USD", "SOL-USD", "XRP-USD", "BNB-USD", "ADA-USD", "LINK-USD", "AVAX-USD"]
  },
  {
    id: "meme-coins",
    name: "Meme Coins",
    description: "Speculative, high-volatility community-led crypto assets.",
    primarySymbol: "DOGE-USD",
    symbols: ["DOGE-USD", "SHIB-USD", "PEPE24478-USD", "BONK-USD", "FLOKI-USD", "WIF-USD"]
  },
  {
    id: "semiconductors",
    name: "AI & Semiconductors",
    description: "AI chip designers, foundries and equipment leaders.",
    primarySymbol: "NVDA",
    symbols: ["NVDA", "AVGO", "AMD", "TSM", "ASML", "ARM", "MU", "MRVL"]
  },
  {
    id: "uk",
    name: "UK Markets",
    description: "UK indices, sterling and leading London-listed companies.",
    primarySymbol: "^FTSE",
    symbols: ["^FTSE", "^FTMC", "^FTAS", "GBPUSD=X", "AZN.L", "HSBA.L", "SHEL.L", "RR.L"]
  }
];

var RANGE_DEFINITIONS = [
  { id: "1d", label: "1D", interval: "5m" },
  { id: "5d", label: "5D", interval: "15m" },
  { id: "1mo", label: "1M", interval: "1d" },
  { id: "6mo", label: "6M", interval: "1d" },
  { id: "1y", label: "1Y", interval: "1wk" }
];

function isArray(value) {
  return Object.prototype.toString.call(value) === "[object Array]";
}

function hasOwn(object, key) {
  return object !== null && object !== undefined &&
    Object.prototype.hasOwnProperty.call(object, key);
}

function trimmed(value) {
  if (typeof value !== "string") return "";
  return value.replace(/^\s+|\s+$/g, "");
}

function finiteNumber(value) {
  var text;
  var number;

  if (typeof value === "number") {
    return isFinite(value) ? value : null;
  }

  if (typeof value !== "string") return null;
  text = trimmed(value);
  if (text === "") return null;
  if (!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(text)) {
    return null;
  }
  number = Number(text);
  return isFinite(number) ? number : null;
}

function boundedInteger(value, fallback, minimum, maximum) {
  var number = finiteNumber(value);
  if (number === null) return fallback;
  number = Math.floor(number);
  if (number < minimum) return minimum;
  if (number > maximum) return maximum;
  return number;
}

function safeText(value, maximumLength) {
  var text;
  if (typeof value !== "string") return "";
  text = trimmed(value)
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ");
  if (text.length > maximumLength) text = text.substring(0, maximumLength);
  return text;
}

function normalizeSymbol(value) {
  var symbol;
  if (typeof value !== "string") return null;
  symbol = trimmed(value).toUpperCase();
  if (symbol.length === 0 || symbol.length > MAX_SYMBOL_LENGTH) return null;
  if (!/^[A-Z0-9.^=_+\-]+$/.test(symbol)) return null;
  if (!/[A-Z0-9]/.test(symbol)) return null;
  return symbol;
}

function normalizeSymbols(value, requestedLimit) {
  var raw;
  var limit = boundedInteger(requestedLimit, MAX_SYMBOLS, 0, MAX_SYMBOLS);
  var result = [];
  var seen = {};
  var index;
  var symbol;
  var key;

  if (typeof value === "string") {
    raw = value.split(",");
  } else if (isArray(value)) {
    raw = value;
  } else {
    return result;
  }

  for (index = 0; index < raw.length && result.length < limit; index += 1) {
    symbol = normalizeSymbol(raw[index]);
    if (symbol === null) continue;
    key = "$" + symbol;
    if (hasOwn(seen, key)) continue;
    seen[key] = true;
    result.push(symbol);
  }
  return result;
}

function cloneProfile(profile) {
  if (profile === null || profile === undefined) return null;
  return {
    id: profile.id,
    name: profile.name,
    description: profile.description,
    primarySymbol: profile.primarySymbol,
    symbols: profile.symbols.slice(0)
  };
}

function profileIndexById(value) {
  var id;
  var index;
  if (typeof value !== "string") return -1;
  id = trimmed(value).toLowerCase();
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(id)) return -1;
  for (index = 0; index < BUILT_IN_PROFILES.length; index += 1) {
    if (BUILT_IN_PROFILES[index].id === id) return index;
  }
  return -1;
}

function normalizeProfileId(value, fallback) {
  var index = profileIndexById(value);
  var fallbackIndex;
  if (index >= 0) return BUILT_IN_PROFILES[index].id;
  fallbackIndex = profileIndexById(fallback);
  return fallbackIndex >= 0 ? BUILT_IN_PROFILES[fallbackIndex].id : null;
}

function profiles() {
  var result = [];
  var index;
  for (index = 0; index < BUILT_IN_PROFILES.length; index += 1) {
    result.push(cloneProfile(BUILT_IN_PROFILES[index]));
  }
  return result;
}

function profileById(value) {
  var index = profileIndexById(value);
  return index < 0 ? null : cloneProfile(BUILT_IN_PROFILES[index]);
}

function symbolsForProfile(value) {
  var profile = profileById(value);
  return profile === null ? [] : profile.symbols;
}

function sameSymbolSet(left, right) {
  var seen = {};
  var index;
  if (left.length !== right.length) return false;
  for (index = 0; index < left.length; index += 1) {
    seen["$" + left[index]] = true;
  }
  for (index = 0; index < right.length; index += 1) {
    if (!hasOwn(seen, "$" + right[index])) return false;
  }
  return true;
}

function profileForSymbols(value) {
  var symbols = normalizeSymbols(value);
  var index;
  for (index = 0; index < BUILT_IN_PROFILES.length; index += 1) {
    if (sameSymbolSet(symbols, BUILT_IN_PROFILES[index].symbols)) {
      return cloneProfile(BUILT_IN_PROFILES[index]);
    }
  }
  return null;
}

function symbolMutationResult(ok, changed, code, message, symbols, symbol, fromIndex, toIndex) {
  return {
    ok: ok,
    changed: changed,
    code: code,
    message: message,
    symbols: symbols.slice(0),
    symbol: symbol,
    fromIndex: fromIndex === undefined ? null : fromIndex,
    toIndex: toIndex === undefined ? null : toIndex
  };
}

function addSymbol(value, candidate, requestedLimit) {
  var symbols = normalizeSymbols(value);
  var symbol = normalizeSymbol(candidate);
  var limit = boundedInteger(requestedLimit, MAX_SYMBOLS, 1, MAX_SYMBOLS);
  var index;
  if (symbol === null) {
    return symbolMutationResult(false, false, "invalid_symbol",
      "Enter a valid market symbol.", symbols, null);
  }
  for (index = 0; index < symbols.length; index += 1) {
    if (symbols[index] === symbol) {
      return symbolMutationResult(true, false, "already_present",
        symbol + " is already in this watchlist.", symbols, symbol, index, index);
    }
  }
  if (symbols.length >= limit) {
    return symbolMutationResult(false, false, "limit_reached",
      "A watchlist can contain up to " + limit + " symbols.", symbols, symbol);
  }
  symbols.push(symbol);
  return symbolMutationResult(true, true, "added",
    symbol + " was added.", symbols, symbol, null, symbols.length - 1);
}

function removeSymbol(value, candidate) {
  var symbols = normalizeSymbols(value);
  var symbol = normalizeSymbol(candidate);
  var index;
  if (symbol === null) {
    return symbolMutationResult(false, false, "invalid_symbol",
      "Choose a valid symbol to remove.", symbols, null);
  }
  for (index = 0; index < symbols.length; index += 1) {
    if (symbols[index] === symbol) {
      symbols.splice(index, 1);
      return symbolMutationResult(true, true, "removed",
        symbol + " was removed.", symbols, symbol, index, null);
    }
  }
  return symbolMutationResult(false, false, "not_found",
    symbol + " is not in this watchlist.", symbols, symbol);
}

function listIndex(value, symbols) {
  var symbol;
  var index;
  if (typeof value === "number" && isFinite(value) && Math.floor(value) === value) return value;
  symbol = normalizeSymbol(value);
  if (symbol === null) return -1;
  for (index = 0; index < symbols.length; index += 1) {
    if (symbols[index] === symbol) return index;
  }
  return -1;
}

function moveSymbol(value, symbolOrIndex, destinationIndex) {
  var symbols = normalizeSymbols(value);
  var fromIndex = listIndex(symbolOrIndex, symbols);
  var toNumber = finiteNumber(destinationIndex);
  var toIndex;
  var symbol;
  if (fromIndex < 0 || fromIndex >= symbols.length) {
    return symbolMutationResult(false, false, "not_found",
      "Choose a symbol in this watchlist.", symbols, null);
  }
  symbol = symbols[fromIndex];
  if (toNumber === null || Math.floor(toNumber) !== toNumber) {
    return symbolMutationResult(false, false, "invalid_position",
      "Choose a valid watchlist position.", symbols, symbol, fromIndex);
  }
  toIndex = toNumber;
  if (toIndex < 0 || toIndex >= symbols.length) {
    return symbolMutationResult(false, false, "invalid_position",
      "Choose a position between 1 and " + symbols.length + ".",
      symbols, symbol, fromIndex, toIndex);
  }
  if (fromIndex === toIndex) {
    return symbolMutationResult(true, false, "unchanged",
      symbol + " is already in that position.", symbols, symbol, fromIndex, toIndex);
  }
  symbols.splice(fromIndex, 1);
  symbols.splice(toIndex, 0, symbol);
  return symbolMutationResult(true, true, "moved",
    symbol + " was moved.", symbols, symbol, fromIndex, toIndex);
}

function normalizeBarMode(value, fallback) {
  var mode = typeof value === "string" ? trimmed(value).toLowerCase() : "";
  var fallbackMode = typeof fallback === "string" ? trimmed(fallback).toLowerCase() : "";
  if (mode === "single" || mode === "ticker") return mode;
  if (fallbackMode === "single" || fallbackMode === "ticker") return fallbackMode;
  return "single";
}

function rangeIndex(value) {
  var normalized;
  var index;
  if (typeof value !== "string") return -1;
  normalized = trimmed(value).toLowerCase();
  if (normalized === "1day") normalized = "1d";
  else if (normalized === "5day" || normalized === "5days") normalized = "5d";
  else if (normalized === "1month") normalized = "1mo";
  else if (normalized === "6month" || normalized === "6months") normalized = "6mo";
  else if (normalized === "1year") normalized = "1y";
  for (index = 0; index < RANGE_DEFINITIONS.length; index += 1) {
    if (RANGE_DEFINITIONS[index].id === normalized) return index;
  }
  return -1;
}

function normalizeRange(value, fallback) {
  var index = rangeIndex(value);
  var fallbackIndex;
  if (index >= 0) return RANGE_DEFINITIONS[index].id;
  fallbackIndex = rangeIndex(fallback);
  if (fallbackIndex >= 0) return RANGE_DEFINITIONS[fallbackIndex].id;
  return "1d";
}

function rangeOptions() {
  var result = [];
  var index;
  for (index = 0; index < RANGE_DEFINITIONS.length; index += 1) {
    result.push({
      id: RANGE_DEFINITIONS[index].id,
      label: RANGE_DEFINITIONS[index].label,
      interval: RANGE_DEFINITIONS[index].interval
    });
  }
  return result;
}

function rangeLabel(value) {
  return RANGE_DEFINITIONS[rangeIndex(normalizeRange(value))].label;
}

function rangeInterval(value) {
  return RANGE_DEFINITIONS[rangeIndex(normalizeRange(value))].interval;
}

function selectedRange(selections, symbol, fallback) {
  var normalizedSymbol = normalizeSymbol(symbol);
  var key;
  if (typeof selections === "string") return normalizeRange(selections, fallback);
  if (normalizedSymbol !== null && selections !== null && typeof selections === "object" &&
      !isArray(selections) && hasOwn(selections, normalizedSymbol)) {
    return normalizeRange(selections[normalizedSymbol], fallback);
  }
  if (normalizedSymbol !== null && selections !== null && typeof selections === "object" &&
      !isArray(selections)) {
    for (key in selections) {
      if (hasOwn(selections, key) && normalizeSymbol(key) === normalizedSymbol) {
        return normalizeRange(selections[key], fallback);
      }
    }
  }
  return normalizeRange(fallback);
}

function withSelectedRange(selections, symbol, range) {
  var normalizedSymbol = normalizeSymbol(symbol);
  var normalizedRange = normalizeRange(range);
  var result = {};
  var key;
  var copied = 0;
  if (selections !== null && typeof selections === "object" && !isArray(selections)) {
    for (key in selections) {
      if (!hasOwn(selections, key) || normalizeSymbol(key) === null || copied >= MAX_SYMBOLS) continue;
      if (!hasOwn(result, normalizeSymbol(key))) copied += 1;
      result[normalizeSymbol(key)] = normalizeRange(selections[key]);
    }
  }
  if (normalizedSymbol !== null &&
      (hasOwn(result, normalizedSymbol) || copied < MAX_SYMBOLS)) {
    result[normalizedSymbol] = normalizedRange;
  }
  return result;
}

function selectedRangeForSymbol(selections, symbol, fallback) {
  return selectedRange(selections, symbol, fallback);
}

function setSelectedRange(selections, symbol, range) {
  return withSelectedRange(selections, symbol, range);
}

function normalizeCurrency(value) {
  var currency = safeText(value, 8);
  var upper;
  if (currency === "") return "";
  upper = currency.toUpperCase();
  // Yahoo uses the case-sensitive pseudo-code GBp for prices in pence. GBX is
  // another commonly encountered spelling for the same unit.
  if (currency === "GBp" || upper === "GBX") return "GBp";
  if (!/^[A-Z]{3,5}$/.test(upper)) return "";
  return upper;
}

function currencyParts(currency) {
  var code = normalizeCurrency(currency);
  var parts = { prefix: "", suffix: "", code: code };

  if (code === "USD") parts.prefix = "$";
  else if (code === "GBP") parts.prefix = "\u00a3";
  else if (code === "EUR") parts.prefix = "\u20ac";
  else if (code === "JPY" || code === "CNY") parts.prefix = "\u00a5";
  else if (code === "CAD") parts.prefix = "CA$";
  else if (code === "AUD") parts.prefix = "A$";
  else if (code === "NZD") parts.prefix = "NZ$";
  else if (code === "HKD") parts.prefix = "HK$";
  else if (code === "SGD") parts.prefix = "S$";
  else if (code === "INR") parts.prefix = "\u20b9";
  else if (code === "KRW") parts.prefix = "\u20a9";
  else if (code === "BTC") parts.prefix = "\u20bf";
  else if (code === "GBp") parts.suffix = "p";
  else if (code !== "") parts.suffix = " " + code;

  return parts;
}

function decimalPlacesForPrice(value) {
  var magnitude = Math.abs(value);
  if (magnitude === 0 || magnitude >= 1) return 2;
  if (magnitude >= 0.01) return 4;
  return 6;
}

function groupedFixed(value, decimalPlaces) {
  var fixed = value.toFixed(decimalPlaces);
  var pieces = fixed.split(".");
  var whole = pieces[0];
  var grouped = "";
  var cursor;
  var count = 0;

  for (cursor = whole.length - 1; cursor >= 0; cursor -= 1) {
    if (count > 0 && count % 3 === 0) grouped = "," + grouped;
    grouped = whole.charAt(cursor) + grouped;
    count += 1;
  }
  return pieces.length === 2 ? grouped + "." + pieces[1] : grouped;
}

function formatMagnitude(value, currency, decimalPlaces) {
  var parts = currencyParts(currency);
  return parts.prefix + groupedFixed(Math.abs(value), decimalPlaces) + parts.suffix;
}

function formatPrice(value, currency) {
  var number = finiteNumber(value);
  var sign;
  if (number === null) return MISSING_VALUE;
  sign = number < 0 ? MINUS_SIGN : "";
  return sign + formatMagnitude(number, currency, decimalPlacesForPrice(number));
}

function formatCurrency(value, currency) {
  return formatPrice(value, currency);
}

function formatDelta(value, currency, showPositiveSign) {
  var number = finiteNumber(value);
  var sign = "";
  if (number === null) return MISSING_VALUE;
  if (number < 0) sign = MINUS_SIGN;
  else if (number > 0 && showPositiveSign !== false) sign = "+";
  return sign + formatMagnitude(number, currency, decimalPlacesForPrice(number));
}

function formatPercent(value, showPositiveSign) {
  var number = finiteNumber(value);
  var sign = "";
  if (number === null) return MISSING_VALUE;
  if (number < 0) sign = MINUS_SIGN;
  else if (number > 0 && showPositiveSign !== false) sign = "+";
  return sign + groupedFixed(Math.abs(number), 2) + "%";
}

function timestampMilliseconds(value) {
  var number;
  var parsed;
  var tag = Object.prototype.toString.call(value);

  if (tag === "[object Date]") {
    number = value.getTime();
    return isFinite(number) && number > 0 ? number : null;
  }

  number = finiteNumber(value);
  if (number !== null) {
    if (number <= 0) return null;
    // Unix seconds remain below this threshold for millennia; browser and Qt
    // timestamps are normally milliseconds.
    if (number < 100000000000) number *= 1000;
    return isFinite(number) ? Math.floor(number) : null;
  }

  if (typeof value !== "string" || trimmed(value) === "") return null;
  parsed = Date.parse(value);
  return isFinite(parsed) && parsed > 0 ? parsed : null;
}

function formatFreshness(value, nowValue) {
  var timestamp = timestampMilliseconds(value);
  var now = timestampMilliseconds(nowValue);
  var seconds;
  var count;

  if (timestamp === null) return "Update time unavailable";
  if (now === null) now = new Date().getTime();
  seconds = Math.max(0, Math.floor((now - timestamp) / 1000));

  if (seconds < 60) return "Just now";
  if (seconds < 3600) {
    count = Math.floor(seconds / 60);
    return count + (count === 1 ? " min ago" : " mins ago");
  }
  if (seconds < 86400) {
    count = Math.floor(seconds / 3600);
    return count + (count === 1 ? " hour ago" : " hours ago");
  }
  count = Math.floor(seconds / 86400);
  return count + (count === 1 ? " day ago" : " days ago");
}

function formatVolume(value) {
  var number = finiteNumber(value);
  var magnitude;
  if (number === null || number < 0) return MISSING_VALUE;
  magnitude = Math.abs(number);
  if (magnitude >= 1000000000000) return groupedFixed(number / 1000000000000, 2) + "T";
  if (magnitude >= 1000000000) return groupedFixed(number / 1000000000, 2) + "B";
  if (magnitude >= 1000000) return groupedFixed(number / 1000000, 1) + "M";
  if (magnitude >= 1000) return groupedFixed(number / 1000, 1) + "K";
  return groupedFixed(Math.round(number), 0);
}

function marketStateLabel(value) {
  var state;
  if (value !== null && typeof value === "object") {
    state = inferredSessionState(value.marketState, value.sessionState, value.instrumentType);
  } else {
    state = normalizedStateToken(value);
  }
  if (state === "open") return "Market open";
  if (state === "pre") return "Pre-market";
  if (state === "post") return "After hours";
  if (state === "closed") return "Market closed";
  if (state === "continuous") return "Open 24 hours";
  if (state === "halted") return "Trading halted";
  return "Market status unavailable";
}

function asOfLabel(value, nowValue) {
  var timestamp = value;
  var prefix = "As of ";
  var freshness;
  if (value !== null && typeof value === "object") {
    timestamp = timestampMilliseconds(value.marketTime) !== null
      ? value.marketTime : value.updatedAt;
    if (value.stale === true) prefix = "Stale as of ";
    else if (value.cached === true) prefix = "Cached as of ";
  }
  freshness = formatFreshness(timestamp, nowValue);
  if (freshness === "Update time unavailable") return "As of unavailable";
  return prefix + freshness.toLowerCase();
}

function formattedRange(low, high, currency) {
  var normalizedLow = finiteNumber(low);
  var normalizedHigh = finiteNumber(high);
  if (normalizedLow === null || normalizedHigh === null) return MISSING_VALUE;
  return formatPrice(normalizedLow, currency) + " – " + formatPrice(normalizedHigh, currency);
}

function statRows(quote) {
  var value = quote !== null && typeof quote === "object" ? quote : {};
  var currency = value.currency;
  return [
    {
      id: "open",
      label: "Open",
      value: formatPrice(value.regularMarketOpen, currency)
    },
    {
      id: "day-range",
      label: "Day range",
      value: formattedRange(value.dayLow, value.dayHigh, currency)
    },
    {
      id: "52-week-range",
      label: "52-week range",
      value: formattedRange(value.fiftyTwoWeekLow, value.fiftyTwoWeekHigh, currency)
    },
    {
      id: "volume",
      label: "Volume",
      value: formatVolume(value.volume)
    }
  ];
}

function sparklineValue(point) {
  var value;
  if (finiteNumber(point) !== null) return finiteNumber(point);
  if (isArray(point)) {
    if (point.length < 2) return null;
    return finiteNumber(point[1]);
  }
  if (point === null || typeof point !== "object") return null;
  if (hasOwn(point, "value")) value = finiteNumber(point.value);
  else if (hasOwn(point, "close")) value = finiteNumber(point.close);
  else if (hasOwn(point, "c")) value = finiteNumber(point.c);
  else if (hasOwn(point, "price")) value = finiteNumber(point.price);
  else if (hasOwn(point, "y")) value = finiteNumber(point.y);
  else value = null;
  return value;
}

function downsampleSparkline(points, requestedMaximum) {
  var maximum = boundedInteger(
    requestedMaximum,
    DEFAULT_SPARKLINE_POINTS,
    0,
    MAX_SPARKLINE_POINTS
  );
  var valid = [];
  var result = [];
  var index;
  var selectedIndex;
  var previousIndex = -1;

  if (!isArray(points) || maximum === 0) return result;
  for (index = 0; index < points.length; index += 1) {
    if (sparklineValue(points[index]) !== null) valid.push(points[index]);
  }
  if (valid.length <= maximum) return valid.slice(0);
  if (maximum === 1) return [valid[valid.length - 1]];

  for (index = 0; index < maximum; index += 1) {
    selectedIndex = Math.round(index * (valid.length - 1) / (maximum - 1));
    if (selectedIndex === previousIndex) continue;
    result.push(valid[selectedIndex]);
    previousIndex = selectedIndex;
  }
  return result;
}

// Never show a one-day fallback as a longer requested range.
function chartQuoteFor(quote, history, matches, range) {
  if (matches && history) return history;
  return range === "1d" ? quote : null;
}

function rangePerformance(points) {
  var first = null;
  var last = null;
  var change;
  var count = 0;
  var index;
  var value;
  if (!isArray(points)) {
    return { change: null, percent: null, direction: "unknown", first: null };
  }
  for (index = 0; index < points.length; index += 1) {
    value = sparklineValue(points[index]);
    if (value === null) continue;
    if (first === null) first = value;
    last = value;
    count += 1;
  }
  if (first === null || last === null || count < 2) {
    return { change: null, percent: null, direction: "unknown", first: null };
  }
  change = last - first;
  return {
    first: first,
    change: change,
    percent: first === 0 ? null : change / first * 100,
    direction: changeDirection(change)
  };
}

function firstNumber(object, keys) {
  var index;
  var value;
  if (object === null || typeof object !== "object") return null;
  for (index = 0; index < keys.length; index += 1) {
    if (!hasOwn(object, keys[index])) continue;
    value = finiteNumber(object[keys[index]]);
    if (value !== null) return value;
  }
  return null;
}

function firstText(object, keys, maximumLength) {
  var index;
  var value;
  if (object === null || typeof object !== "object") return "";
  for (index = 0; index < keys.length; index += 1) {
    if (!hasOwn(object, keys[index])) continue;
    value = safeText(object[keys[index]], maximumLength);
    if (value !== "") return value;
  }
  return "";
}

function firstTimestamp(object, keys) {
  var index;
  var value;
  if (object === null || typeof object !== "object") return null;
  for (index = 0; index < keys.length; index += 1) {
    if (!hasOwn(object, keys[index])) continue;
    value = timestampMilliseconds(object[keys[index]]);
    if (value !== null) return value;
  }
  return null;
}

function pointFromValue(point, fallbackTimestamp) {
  var value = null;
  var time = null;

  if (finiteNumber(point) !== null) {
    value = finiteNumber(point);
    time = timestampMilliseconds(fallbackTimestamp);
  } else if (isArray(point)) {
    if (point.length >= 2) {
      time = timestampMilliseconds(point[0]);
      value = finiteNumber(point[1]);
    }
  } else if (point !== null && typeof point === "object") {
    value = sparklineValue(point);
    time = firstTimestamp(point, ["time", "timestamp", "date", "x", "t"]);
    if (time === null) time = timestampMilliseconds(fallbackTimestamp);
  }

  if (value === null) return null;
  return { time: time, value: value };
}

function rawHistory(quote, meta) {
  var points = null;
  var timestamps = null;
  var indicators;

  if (isArray(quote.points)) points = quote.points;
  else if (isArray(quote.sparkline)) points = quote.sparkline;
  else if (isArray(quote.history)) points = quote.history;
  else if (isArray(quote.series)) points = quote.series;
  else if (isArray(quote.closes)) points = quote.closes;

  if (isArray(quote.sparklineTimestamps)) timestamps = quote.sparklineTimestamps;
  else if (isArray(quote.timestamps)) timestamps = quote.timestamps;
  else if (isArray(quote.timestamp)) timestamps = quote.timestamp;

  indicators = quote.indicators;
  if (points === null && indicators && isArray(indicators.quote) &&
      indicators.quote.length > 0 && isArray(indicators.quote[0].close)) {
    points = indicators.quote[0].close;
  }

  if (points === null && meta && isArray(meta.points)) points = meta.points;
  return { points: points || [], timestamps: timestamps || [] };
}

function normalizedSparklineData(quote, meta, maximumPoints) {
  var history = rawHistory(quote, meta);
  var points = [];
  var sampled;
  var values = [];
  var timestamps = [];
  var timestampsValid = true;
  var index;
  var point;
  for (index = 0; index < history.points.length; index += 1) {
    point = pointFromValue(history.points[index], history.timestamps[index]);
    if (point !== null) points.push(point);
  }
  sampled = downsampleSparkline(points, maximumPoints);
  for (index = 0; index < sampled.length; index += 1) {
    values.push(sampled[index].value);
    // Canvas arithmetic needs numeric values. Normalize provider seconds and
    // ISO strings to Unix milliseconds. A partial timeline is discarded so a
    // missing timestamp cannot be mistaken for epoch zero by QML Number().
    if (sampled[index].time === null) timestampsValid = false;
    else timestamps.push(sampled[index].time);
  }
  if (!timestampsValid || timestamps.length !== values.length) timestamps = [];
  return { values: values, timestamps: timestamps };
}

function normalizedSparkline(quote, meta, maximumPoints) {
  return normalizedSparklineData(quote, meta, maximumPoints).values;
}

function isoTimestamp(value) {
  var milliseconds = timestampMilliseconds(value);
  if (milliseconds === null) return null;
  try {
    return new Date(milliseconds).toISOString();
  } catch (error) {
    return null;
  }
}

function firstBoolean(object, keys) {
  var index;
  var value;
  var normalized;
  if (object === null || typeof object !== "object") return null;
  for (index = 0; index < keys.length; index += 1) {
    if (!hasOwn(object, keys[index])) continue;
    value = object[keys[index]];
    if (typeof value === "boolean") return value;
    if (value === 1 || value === 0) return value === 1;
    if (typeof value === "string") {
      normalized = trimmed(value).toLowerCase();
      if (normalized === "true" || normalized === "yes" || normalized === "1") return true;
      if (normalized === "false" || normalized === "no" || normalized === "0") return false;
    }
  }
  return null;
}

function firstOpenValue(quote, meta) {
  var value = firstNumber(quote, ["regularMarketOpen", "open"]);
  var opens;
  var index;
  if (value !== null) return value;
  value = firstNumber(meta, ["regularMarketOpen", "open"]);
  if (value !== null) return value;
  if (quote && quote.indicators && isArray(quote.indicators.quote) &&
      quote.indicators.quote.length > 0 && isArray(quote.indicators.quote[0].open)) {
    opens = quote.indicators.quote[0].open;
    for (index = 0; index < opens.length; index += 1) {
      value = finiteNumber(opens[index]);
      if (value !== null) return value;
    }
  }
  return null;
}

function normalizedStateToken(value) {
  var state = safeText(value, 40).toLowerCase()
    .replace(/[\s\-]+/g, "_")
    .replace(/[^a-z0-9_]+/g, "")
    .replace(/^_+|_+$/g, "");
  if (state === "regular" || state === "open" || state === "trading" ||
      state === "market_open" || state === "regular_market") return "open";
  if (state === "pre" || state === "premarket" || state === "pre_market") return "pre";
  if (state === "post" || state === "postmarket" || state === "post_market" ||
      state === "after_hours" || state === "afterhours") return "post";
  if (state === "closed" || state === "market_closed" || state === "regular_market_closed") {
    return "closed";
  }
  if (state === "continuous" || state === "247" || state === "24_7" || state === "24x7" ||
      state === "always_open") return "continuous";
  if (state === "halted" || state === "trading_halted") return "halted";
  return "unknown";
}

function inferredSessionState(marketState, sessionState, instrumentType) {
  var state = normalizedStateToken(sessionState);
  var type;
  if (state !== "unknown") return state;
  state = normalizedStateToken(marketState);
  if (state !== "unknown") return state;
  type = safeText(instrumentType, 40).toLowerCase().replace(/[\s\-]+/g, "_");
  if (type === "cryptocurrency" || type === "crypto" || type === "digital_asset") {
    return "continuous";
  }
  return "unknown";
}

function sanitizeQuote(rawQuote, fallbackSymbol, fetchedAt, maximumPoints) {
  var quote = rawQuote;
  var meta;
  var symbol;
  var name;
  var currency;
  var exchange;
  var exchangeTimezone;
  var instrumentType;
  var marketState;
  var sessionState;
  var price;
  var previousClose;
  var change;
  var changePercent;
  var regularMarketOpen;
  var dayLow;
  var dayHigh;
  var fiftyTwoWeekLow;
  var fiftyTwoWeekHigh;
  var volume;
  var marketTime;
  var sparklineData;
  var sparkline;
  var range;
  var cached;
  var cacheAgeSec;
  var stale;

  if (quote === null || typeof quote !== "object" || isArray(quote)) return null;
  meta = quote.meta && typeof quote.meta === "object" ? quote.meta : {};

  symbol = normalizeSymbol(firstText(quote, ["symbol", "ticker"], MAX_SYMBOL_LENGTH));
  if (symbol === null) {
    symbol = normalizeSymbol(firstText(meta, ["symbol", "ticker"], MAX_SYMBOL_LENGTH));
  }
  if (symbol === null) symbol = normalizeSymbol(fallbackSymbol);
  if (symbol === null) return null;

  name = firstText(quote, ["name", "displayName", "shortName", "longName"], 120);
  if (name === "") {
    name = firstText(meta, ["name", "displayName", "shortName", "longName"], 120);
  }
  if (name === "") name = symbol;

  currency = normalizeCurrency(firstText(quote, ["currency"], 8));
  if (currency === "") currency = normalizeCurrency(firstText(meta, ["currency"], 8));
  exchange = firstText(quote, ["exchange", "exchangeName", "fullExchangeName"], 80);
  if (exchange === "") {
    exchange = firstText(meta, ["exchange", "exchangeName", "fullExchangeName"], 80);
  }
  exchangeTimezone = firstText(quote, [
    "exchangeTimezone", "exchangeTimezoneName", "timezone"
  ], 80);
  if (exchangeTimezone === "") {
    exchangeTimezone = firstText(meta, [
      "exchangeTimezone", "exchangeTimezoneName", "timezone"
    ], 80);
  }
  instrumentType = firstText(quote, ["instrumentType", "quoteType", "type"], 40);
  if (instrumentType === "") {
    instrumentType = firstText(meta, ["instrumentType", "quoteType", "type"], 40);
  }
  marketState = firstText(quote, ["marketState", "marketStatus"], 40);
  if (marketState === "") marketState = firstText(meta, ["marketState", "marketStatus"], 40);
  sessionState = firstText(quote, ["sessionState", "session"], 40);
  if (sessionState === "") sessionState = firstText(meta, ["sessionState", "session"], 40);
  sessionState = inferredSessionState(marketState, sessionState, instrumentType);

  price = firstNumber(quote, ["price", "regularMarketPrice", "currentPrice"]);
  if (price === null) price = firstNumber(meta, ["price", "regularMarketPrice", "currentPrice"]);
  previousClose = firstNumber(quote, [
    "previousClose", "prevClose", "regularMarketPreviousClose", "chartPreviousClose"
  ]);
  if (previousClose === null) {
    previousClose = firstNumber(meta, [
      "previousClose", "prevClose", "regularMarketPreviousClose", "chartPreviousClose"
    ]);
  }
  change = firstNumber(quote, ["change", "regularMarketChange"]);
  if (change === null) change = firstNumber(meta, ["change", "regularMarketChange"]);
  changePercent = firstNumber(quote, [
    "changePercent", "changePct", "changePercentage", "regularMarketChangePercent"
  ]);
  if (changePercent === null) {
    changePercent = firstNumber(meta, [
      "changePercent", "changePct", "changePercentage", "regularMarketChangePercent"
    ]);
  }

  regularMarketOpen = firstOpenValue(quote, meta);
  dayLow = firstNumber(quote, ["dayLow", "regularMarketDayLow"]);
  if (dayLow === null) dayLow = firstNumber(meta, ["dayLow", "regularMarketDayLow"]);
  dayHigh = firstNumber(quote, ["dayHigh", "regularMarketDayHigh"]);
  if (dayHigh === null) dayHigh = firstNumber(meta, ["dayHigh", "regularMarketDayHigh"]);
  fiftyTwoWeekLow = firstNumber(quote, ["fiftyTwoWeekLow", "week52Low"]);
  if (fiftyTwoWeekLow === null) {
    fiftyTwoWeekLow = firstNumber(meta, ["fiftyTwoWeekLow", "week52Low"]);
  }
  fiftyTwoWeekHigh = firstNumber(quote, ["fiftyTwoWeekHigh", "week52High"]);
  if (fiftyTwoWeekHigh === null) {
    fiftyTwoWeekHigh = firstNumber(meta, ["fiftyTwoWeekHigh", "week52High"]);
  }
  volume = firstNumber(quote, ["volume", "regularMarketVolume"]);
  if (volume === null) volume = firstNumber(meta, ["volume", "regularMarketVolume"]);

  sparklineData = normalizedSparklineData(quote, meta, maximumPoints);
  sparkline = sparklineData.values;
  if (price === null && sparkline.length > 0) price = sparkline[sparkline.length - 1];
  if (price === null) return null;
  if (change === null && price !== null && previousClose !== null) {
    change = price - previousClose;
  }
  if (changePercent === null && change !== null && previousClose !== null && previousClose !== 0) {
    changePercent = change / previousClose * 100;
  }

  marketTime = firstTimestamp(quote, [
    "updatedAt", "marketTime", "regularMarketTime", "timestamp"
  ]);
  if (marketTime === null) {
    marketTime = firstTimestamp(meta, [
      "updatedAt", "marketTime", "regularMarketTime", "timestamp"
    ]);
  }
  range = normalizeRange(firstText(quote, ["range", "chartRange"], 16),
    firstText(meta, ["range", "chartRange"], 16));
  cached = firstBoolean(quote, ["cached", "fromCache"]);
  if (cached === null) cached = firstBoolean(meta, ["cached", "fromCache"]);
  if (cached === null) cached = false;
  cacheAgeSec = firstNumber(quote, ["cacheAgeSec", "cacheAgeSeconds"]);
  if (cacheAgeSec === null) cacheAgeSec = firstNumber(meta, ["cacheAgeSec", "cacheAgeSeconds"]);
  if (cacheAgeSec !== null) {
    cacheAgeSec = Math.min(31536000, Math.max(0, Math.floor(cacheAgeSec)));
  }
  stale = firstBoolean(quote, ["stale", "isStale"]);
  if (stale === null) stale = firstBoolean(meta, ["stale", "isStale"]);
  if (stale === null) stale = false;
  return {
    symbol: symbol,
    name: name,
    currency: currency === "" ? null : currency,
    regularMarketPrice: price,
    previousClose: previousClose,
    change: change,
    changePercent: changePercent,
    marketTime: marketTime === null ? null : isoTimestamp(marketTime),
    sparkline: sparkline,
    sparklineTimestamps: sparklineData.timestamps,
    range: range,
    exchange: exchange === "" ? null : exchange,
    exchangeTimezone: exchangeTimezone === "" ? null : exchangeTimezone,
    instrumentType: instrumentType === "" ? null : instrumentType,
    marketState: marketState === "" ? null : marketState.toUpperCase(),
    sessionState: sessionState,
    regularMarketOpen: regularMarketOpen,
    dayLow: dayLow,
    dayHigh: dayHigh,
    fiftyTwoWeekLow: fiftyTwoWeekLow,
    fiftyTwoWeekHigh: fiftyTwoWeekHigh,
    volume: volume,
    cached: cached,
    cacheAgeSec: cacheAgeSec,
    stale: stale
  };
}

function responseItems(payload) {
  var chart;
  if (isArray(payload)) return payload;
  if (payload === null || typeof payload !== "object") return [];
  chart = payload.chart;
  if (chart && isArray(chart.result)) return chart.result;
  if (isArray(payload.quotes)) return payload.quotes;
  if (isArray(payload.results)) return payload.results;
  if (isArray(payload.items)) return payload.items;
  if (isArray(payload.data)) return payload.data;
  if (payload.quote && typeof payload.quote === "object") return [payload.quote];
  if (hasOwn(payload, "symbol") || hasOwn(payload, "meta")) return [payload];
  return [];
}

function parsedPayload(payload) {
  if (typeof payload !== "string") return payload;
  if (trimmed(payload) === "") return null;
  try {
    return JSON.parse(payload);
  } catch (error) {
    return null;
  }
}

function normalizedQuoteList(parsed, requestedSymbols, maximumPoints) {
  var items = responseItems(parsed);
  var requested = normalizeSymbols(requestedSymbols);
  var requestedSet = {};
  var fetchedAt = firstTimestamp(parsed, [
    "generatedAt", "fetchedAt", "updatedAt", "timestamp"
  ]);
  var limit = boundedInteger(
    maximumPoints,
    DEFAULT_SPARKLINE_POINTS,
    0,
    MAX_SPARKLINE_POINTS
  );
  var quotes = [];
  var seen = {};
  var ordered = [];
  var bySymbol = {};
  var index;
  var raw;
  var candidate;
  var fallback;
  var quote;
  var key;

  for (index = 0; index < requested.length; index += 1) {
    requestedSet["$" + requested[index]] = true;
  }

  for (index = 0; index < items.length && quotes.length < MAX_SYMBOLS; index += 1) {
    raw = items[index];
    candidate = raw;
    fallback = requested.length === 1 ? requested[0] : requested[index];
    if (raw && typeof raw === "object" && raw.quote && typeof raw.quote === "object") {
      candidate = raw.quote;
      fallback = normalizeSymbol(raw.symbol) || fallback;
    }
    quote = sanitizeQuote(candidate, fallback, fetchedAt, limit);
    if (quote === null) continue;
    key = "$" + quote.symbol;
    if (requested.length > 0 && !hasOwn(requestedSet, key)) continue;
    if (hasOwn(seen, key)) continue;
    seen[key] = true;
    quotes.push(quote);
    bySymbol[key] = quote;
  }

  if (requested.length === 0) return quotes;
  for (index = 0; index < requested.length; index += 1) {
    key = "$" + requested[index];
    if (hasOwn(bySymbol, key)) ordered.push(bySymbol[key]);
  }
  return ordered;
}

function sanitizeProviderError(value) {
  var symbol;
  var code;
  var message;
  if (value === null || typeof value !== "object" || isArray(value)) return null;
  symbol = normalizeSymbol(value.symbol);
  code = safeText(value.code, 40).toLowerCase().replace(/[^a-z0-9_]+/g, "_")
    .replace(/^_+|_+$/g, "");
  message = safeText(value.message, 160);
  if (code === "") code = "unknown_error";
  if (message === "") message = "Quote unavailable.";
  return { symbol: symbol, code: code, message: message };
}

function normalizedErrors(parsed, requestedSymbols) {
  var source = parsed && isArray(parsed.errors) ? parsed.errors : [];
  var requested = normalizeSymbols(requestedSymbols);
  var requestedSet = {};
  var result = [];
  var index;
  var error;
  for (index = 0; index < requested.length; index += 1) {
    requestedSet["$" + requested[index]] = true;
  }
  for (index = 0; index < source.length && result.length < MAX_SYMBOLS; index += 1) {
    error = sanitizeProviderError(source[index]);
    if (error === null) continue;
    if (requested.length > 0 && error.symbol !== null &&
        !hasOwn(requestedSet, "$" + error.symbol)) continue;
    result.push(error);
  }
  return result;
}

function responseStatus(quotes, errors) {
  if (quotes.length > 0 && errors.length > 0) return "partial";
  if (quotes.length > 0) return "ready";
  if (errors.length > 0) return "failed";
  return "empty";
}

function invalidProviderResponse(message) {
  return {
    ok: false,
    error: message,
    schemaVersion: null,
    provider: "",
    generatedAt: null,
    status: "failed",
    quotes: [],
    errors: []
  };
}

function normalizeProviderResponse(payload, requestedSymbols, maximumPoints) {
  var parsed = parsedPayload(payload);
  var isEnvelope;
  var schemaVersion;
  var provider;
  var generatedAt;
  var quotes;
  var errors;

  if (parsed === null || typeof parsed !== "object" || isArray(parsed)) {
    return invalidProviderResponse("The quote provider returned malformed data");
  }

  isEnvelope = hasOwn(parsed, "schemaVersion") || hasOwn(parsed, "quotes") ||
    hasOwn(parsed, "errors") || hasOwn(parsed, "provider");
  if (isEnvelope) {
    schemaVersion = finiteNumber(parsed.schemaVersion);
    if (schemaVersion !== 1) {
      return invalidProviderResponse("The quote provider returned an unsupported schema");
    }
    if (!isArray(parsed.quotes) || !isArray(parsed.errors)) {
      return invalidProviderResponse("The quote provider returned an incomplete document");
    }
  } else if (!(parsed.chart && typeof parsed.chart === "object")) {
    return invalidProviderResponse("The quote provider returned an incomplete document");
  } else if (parsed.chart.error) {
    return invalidProviderResponse("The quote provider returned an error");
  } else if (!isArray(parsed.chart.result)) {
    return invalidProviderResponse("The quote provider returned no chart result");
  }

  quotes = normalizedQuoteList(parsed, requestedSymbols, maximumPoints);
  errors = normalizedErrors(parsed, requestedSymbols);
  if (quotes.length === 0 && errors.length === 0 &&
      responseItems(parsed).length > 0 &&
      normalizedQuoteList(parsed, null, maximumPoints).length === 0) {
    return invalidProviderResponse("The quote provider returned no usable prices");
  }
  provider = safeText(parsed.provider, 80);
  if (provider === "") provider = "Yahoo Finance chart";
  generatedAt = isoTimestamp(firstTimestamp(parsed, [
    "generatedAt", "fetchedAt", "updatedAt", "timestamp"
  ]));

  return {
    ok: true,
    error: "",
    schemaVersion: isEnvelope ? 1 : null,
    provider: provider,
    generatedAt: generatedAt,
    status: responseStatus(quotes, errors),
    quotes: quotes,
    errors: errors
  };
}

function sanitizeProviderResponse(payload, requestedSymbols, maximumPoints) {
  return normalizeProviderResponse(payload, requestedSymbols, maximumPoints);
}

function findQuote(quotesOrResponse, symbol) {
  var wanted = normalizeSymbol(symbol);
  var quotes = quotesOrResponse;
  var index;
  if (wanted === null) return null;
  if (!isArray(quotes) && quotes && isArray(quotes.quotes)) quotes = quotes.quotes;
  if (!isArray(quotes)) return null;
  for (index = 0; index < quotes.length; index += 1) {
    if (!quotes[index] || typeof quotes[index] !== "object") continue;
    if (normalizeSymbol(quotes[index].symbol) === wanted) return quotes[index];
  }
  return null;
}

function changeNumber(value) {
  var number;
  if (value !== null && typeof value === "object") {
    number = firstNumber(value, ["change", "regularMarketChange"]);
    if (number === null) {
      number = firstNumber(value, [
        "changePercent", "changePercentage", "regularMarketChangePercent"
      ]);
    }
    return number;
  }
  return finiteNumber(value);
}

function changeDirection(value) {
  var number = changeNumber(value);
  if (number === null) return "unknown";
  if (number > 0) return "up";
  if (number < 0) return "down";
  return "flat";
}

function directionForChange(value) {
  return changeDirection(value);
}

function unsignedPercent(value) {
  var number = finiteNumber(value);
  if (number === null) return "";
  return groupedFixed(Math.abs(number), 2) + " percent";
}

function changeAccessibilityLabel(changeOrQuote, percentValue, currencyValue) {
  var change = finiteNumber(changeOrQuote);
  var percent = finiteNumber(percentValue);
  var currency = normalizeCurrency(currencyValue);
  var direction;
  var label;

  if (changeOrQuote !== null && typeof changeOrQuote === "object") {
    change = firstNumber(changeOrQuote, ["change", "regularMarketChange"]);
    percent = firstNumber(changeOrQuote, [
      "changePercent", "changePercentage", "regularMarketChangePercent"
    ]);
    currency = normalizeCurrency(changeOrQuote.currency);
  }

  direction = changeDirection(change !== null ? change : percent);
  if (direction === "unknown") return "Change unavailable";
  if (direction === "flat") return "Unchanged";

  label = direction === "up" ? "Up" : "Down";
  if (change !== null) {
    label += " by " + formatMagnitude(change, currency, decimalPlacesForPrice(change));
  }
  if (percent !== null) {
    label += (change !== null ? ", " : " ") + unsignedPercent(percent);
  }
  return label;
}

function configuredRefreshSeconds(value) {
  var number = finiteNumber(value);
  if (number === null || number <= 0) return 900;
  return Math.max(1, Math.floor(number));
}

function quoteSessionState(quote) {
  if (quote === null || typeof quote !== "object") return "unknown";
  return inferredSessionState(quote.marketState, quote.sessionState, quote.instrumentType);
}

function recommendedRefreshInterval(quotesOrResponse, configuredSec) {
  var configured = configuredRefreshSeconds(configuredSec);
  var quotes = quotesOrResponse;
  var sawPreOrPost = false;
  var sawClosed = false;
  var sawUnknown = false;
  var state;
  var index;
  if (!isArray(quotes) && quotes && isArray(quotes.quotes)) quotes = quotes.quotes;
  if (!isArray(quotes) || quotes.length === 0) return configured;
  for (index = 0; index < quotes.length; index += 1) {
    state = quoteSessionState(quotes[index]);
    if (state === "open" || state === "continuous") return configured;
    if (state === "pre" || state === "post") sawPreOrPost = true;
    else if (state === "closed" || state === "halted") sawClosed = true;
    else sawUnknown = true;
  }
  // Unknown provider state must not silently slow an explicitly configured
  // cadence. A mixed closed/unknown watchlist therefore remains configured.
  if (sawUnknown) return configured;
  if (sawPreOrPost) return Math.max(configured, 900);
  if (sawClosed) return Math.max(configured, 3600);
  return configured;
}

function quoteAccessibilityLabel(quote, nowValue) {
  var parts = [];
  var name;
  var price;
  var exchange;
  var sessionState;
  if (quote === null || typeof quote !== "object") return "Quote unavailable";
  name = safeText(quote.name || quote.displayName || quote.symbol, 120);
  if (name !== "") parts.push(name);
  price = formatPrice(
    hasOwn(quote, "regularMarketPrice") ? quote.regularMarketPrice : quote.price,
    quote.currency
  );
  if (price !== MISSING_VALUE) parts.push(price);
  parts.push(changeAccessibilityLabel(quote));
  exchange = safeText(quote.exchange, 80);
  if (exchange !== "") parts.push("Exchange " + exchange);
  sessionState = quoteSessionState(quote);
  if (sessionState !== "unknown") parts.push(marketStateLabel(quote));
  if (quote.stale === true) parts.push("Stale quote");
  else if (quote.cached === true) parts.push("Cached quote");
  if (timestampMilliseconds(quote.marketTime || quote.updatedAt) !== null) {
    parts.push("Updated " +
      formatFreshness(quote.marketTime || quote.updatedAt, nowValue).toLowerCase());
  }
  return parts.join(", ");
}

// Node's parser does not understand `.pragma library`; portable tests remove
// that first line before evaluation. This guard then exposes the same API while
// remaining inert in QML.
if (typeof module !== "undefined" && module && module.exports) {
  module.exports = {
    MAX_SYMBOLS: MAX_SYMBOLS,
    profiles: profiles,
    profileById: profileById,
    symbolsForProfile: symbolsForProfile,
    profileForSymbols: profileForSymbols,
    normalizeProfileId: normalizeProfileId,
    normalizeSymbol: normalizeSymbol,
    normalizeSymbols: normalizeSymbols,
    addSymbol: addSymbol,
    removeSymbol: removeSymbol,
    moveSymbol: moveSymbol,
    normalizeBarMode: normalizeBarMode,
    rangeOptions: rangeOptions,
    normalizeRange: normalizeRange,
    rangeLabel: rangeLabel,
    rangeInterval: rangeInterval,
    selectedRange: selectedRange,
    selectedRangeForSymbol: selectedRangeForSymbol,
    withSelectedRange: withSelectedRange,
    setSelectedRange: setSelectedRange,
    normalizeCurrency: normalizeCurrency,
    formatPrice: formatPrice,
    formatCurrency: formatCurrency,
    formatDelta: formatDelta,
    formatPercent: formatPercent,
    formatVolume: formatVolume,
    formatFreshness: formatFreshness,
    marketStateLabel: marketStateLabel,
    asOfLabel: asOfLabel,
    statRows: statRows,
    timestampMilliseconds: timestampMilliseconds,
    downsampleSparkline: downsampleSparkline,
    rangePerformance: rangePerformance,
    chartQuoteFor: chartQuoteFor,
    sanitizeQuote: sanitizeQuote,
    normalizeProviderResponse: normalizeProviderResponse,
    sanitizeProviderResponse: sanitizeProviderResponse,
    findQuote: findQuote,
    changeDirection: changeDirection,
    directionForChange: directionForChange,
    changeAccessibilityLabel: changeAccessibilityLabel,
    quoteAccessibilityLabel: quoteAccessibilityLabel,
    recommendedRefreshInterval: recommendedRefreshInterval
  };
}
