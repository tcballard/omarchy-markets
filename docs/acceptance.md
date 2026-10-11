# Omarchy Markets acceptance matrix

Portable tests are automated. The live rows must be completed on the target
Omarchy revision before a release is described as visually or operationally
verified.

| Surface or lifecycle | Portable | Live Omarchy |
| --- | --- | --- |
| Manifest, paths, limits, security patterns | Automated | Reconcile with `omarchy plugin validate` |
| Profile catalog and watchlist mutations | Automated | Profile selection persists |
| Provider parsing, ranges, cache and fallback | Automated fixtures | Fixed-host network smoke test |
| Quote/history process lifecycle and watchdogs | Automated state tests | Kill/restart/suspend recovery |
| Loading, ready, partial, stale, cached, offline | Automated source/fixture checks | Inspect every rendered state |
| Setup consent and disabled/no-poll state | Automated source/state checks | Verify with process/network observation |
| Horizontal single and ticker bar modes | Source checks | Inspect top/bottom bar |
| Vertical bar | Source checks | Inspect left/right bar |
| Panel focus, outside close, Escape and Tab | Selected focus/key paths in Qt; source checks | Keyboard/pointer smoke test |
| Add, remove, reorder, inspect and pin | Model/source checks | Keyboard and pointer smoke test |
| Ranges, stats and selected-only history | Model/provider checks | Inspect all five ranges |
| Chart pointer/keyboard inspection | Offscreen Qt: samples, painting, focus and range isolation | Check real popup input and scrolling |
| Themes, text scaling and translucent bar | Contrast/model checks | Light/dark themes and scaling |
| Multi-monitor singleton | Lifecycle/source checks | Two monitors, mixed scale |
| Reload, shell restart, disable/re-enable | State tests | Live lifecycle |
| First-party removed-from-bar polling gate | State/source checks | Upstream-port acceptance |
| Remove without credentials or daemon residue | Documentation check | Fresh checkout install/remove |

Record the date, plugin SHA, Omarchy SHA, monitor/scaling details, commands,
screenshots, and failures. A generated preview is not live-shell evidence.

## Chart inspection candidate — 11 October 2026

`tests/qml/run` passes locally with Qt Quick Test 6.4.2, 6.8.3 and 6.12.0 using the
software/offscreen backend: five behavior checks plus setup/cleanup on each,
with no warnings or skips. The 6.4 run caught a Qt/Omarchy Color-name collision;
production theme references now use an explicit Omarchy namespace.
It loads shipped components against the documented host stubs and checks
time-spaced hover selection, missing data, keyboard bounds, focus return,
unchanged range during inspection, normal range keys afterwards, and settings
reactivity. GitHub's separate `qml` job runs the suite with Ubuntu 24.04's Qt 6
packages; its log records the version and candidate SHA.
The separate `qml-qt612` CI job pins Qt 6.12.0, asserts the runtime version and
runs the same suite, including loading all shipped visual components with the
real QtQuick Color singleton present. The Qt 6.12 local run passed all seven
test phases without warnings, failures or skips; no further product changes
were needed after qualifying the Omarchy theme namespace. This verifies the
tested Markets UI paths on Qt 6.12, not the host's own Qt/Quickshell compatibility.

Live host checks remain unrun for this candidate:

- Hover and click chart points on the XPS; check price/UTC text and a stationary
  readout area on short screens and at the intended text scale.
- Use I, Left/Right, Home/End and Escape/Tab. Verify Escape first returns to the
  panel, normal arrows change ranges, and the next Escape closes the popup.
- Switch symbol, range and watchlist while inspecting; ensure no stale marker.
- Check light/dark themes, popup scrolling, and no extra requests while stepping
  through loaded points. Recheck named lists and restart persistence below.

## Watchlist-management candidate — 11 October 2026

Live checks below are **unrun** in the development environment. No live Omarchy
desktop is available there; offscreen Qt evidence is recorded above. Record the
candidate SHA and host details when run.

- Upgrade an existing custom list: symbols, order, pin, data consent, refresh
  interval and ticker settings survive unchanged.
- In Manage, create empty and copied lists; rename; reject duplicate names;
  cancel deletion, then confirm it. Switch back and verify edits and pins.
- Use N, Enter, Tab/Shift-Tab and Escape in the name editor; W switches lists;
  existing add/reorder/remove shortcuts keep working.
- Sort gainers/losers with S or the Order button. Refresh quotes and keep the
  same selected instrument; Manage and the ticker retain the saved order.
- Hide the chart, restart the shell and reopen: the active list, sort mode and
  chart visibility return. Expanding the chart requests the selected history.
- Pause data and switch lists: requests stay paused. Test with a second monitor
  if available to verify host propagation and singleton polling.
- Inspect manager/picker overflow at the intended scale, on a short viewport,
  and with long list names in light and dark themes.

## Capture record: 22 September 2026

- `preview.png`: screenshot supplied by Tom after testing the collapsible-chart
  candidate `5fb5068f9bdcdba7f3a55560d2de7641ece33cf4` (v0.4.0).
- Shows the live Markets panel on his XPS: AI & Semiconductors watchlist,
  NVDA selected, 5D range, expanded chart and the Hide chart control.
- The supplied PNG is preserved byte-for-byte, including its desktop framing.
  No generation, retouching, cropping or resizing was performed here.
- Tom confirmed the preceding layout checks and subsequently reported that
  the collapsible-chart build “all works nicely”. This is user-reported host
  acceptance; the screenshot alone does not demonstrate every interaction.
- `preview-profiles.png` remains the historical v0.3.2 capture below.

## v0.4.0 UX refresh — user-reported host acceptance

The 22 September XPS screenshot supplied by Tom prompted a wider watchlist,
clearer chart comparisons, chart-local range controls and an inset footer.
Tom subsequently confirmed the refreshed layout worked, then tested the
collapsible-chart candidate `5fb5068f9bdcdba7f3a55560d2de7641ece33cf4` and
reported that it “all works nicely”. The new main preview shows that build.
These are user-reported results on the XPS; no additional live testing was
performed in this development environment.

The requested UX checks for that host pass were:

- Eight- and twelve-symbol watchlists: company names, prices and daily changes
  stay inside each row, including long symbols and large currency values.
- Short/narrow screens and increased text scale: rows scroll, mini charts hide
  on narrow panels, and the provider footer remains inside the border.
- Select symbols and all five ranges quickly: no old-symbol or daily chart is
  labelled as another range; loading, offline and cached states are clear.
- A quote with a positive daily change and negative plotted return has explicit
  comparison labels and a baseline matching the plotted return.
- Keyboard selection remains visible; range arrows, Manage, setup, pinning,
  Escape, outside click and panel switching still work in light/dark themes.

The runtime source remains identical to the accepted collapsible-chart
candidate; this follow-up changes only screenshots and documentation.
Publication must record the final merged SHA and the scope of this user
acceptance. Unobserved matrix rows above are not newly claimed as passed.

## v0.3.4 publication — 22 September 2026

Tom confirmed the required XPS host checks passed at plugin commit
`c2eb85ea5302d2350ae0ebe8c97ce7ecebd1ed1d` on Omarchy
`4ee6d4eeea176b0bf4014ce8b82a148a9433efff`. The published
[v0.3.4 host record](https://github.com/tcballard/omarchy-markets/releases/download/v0.3.4/HOST-ACCEPTANCE.json)
contains that user attestation and its limits. The subsequent screenshot shows
that the footer still needs attention; this is addressed in the v0.4.0 layout.

## v0.3.4 preparation: 22 September 2026

The candidate addresses the overflow and muted-text defects documented in the
historical capture below. Portable validation passed: 77 Python tests, 50 model
tests, 24 lifecycle tests, the public API/path probes, isolated-helper startup,
popup contrast, keyboard scrolling and v0.3.3 settings/cache regressions.
Commands: `./tests/run`, `git diff --check`, and the Plugin Skills Bundle's
`validate_plugin.py --json --security .` at bundle commit
`221f77bebf7e240a5ef5f54bd2a102e68119bb69`.

These results describe the v0.3.4 preparation changes based on
`90ddf9b58708b3d9040cd7ca63cf82c4f992caa4`; CI reruns the checks against each PR
commit. The advisory scan found no structural errors or security findings;
process execution, collected output and documentation privilege references
still require human interpretation and are not certification.

The 0.3.4 live checks and fresh screenshots have **not** been performed in this
development environment. Historical observations are retained below, not
counted as new acceptance. The [release guide](releasing.md) names the required
x86_64 host checks. Publication now requires a host record for the exact merged
source and packages it with the release. Multi-monitor acceptance remains
unclaimed until observed separately.

## Capture record: 12 September 2026

- Installed plugin: 0.3.2, clean source commit
  `4a667dadfce52251ac4d897ac3f10fd5eaac3967`.
- Omarchy: development revision `4ee6d4eeea176b0bf4014ce8b82a148a9433efff`.
- Display: Sharp eDP-1, 1920 × 1200, scale 1.25, approximately 60 Hz.
- Theme: `matte-black`; horizontal top bar.
- Original `preview.png` (replaced on 22 September): actual running panel and ticker, AI & Semiconductors watchlist,
  NVDA selected, 1D range, public Yahoo Finance data with market-closed status.
- `preview-profiles.png`: actual profile chooser with market data temporarily
  paused; the existing watchlist was retained. This is the setup surface, not
  evidence of a fresh installation.
- Both images are direct `grim` region captures at native display scale, without
  image synthesis, retouching, or post-capture resizing. The resulting images
  are 637 × 1027 and 637 × 855 pixels respectively.

After opening the installed panel on an empty workspace and allowing it to
render, the captures used these logical screen rectangles:

```bash
grim -g '970,0 510x822' preview.png
grim -g '970,0 510x684' preview-profiles.png
```

The profile image was captured after temporarily setting `dataEnabled` to
`false`. The original `true` value was restored, the complete shell
configuration was compared byte-for-byte with its backup, and workspace 1 was
restored. The capture did not modify the installed plugin source.

Observed: populated quote rows and price history, ticker rendering, the
market-closed label, the data-paused state, and all six profile choices.
Secondary text is very dim in this theme; the provider footer and “Start custom”
control extend below the panel border. The captures preserve that actual
appearance. They do not establish full visual or lifecycle acceptance. The
uncompleted rows above remain open, including other themes, vertical bars,
multiple monitors, fresh install/removal, and recovery behavior.
