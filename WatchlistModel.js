.pragma library
.import "MarketModel.js" as MarketModel

// Pure named-list and display-order transitions. The flat widget settings stay
// the active list so existing installs, the service and CLI settings keep working.
var MAX_WATCHLISTS = 8;
var MAX_NAME_LENGTH = 32;

function snapshot(value) {
  value = value || {};
  var symbols = MarketModel.normalizeSymbols(value.symbols);
  var primary = MarketModel.normalizeSymbol(value.primarySymbol);
  return {
    symbols: symbols,
    primarySymbol: symbols.indexOf(primary) >= 0 ? primary : (symbols[0] || ""),
    profile: MarketModel.normalizeProfileId(value.profile, "") || ""
  };
}

function normalizeLists(value) {
  if (!MarketModel.isArray(value)) return [];
  var lists = [];
  var ids = {};
  var names = {};
  for (var i = 0; i < Math.min(value.length, MAX_WATCHLISTS); i += 1) {
    var item = value[i];
    if (!item || typeof item !== "object") continue;
    var id = typeof item.id === "string" ? item.id : "";
    var name = MarketModel.safeText(item.name, MAX_NAME_LENGTH);
    if (!/^watchlist-[1-9][0-9]{0,7}$/.test(id) || !name
        || ids[id] || names["$" + name.toLowerCase()]) continue;
    var entry = snapshot(item);
    entry.id = id;
    entry.name = name;
    lists.push(entry);
    ids[id] = true;
    names["$" + name.toLowerCase()] = true;
  }
  return lists;
}

function indexOf(lists, id) {
  for (var i = 0; i < lists.length; i += 1) {
    if (lists[i].id === id) return i;
  }
  return -1;
}

function libraryForSettings(settings) {
  settings = settings || {};
  var lists = normalizeLists(settings.watchlists);
  var active = indexOf(lists, settings.activeWatchlistId);
  if (lists.length === 0) {
    var legacy = snapshot(settings);
    var profile = MarketModel.profileById(legacy.profile);
    legacy.id = "watchlist-1";
    legacy.name = profile ? profile.name : "My watchlist";
    lists.push(legacy);
    active = 0;
  } else if (active >= 0) {
    // Inline CLI edits and the ordinary symbol controls remain authoritative.
    var current = snapshot(settings);
    current.id = lists[active].id;
    current.name = lists[active].name;
    lists[active] = current;
  }
  // An invalid active ID must not overwrite an unrelated saved list.
  return { lists: lists, activeId: active >= 0 ? lists[active].id : "" };
}

function saveActive(settings) {
  if (!MarketModel.isArray(settings.watchlists) || settings.watchlists.length === 0) return settings;
  var library = libraryForSettings(settings);
  if (library.activeId) settings.watchlists = library.lists;
  return settings;
}

function failure(message) {
  return { ok: false, message: message };
}

function success(library, message) {
  var active = library.lists[indexOf(library.lists, library.activeId)];
  return {
    ok: true,
    message: message,
    patch: {
      watchlists: library.lists,
      activeWatchlistId: active.id,
      symbols: active.symbols,
      primarySymbol: active.primarySymbol,
      profile: active.profile
    }
  };
}

function nameForChange(value, lists, excludedId) {
  var name = MarketModel.safeText(value, MAX_NAME_LENGTH + 1);
  if (!name || name.length > MAX_NAME_LENGTH) return "";
  for (var i = 0; i < lists.length; i += 1) {
    if (lists[i].id !== excludedId && lists[i].name.toLowerCase() === name.toLowerCase()) return "";
  }
  return name;
}

function create(settings, nameValue, empty) {
  var library = libraryForSettings(settings);
  if (library.lists.length >= MAX_WATCHLISTS)
    return failure("You can keep up to " + MAX_WATCHLISTS + " watchlists. Delete one before adding another.");
  var name = nameForChange(nameValue, library.lists, "");
  if (!name) return failure("Use a unique watchlist name of 1–32 characters.");
  var entry = snapshot(empty ? {} : settings);
  var number = 1;
  while (indexOf(library.lists, "watchlist-" + number) >= 0) number += 1;
  entry.id = "watchlist-" + number;
  entry.name = name;
  library.lists.push(entry);
  library.activeId = entry.id;
  return success(library, empty ? "Created " + name + ". Add symbols or choose a starting profile."
    : "Saved a copy as " + name + ". Further edits are saved automatically.");
}

function select(settings, id) {
  var library = libraryForSettings(settings);
  if (indexOf(library.lists, id) < 0) return failure("That watchlist is no longer available.");
  if (!library.activeId)
    return failure("Save a copy of the current watchlist before switching; its saved-list ID is missing.");
  library.activeId = id;
  return success(library, "Switched watchlist.");
}

function rename(settings, nameValue) {
  var library = libraryForSettings(settings);
  var index = indexOf(library.lists, library.activeId);
  if (index < 0) return failure("Save a copy of the current watchlist before renaming it.");
  var name = nameForChange(nameValue, library.lists, library.activeId);
  if (!name) return failure("Use a unique watchlist name of 1–32 characters.");
  library.lists[index].name = name;
  return success(library, "Renamed watchlist to " + name + ".");
}

function remove(settings, id) {
  var library = libraryForSettings(settings);
  var index = indexOf(library.lists, id);
  if (index < 0 || id !== library.activeId) return failure("Select that watchlist before deleting it.");
  if (library.lists.length === 1) return failure("Keep at least one watchlist. You can rename it or remove its symbols.");
  var name = library.lists[index].name;
  library.lists.splice(index, 1);
  library.activeId = library.lists[Math.min(index, library.lists.length - 1)].id;
  return success(library, "Deleted " + name + ".");
}

function normalizeSort(value) {
  return value === "gainers" || value === "losers" ? value : "saved";
}

function sortSymbols(symbolsValue, quotes, modeValue) {
  var symbols = MarketModel.normalizeSymbols(symbolsValue);
  var mode = normalizeSort(modeValue);
  if (mode === "saved") return symbols;
  var rows = symbols.map(function(symbol, index) {
    var quote = MarketModel.findQuote(quotes, symbol);
    return { symbol: symbol, index: index,
      change: quote ? MarketModel.finiteNumber(quote.changePercent) : null };
  });
  rows.sort(function(a, b) {
    if (a.change === null && b.change !== null) return 1;
    if (b.change === null && a.change !== null) return -1;
    if (a.change === null || a.change === b.change) return a.index - b.index;
    return mode === "gainers" ? b.change - a.change : a.change - b.change;
  });
  return rows.map(function(row) { return row.symbol; });
}
