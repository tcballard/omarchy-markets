#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = path.join(__dirname, "..");
const bar = fs.readFileSync(path.join(root, "BarWidget.qml"), "utf8");
const service = fs.readFileSync(path.join(root, "Service.qml"), "utf8");

// Execute the shipped binding expressions with only the public host surface.
// This portable harness checks JS behavior, not QML parsing or reactivity.
function binding(source, name, context) {
  const match = source.match(new RegExp(
    "readonly property \\w+ " + name + ": ([\\s\\S]*?)(?=\\n  readonly property)"));
  assert.ok(match, "binding exists: " + name);
  const expression = match[1].trim();
  return vm.runInNewContext(expression.startsWith("{")
    ? "(function() " + expression + ")()"
    : "(" + expression + ")", context);
}

const pluginId = "io.github.tcballard.omarchy-markets";
const quoteService = { state: "setup" };
let mountedService = null;
const shell = {
  serviceFor(id) {
    assert.equal(id, pluginId);
    return mountedService;
  },
};
const widget = { bar: { shell }, moduleName: pluginId };
assert.equal(binding(bar, "marketService", { root: widget }), null);
mountedService = quoteService;
assert.equal(binding(bar, "marketService", { root: widget }), quoteService);
for (const barValue of [null, {}, { shell: {} }]) {
  assert.equal(binding(bar, "marketService", {
    root: { bar: barValue, moduleName: pluginId },
  }), null);
}

for (const directory of [
  "/home/user/.config/omarchy/plugins/" + pluginId,
  "/tmp/Markets with spaces #1 % café",
]) {
  const sourceDirectory = binding(service, "sourceDirectory", {
    manifest: { id: pluginId }, // public manifests contain no __sourceDir
    Qt: { resolvedUrl: relative => {
      assert.equal(relative, ".");
      return "file://" + directory.split("/").map(encodeURIComponent).join("/") + "/";
    } },
  });
  assert.equal(sourceDirectory, directory);
  assert.equal(binding(service, "helperPath", { sourceDirectory }),
    directory + "/scripts/fetch_quotes.py");
}
for (const url of ["qrc:/plugins/markets/", "https://example.com/markets/"]) {
  const sourceDirectory = binding(service, "sourceDirectory", {
    Qt: { resolvedUrl: () => url }, manifest: { id: pluginId },
  });
  assert.equal(sourceDirectory, "");
  assert.equal(binding(service, "helperPath", { sourceDirectory }), "");
}

console.log("Public plugin API and bundled helper path checks passed.");
