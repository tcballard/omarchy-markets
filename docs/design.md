# Omarchy Markets design contract

- Community ID: `io.github.tcballard.omarchy-markets`. The reserved
  `omarchy.markets` ID is only for a future first-party upstream port.
- User problem: Pick a useful market profile, scan it from the Omarchy bar,
  inspect price history and key statistics, and maintain a personal watchlist
  without a second shell process, an account, or an API key.
- Kinds and entry points: one process-wide `service` (`Service.qml`) plus one
  `bar-widget` (`BarWidget.qml`). The widget privately loads `Panel.qml`.
- First run and consent: the plugin ships profile definitions but no live
  market data is requested until the user explicitly chooses a profile or
  enables a custom watchlist. `dataEnabled` is a strict JSON boolean.
- Built-in profiles: broad markets, Magnificent 7, crypto, meme coins,
  semiconductors, and UK markets. Profiles are editable starting points, not
  portfolios, recommendations, or claims that their members will stay fixed.
- Per-instance state: panel lifecycle, inspected symbol, keyboard cursor,
  manager state, ticker pause, and focus. Inspecting a row never silently
  changes the pinned bar symbol.
- Everyday hierarchy: the horizontal ticker is the default bar presentation;
  the panel puts company names below symbols, prices and daily changes in an
  aligned column, and range controls inside the selected-instrument detail.
  The chart baseline and return both use the first plotted price; quote changes
  explicitly compare against previous close. The provider footer has reserved
  space outside the scrolling viewport. The popup grows naturally up to 560
  scaled pixels or three quarters of the host's available card height, whichever
  is smaller; excess content scrolls within the card. Profiles remain setup and
  management concerns.
- Chart inspection: pointer hover selects the nearest plotted sample. A separate
  focus scope entered with I or Inspect chart owns Left/Right, Home/End and
  Escape/Tab; ordinary panel arrows retain range selection. Painting and hit
  testing share filtered price/time pairs and coordinates. The readout labels
  UTC and missing times explicitly, keeps a fixed height, and leaves the live
  quote unchanged. It uses existing history without a new provider request;
  opening previously hidden details retains the normal history-loading path.
- Durable configuration: selected profile, symbols, pinned symbol, selected
  chart range, bar mode, ticker width/speed, refresh interval, and consent live
  inline on the widget entry in Omarchy's `shell.json`.
- Watchlist-management candidate: up to eight named lists with unique names
  of 1–32 characters. Each stores at most twelve symbols in saved order, its
  pinned symbol and starting-profile ID. The active list mirrors the existing
  flat `symbols`, `primarySymbol` and `profile` settings; older installs are
  represented as one list without changing their symbols or consent. The first
  named-list action persists that library, and later symbol/pin/profile edits
  update only its active member. `watchlists` and `activeWatchlistId` stay inline
  in `shell.json`; no private file, process or new endpoint is introduced.
- `sortMode` and `chartVisible` are durable widget-wide preferences. Sorting
  affects only the panel: ties retain saved order, missing changes sort last,
  and selection follows symbol identity through refreshed rankings. The manager
  and ticker retain saved order. Switching lists never enables paused data.
- Candidate acceptance: legacy settings survive migration; copy/rename/switch/
  delete preserve other lists; deletion requires confirmation and retains at
  least one list; multiple monitors receive the host's updated inline settings;
  keyboard and pointer actions work; sorting preserves the inspected symbol;
  restart restores the active list, sorting and chart visibility. Portable
  transition tests establish state behavior; live QML input/layout and host
  propagation remain separate checks in `docs/acceptance.md`.
- Process-wide state: one singleton owns quote polling, last-good merging,
  selected-symbol history requests, provider status, retry/backoff, and the
  bounded process lifecycle shared across monitors.
- First-party lifecycle: a future bundled service must poll only while its
  widget is present in the bar. Removal cancels requests and timers even though
  Omarchy keeps first-party services loadable.
- External command: the trusted system interpreter `/usr/bin/python3` runs the
  bundled standard-library helper with `-I -S` and argument arrays, a cleared
  environment and a fixed UTF-8 locale. The inherited `PATH`
  is never used for interpreter resolution. There is no shell interpolation, package
  manager, install hook, daemon, credential access, telemetry, or privilege.
- Provider boundary: the helper is the sole Yahoo adapter. It emits a bounded,
  versioned quote/history envelope and caps symbols, names, points, files,
  response bytes, worker count, redirects, host, timeout, and error text.
- Network: HTTPS GET is fixed to
  `query1.finance.yahoo.com/v8/finance/chart/<encoded-symbol>`. Yahoo's chart
  endpoint is unofficial, best effort, potentially delayed, and subject to
  change. The interface never says real-time or treats data as trading advice.
- Cache: regenerated provider results may be stored atomically under the user's
  XDG cache directory with owner-only permissions. Cache entries are bounded,
  expire, never contain credentials, and are displayed explicitly as stale.
  The quote file is capped at 2 MiB; history files share a 60-file / 8 MiB budget
  under a nonblocking directory lock. Cache reads validate opened file identity
  without blocking on FIFOs, and skip unsafe or permissive storage.
- Refresh policy: 300–3600 seconds while an instrument is trading or
  continuous, at least 15 minutes in pre/post sessions, at least one hour when
  all instruments are closed, plus exponential failure backoff. Manual refresh
  has a cooldown and overlapping requests coalesce.
- History policy: `1D` reuses the watchlist result. `5D`, `1M`, `6M`, and
  `1Y` fetch only the inspected symbol, keep a bounded in-memory cache, and
  use the same persistent last-known-good boundary.
- IPC: `io.github.tcballard.omarchy-markets` exposes bounded `refresh()` and
  `status()` methods. Status contains counts and state, never raw provider data.
- User-visible states: setup, disabled, waiting, loading, ready, partial,
  stale/cached, market closed, offline/timeout, dependency missing, malformed
  response, empty, and failed. Missing values render as an em dash.
- Quote correctness: index values use points while the provider's currency
  metadata is retained. Tiny nonzero prices keep at least four significant
  digits, with bounded scientific notation for extreme magnitudes. Fetch time
  is labelled separately from quote time, which stays available with details
  collapsed. Regular-session prices are never labelled as extended-hours prices.
- Quote-age policy: active/continuous quotes older than the greater of 30
  minutes or twice the configured refresh interval are stale. This conservative
  threshold is not an exchange-delay guarantee. Completed regular-session
  bounds, when supplied, let closing quotes remain valid over weekends/holidays.
  The first threshold window after the open permits waiting for a new quote.
  Closed/pre/post sessions without completed bounds retain their explicit quote
  age; missing or future timestamps remain unknown. No exchange calendar or
  exact feed delay is inferred. The UI says quotes may be delayed. A 30-second
  local age check never requests data and cannot recover a failed fetch.
- Accessibility: every action has a keyboard path and accessible name; signed
  arrows/text accompany color; ticker motion is optional, pausable, horizontal
  only, and never the sole source of information.
- Verification: manifest/security validation, Python adapter/cache tests, pure
  JavaScript profile/format/state tests, process lifecycle tests, deterministic
  fictional fixtures, an offscreen Qt Quick smoke job, and a live Omarchy matrix covering horizontal/vertical,
  scaling, themes, multi-monitor, suspend/resume, reload, disable, removal, and
  first-party in-bar gating. Portable evidence must not be called live proof.
  The Qt smoke loads production bar/panel/editor/chart components with narrow
  host stubs and fails on warnings. It verifies bindings, painting and selected
  input paths, not real Omarchy imports or compositor behavior.
- Deferred: trading, holdings or P&L, alerts, news, recommendations, provider
  credentials, streaming guarantees, automatic currency conversion, and
  desktop surfaces outside the Omarchy bar/panel model.
