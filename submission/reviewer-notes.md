# Marketplace reviewer notes

- Plugin: Omarchy Markets 0.3.3
- Repository: `https://github.com/tcballard/omarchy-markets`
- Permanent community ID: `io.github.tcballard.omarchy-markets`
- Kinds: process-wide service and bar widget
- Runtime dependency: Python 3.10 or newer at `/usr/bin/python3`; standard library only
- Network destination: `https://query1.finance.yahoo.com/v8/finance/chart/<encoded-symbol>`
- Credentials: none
- Privilege or installer surface: none
- Persistent writes: bounded owner-only quote/history cache below `${XDG_CACHE_HOME:-~/.cache}/omarchy-markets/`
- Expected review capability: QML `Process` execution in `Service.qml` invokes the bundled fixed helper by argument array through `/usr/bin/python3`, without inherited-`PATH` interpreter resolution
- Local advisory security outcome: `review-required`, zero findings; QML process/input-collection capabilities and a negated privilege reference in `SECURITY.md`. The upstream baseline is a separate check.
- Current screenshot provenance: actual installed Omarchy 0.3.2 panel and profile chooser captured on 12 September 2026; public Yahoo Finance data, no account data or generated imagery. Exact source/display evidence and limitations are in `docs/acceptance.md`.
- Live acceptance owner: Tom Ballard

## v0.3.3 update

The original listing was approved in [#4216](https://github.com/omacom/omarchy-plugin-marketplace/issues/4216)
at `4a667dadfce52251ac4d897ac3f10fd5eaac3967`. Continue the existing update
request [#6586](https://github.com/omacom/omarchy-plugin-marketplace/issues/6586);
do not create a duplicate.

The earlier screenshot request targeted `35bd257947307497baa25892ce67f5eb053869c9`.
The maintainer blocked it because HEAD had advanced. This release also includes
the public-plugin-API fixes from `818c4ca6c454369d91084d11f94ac147cfea80e8`:

- `BarWidget.qml` looks up the quote service through public `serviceFor()`.
- `Service.qml` resolves its helper through `Qt.resolvedUrl`, decodes file URL
  escapes, rejects non-file URLs and still launches fixed `/usr/bin/python3`
  with structured arguments. Third-party lifecycle follows host mounting.
- Registry connections accept the public API's notification signals.
- `tests/plugin_api.test.js` checks those public bindings, late service lookup,
  escaped installation paths and non-file helper rejection. This is portable JS
  evidence, not live QML reactivity evidence.

The README now states normal-user permissions clearly. The previously reported
privilege capability came from prose saying the plugin never requests elevation;
no actual privileged execution was removed or concealed.

The release also adds documentation badges, an annotated tag and CI release
assets. `.github/workflows/release.yml` is maintainer release automation, not
plugin runtime: it tests the exact main commit, creates an immutable annotated
tag, stages a draft release, verifies downloaded assets and then publishes.
It runs only on main and uses a repository-scoped Actions token with contents
write permission. Existing published tags and release assets are never replaced.

Update #6586 to the final full release commit **after all changes land and CI
passes**, then hold main steady while review runs. Verification belongs to the
marketplace maintainer; a release or passing baseline is not approval.

The root images are the existing 0.3.2 captures. They do not demonstrate the
new startup fixes, fresh install/removal, multi-monitor behavior or complete
visual acceptance. See `docs/acceptance.md` for those limitations.
