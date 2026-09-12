# Marketplace reviewer notes

- Plugin: Omarchy Markets 0.3.2
- Intended repository: `https://github.com/tcballard/omarchy-markets`
- Permanent community ID: `io.github.tcballard.omarchy-markets`
- Kinds: process-wide service and bar widget
- Runtime dependency: Python 3.10 or newer at `/usr/bin/python3`; standard library only
- Network destination: `https://query1.finance.yahoo.com/v8/finance/chart/<encoded-symbol>`
- Credentials: none
- Privilege or installer surface: none
- Persistent writes: bounded owner-only quote/history cache below `${XDG_CACHE_HOME:-~/.cache}/omarchy-markets/`
- Expected review capability: QML `Process` execution in `Service.qml` invokes the bundled fixed helper by argument array through `/usr/bin/python3`, without inherited-`PATH` interpreter resolution
- Local advisory security outcome: `review-required`, zero findings, one `qml-process` capability
- Current screenshot provenance: actual installed Omarchy 0.3.2 panel and profile chooser captured on 12 September 2026; public Yahoo Finance data, no account data or generated imagery. Exact source/display evidence and limitations are in `docs/acceptance.md`.
- Live acceptance owner: Tom Ballard

## Screenshot refresh

The original listing was approved and published in
[marketplace issue #4216](https://github.com/omacom/omarchy-plugin-marketplace/issues/4216).
This update replaces both root preview images and corrects their documentation.
Runtime source and manifest version remain unchanged from the reviewed 0.3.2
commit. Request “Verify and publish a newer upstream commit” for the final full
SHA so the store refreshes the preview and records the new snapshot. A passing
local preflight does not itself update the store or grant verification.
