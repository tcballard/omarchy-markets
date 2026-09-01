# Marketplace issue

Title: `[Plugin]: Omarchy Markets`

### Repository URL

https://github.com/tcballard/omarchy-markets

### Category

Widgets

### Tags

bar, quickshell

### Suggest a missing tag

finance

### Maintainer notes

Omarchy Markets is a macOS Stocks-style market glance for the Omarchy bar. It combines a scrolling ticker with a compact scanner, editable Crypto, Meme Coins and Magnificent Seven profiles, custom watchlists, pinning and five historical ranges.

Yahoo Finance access is consent-gated before the first network request and requires no API key. One shared bounded poller invokes the bundled standard-library Python helper against Yahoo Finance's fixed unofficial chart endpoint, with a private local last-known cache for stale and offline states.

The plugin has no accounts, trading, order execution, portfolio management or investment recommendations, and makes no real-time-data claim. The deterministic security baseline is expected to require manual review because `Service.qml` launches the bounded quote-fetching process; it reports zero findings. The root preview is the repository's clearly identified fictional fixture capture.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
