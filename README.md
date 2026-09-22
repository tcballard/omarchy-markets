<h1 align="center">Omarchy Markets</h1>

<p align="center">
  <a href="https://github.com/tcballard/omarchy-badges"><img src="https://raw.githubusercontent.com/tcballard/omarchy-badges/75975e5b5bf75e7ede3764bcd2950046f7abfe2c/badges/v1/omarchy-plugin.svg" alt="Built for Omarchy: Plugin" height="24"></a>
</p>

**Your watchlist, in the Omarchy bar.**

Follow stocks, indices and crypto without keeping a finance tab open. Scan the ticker, compare quotes in the panel and inspect five price-history ranges. Start with an editable profile or build your own watchlist.

![Omarchy Markets on Omarchy, showing the watchlist and selected price history](preview.png)

Live Omarchy capture from 12 September 2026. [Capture record](docs/acceptance.md#capture-record-12-september-2026).

## Everyday use

Click the ticker and choose a profile to begin. Pin an instrument to the bar, change the chart range or open **Manage** to edit your watchlist. You can pause ticker motion or turn it off. [Profiles and controls →](GUIDE.md#start-with-a-profile)

## Install

Omarchy 4 / Quattro with plugin support and Python 3.10+ at `/usr/bin/python3`. No extra Python packages, account or API key.

```bash
omarchy plugin add https://github.com/tcballard/omarchy-markets.git --enable
```

## Update and remove

Update:

```bash
omarchy plugin update io.github.tcballard.omarchy-markets
```

Remove:

```bash
omarchy plugin remove io.github.tcballard.omarchy-markets
```

## A few useful details

Quotes use Yahoo Finance’s unofficial endpoint and may be delayed. Network requests start only after you choose a profile or enable a watchlist. Cached values are labelled stale when a refresh fails. [Data and privacy →](GUIDE.md#data-cache-and-privacy)

[Marketplace listing](https://plugins.omarchy.org/plugin.html?id=io.github.tcballard.omarchy-markets) · [Releases](https://github.com/tcballard/omarchy-markets/releases) · [Review and verification scope](GUIDE.md#release-and-marketplace-status)

Upgrading from Market Watch 0.1? Follow the [migration steps](GUIDE.md#upgrade-from-market-watch-01). Removal preserves the optional local cache.

[Usage and development guide](GUIDE.md) · [Report a bug](https://github.com/tcballard/omarchy-markets/issues)

[MIT licensed](LICENSE).

<!-- Preserve links to sections now in the guide. -->
<a id="acknowledgements"></a>
<a id="data-cache-and-privacy"></a>
<a id="development-and-validation"></a>
<a id="license"></a>
<a id="release-and-marketplace-status"></a>
<a id="remove"></a>
<a id="requirements-and-trust-boundary"></a>
<a id="start-with-a-profile"></a>
<a id="support"></a>
<a id="upgrade-from-market-watch-01"></a>
<a id="use"></a>
<a id="what-it-does"></a>

[Looking for the previous detailed sections? Open the full guide →](GUIDE.md)
