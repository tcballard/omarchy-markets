# Official install and capture checklist

The root images are actual screen captures from 12 September 2026. See
[`acceptance.md`](acceptance.md#capture-record-12-september-2026) for the source
revision, display, commands, and observed limitations. Use this checklist for
future captures and broader lifecycle acceptance.

## Install the candidate

```bash
omarchy plugin add https://github.com/tcballard/omarchy-markets.git --enable
omarchy plugin validate ~/.config/omarchy/plugins/io.github.tcballard.omarchy-markets
```

If Omarchy reports a different installed checkout path, validate that exact path. Record the plugin commit and Omarchy commit before testing:

```bash
git -C ~/.config/omarchy/plugins/io.github.tcballard.omarchy-markets rev-parse HEAD
git -C "$OMARCHY_PATH" rev-parse HEAD
```

## Exercise the release flow

1. Open the widget before setup and confirm no quote helper or Yahoo request starts.
2. Choose **Magnificent 7** to enable market data explicitly.
3. Confirm the horizontal bar starts as a scrolling ticker.
4. Open the panel and inspect several rows without changing the pinned bar symbol.
5. Switch through 1D, 5D, 1M, 6M, and 1Y.
6. Pin a different symbol, add and remove a symbol, then restart the shell and confirm settings persist.
7. Right-click the ticker to pause it and middle-click to refresh.
8. Disconnect networking and confirm cached or stale data is labelled rather than displayed as fresh.
9. Remove the plugin and confirm polling stops.

## Capture the marketplace image

Use a clean workspace and a watchlist without private data. Open the normal panel with the ticker visible, select a row with a populated chart, and capture only the bar plus panel:

```bash
omarchy capture screenshot region save
```

The marketplace accepts one root preview under 50 MB and 40 megapixels. Crop tightly, keep text readable, remove unrelated notifications or windows, and replace `preview.png` without resizing it merely to meet a marketing template.

Also capture the profile chooser and keep it as `preview-profiles.png` for the README. Do not present either image as release evidence until the commit, Omarchy revision, display scaling, and observed state have been recorded in `docs/acceptance.md`.
