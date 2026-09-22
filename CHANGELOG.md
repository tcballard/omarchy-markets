# Changelog

## 0.4.0 — Unreleased

- Collapse chart details for a compact watchlist with Show/Hide chart or D;
  remember the choice until the plugin reloads. Left/Right opens the chart.

- Widen the panel and stack company names below symbols, with aligned price and
  daily change; hide miniature charts on narrow screens to preserve readable rows.
- Move range controls beside the selected chart and enlarge its price and plot.
- Separate changes versus previous close from returns since the first plotted
  price, and use the same starting-price baseline for the chart and its return.
- Show a loading/unavailable state instead of presenting daily data as another range.
- Keep the provider footer inside a reserved area beneath the scrollable content,
  and remove the duplicate quote refresh timestamp.

## 0.3.4 — 2026-09-22

- Isolate the Python quote/history helper from inherited startup hooks, search
  paths and environment variables.
- Reject blocking special files, unsafe ownership, hard links and permissive
  cache reads; keep writes atomic in private directories.
- Limit history storage to 60 files and 8 MiB, pruning expired entries and
  abandoned writes under a nonblocking directory lock.
- Fit the panel to host padding, borders and available screen height; clip and
  scroll overflow, reveal keyboard-selected profiles and improve muted text.
- Preserve v0.3.3 settings and cache formats with upgrade regression fixtures.
- Refresh the README with a centred title, one Plugin badge and linked reference.
- Stage releases on merge; require exact-source host acceptance before tagging
  and publication, and include that record in the verified release assets.

## 0.3.3 - 2026-09-17

- Fix permanent loading for third-party installs by looking up the quote service
  through the public shell API and resolving the bundled helper relative to QML.
- Handle URL-encoded installation paths and both public and internal registry
  notifications without startup signal warnings.

- Replace illustrative previews with documented live Omarchy captures.
- Clarify installation, update, data permissions and exact-commit marketplace
  status; add marketplace, release, CI and licence badges.
- Add a tested, immutable tagged-release workflow with source archives and checksums.

## 0.3.2 - 2026-09-04

- Anchor the panel to the clicked bar item instead of forcing screen-centred placement.
- Make all shipped starting profiles selectable again from Manage.
- Square the manager surfaces and align reorder controls with Hyprland conventions.
- Reclaim keyboard focus on open and expose the built-in manager key bindings.
- Size the panel to its complete content and remove the embedded scrollbar.

## 0.3.1 - 2026-09-02

- Pin quote and history workers to the trusted `/usr/bin/python3` interpreter
  instead of resolving `python3` through the inherited desktop-shell `PATH`.
- Fail closed when the trusted interpreter or absolute bundled helper path is
  unavailable, and add hostile-PATH regression coverage for both worker paths.

## 0.3.0 - 2026-09-01

- Make the bounded scrolling ticker the default horizontal bar experience.
- Rework the normal panel around a compact scan-first hierarchy: global range
  controls, denser quote rows, a separator, and one flat detail view.
- Keep Profiles as first-run and management affordances instead of allowing
  setup concepts to dominate the everyday market view.
- Narrow the default ticker viewport and update the deterministic preview to
  reflect the new interaction hierarchy.
- Add the public-install path, live capture checklist, marketplace issue draft,
  reviewer disclosures, and evidence-backed launch handoff.

## 0.2.0 - 2026-09-01

- Rename Market Watch to Omarchy Markets under the community-safe
  `io.github.tcballard.omarchy-markets` ID.
- Add an explicit first-run market-data consent gate and six editable profiles:
  Markets, Magnificent 7, Crypto, Meme Coins, AI & Semiconductors, and UK
  Markets.
- Add in-panel watchlist management with add, remove, reorder, inspect, and
  separate pin-to-bar actions.
- Add 1D, 5D, 1M, 6M, and 1Y chart ranges, time-proportional sparklines,
  previous-close reference lines, market-session metadata, range returns, and
  key instrument statistics.
- Add the optional bounded horizontal ticker while retaining the quiet static
  quote as the default and only vertical-bar presentation.
- Add an atomic, private, bounded XDG cache with explicit stale-data fallback.
- Add CI, a documented trust boundary, live-host acceptance matrix, expanded
  adversarial tests, and upstream-oriented release documentation.

## 0.1.0 - 2026-08-31

- Add a macOS Stocks-inspired primary quote and anchored watchlist panel.
- Add a single process-wide, multi-monitor-safe polling service.
- Add bounded local Yahoo chart fetching with partial and stale-data handling.
- Add horizontal and vertical bar layouts, keyboard navigation, and signed
  non-colour movement labels.
- Add complete inline settings metadata, deterministic fictional fixtures,
  portable model/provider tests, and a generated preview.
- Add process-signal lifecycle tests, bounded manual refreshes, adaptive failure
  backoff, contrast-aware movement colours, and explicit per-symbol stale state.
