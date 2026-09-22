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
  space outside the scrolling viewport. Profiles remain setup and management concerns.
- Durable configuration: selected profile, symbols, pinned symbol, selected
  chart range, bar mode, ticker width/speed, refresh interval, and consent live
  inline on the widget entry in Omarchy's `shell.json`.
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
- Accessibility: every action has a keyboard path and accessible name; signed
  arrows/text accompany color; ticker motion is optional, pausable, horizontal
  only, and never the sole source of information.
- Verification: manifest/security validation, Python adapter/cache tests, pure
  JavaScript profile/format/state tests, process lifecycle tests, deterministic
  fictional fixtures, and a live Omarchy matrix covering horizontal/vertical,
  scaling, themes, multi-monitor, suspend/resume, reload, disable, removal, and
  first-party in-bar gating. Portable evidence must not be called live proof.
- Deferred: trading, holdings or P&L, alerts, news, recommendations, provider
  credentials, streaming guarantees, automatic currency conversion, and
  desktop surfaces outside the Omarchy bar/panel model.
