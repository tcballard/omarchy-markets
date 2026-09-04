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
- Current screenshot provenance: deterministic fictional fixture; replace with a live Omarchy capture before submitting
- Live acceptance owner: Tom Ballard
