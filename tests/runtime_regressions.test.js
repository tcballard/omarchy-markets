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
  colors.Color = {muted: sample.muted};
  colors.foreground = sample.fg;
  const result = vm.runInContext(dimExpression, colors);
  assert.equal(result, sample.fallback ? sample.fg : sample.muted);
  if (sample.bg.a === 1) assert.ok(colors.contrastRatio(result, sample.bg) >= 4.5);
}

const scrolling = functions(panel, ["revealItem"], {
  panelScroll: {contentY: 0, height: 300, contentHeight: 900}, contentColumn: {},
});
const item = (y, height) => ({height, mapToItem: () => ({y})});
scrolling.revealItem(item(760, 100));
assert.equal(scrolling.panelScroll.contentY, 560, "offscreen profile is brought into view");
scrolling.revealItem(item(0, 100));
assert.equal(scrolling.panelScroll.contentY, 0, "wrapping back to first profile scrolls up");
scrolling.revealItem(item(850, 100));
assert.equal(scrolling.panelScroll.contentY, 600, "scroll remains within content bounds");

const model = {};
vm.runInNewContext(read("MarketModel.js").replace(/^\.pragma library\s*/, ""), model);
const settings = functions(bar, ["hasOwn", "boundedInteger", "normalizedSettingsPatch"], {
  MarketModel: model, selectedRange: "1d", barMode: "ticker", tickerWidth: 220,
  tickerSpeed: 24, refreshInterval: 900,
});
const previous = JSON.parse(read("tests/fixtures/v0.3.3-state.json")).settings;
const preserved = settings.normalizedSettingsPatch({}, structuredClone(previous));
assert.deepEqual(JSON.parse(JSON.stringify(preserved)), previous);
const paused = settings.normalizedSettingsPatch({tickerPaused: false}, structuredClone(previous));
assert.deepEqual(JSON.parse(JSON.stringify(paused)), {...previous, tickerPaused: false});
const disabled = {...previous, dataEnabled: false};
assert.equal(settings.normalizedSettingsPatch({}, disabled).dataEnabled, false);
console.log("Helper isolation, popup contrast, keyboard scrolling and v0.3.3 settings regressions passed.");

const detailState = functions(panel, ["toggleDetails", "requestFocusedHistory"], {
  detailsExpanded: true, focusedSymbol: "ACME", dataEnabled: true, selectedRange: "1mo",
  panelScroll: {contentY: 250}, Qt: {callLater: callback => callback()},
  keyCatcher: {forceActiveFocus() {}},
  service: {calls: [], requestHistory(symbol, range) { this.calls.push([symbol, range]); }},
});
detailState.toggleDetails();
assert.equal(detailState.detailsExpanded, false);
assert.equal(detailState.panelScroll.contentY, 0);
detailState.requestFocusedHistory();
assert.equal(detailState.service.calls.length, 0, "collapsed selection does not request history");
detailState.focusedSymbol = "OTHER";
detailState.toggleDetails();
assert.equal(detailState.detailsExpanded, true);
assert.deepEqual(detailState.service.calls, [["OTHER", "1mo"]], "expanding loads the current selection");
console.log("Chart collapse and expansion regressions passed.");
