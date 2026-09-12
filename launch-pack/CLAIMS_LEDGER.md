# Claims ledger

> Historical launch planning. The plugin was published on 4 September 2026.
> Both root previews were replaced with actual screen captures on 12 September
> 2026; see `docs/acceptance.md` and `submission/reviewer-notes.md` for current evidence.

| ID | Claim | Importance | Evidence | Status | Qualification | Channels | Owner |
| --- | --- | --- | --- | --- | --- | --- | --- |
| C01 | Omarchy Markets provides a ticker-first bar and compact quote scanner. | Required | `BarWidget.qml`, `Panel.qml`, source-contract tests | Verified | Portable source evidence; live rendering still requires owner acceptance. | README, marketplace | Tom Ballard |
| C02 | Six editable starter profiles are included. | Required | `MarketModel.js`, model tests | Verified | Profiles are starting points, not recommendations. | README, marketplace | Tom Ballard |
| C03 | Market requests remain disabled until explicit setup consent. | Required | Strict boolean settings path, service lifecycle tests | Verified | Live network observation remains part of owner acceptance. | README, reviewer notes | Tom Ballard |
| C04 | Five history ranges and bounded last-good caching are implemented. | Required | Provider/cache tests and fixture validation | Verified | Provider availability and field coverage remain best effort. | README, marketplace | Tom Ballard |
| C05 | No API key or account is required. | Required | Helper and service source inspection | Verified | Direct requests go to Yahoo's unofficial endpoint. | README, marketplace | Tom Ballard |
| C06 | The current root preview proves the live Omarchy appearance. | Optional | `preview.png` provenance | Removed | The fixture preview is illustrative only; owner live capture will replace it. | None | Tom Ballard |
