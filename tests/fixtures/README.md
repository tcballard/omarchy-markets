# Upgrade fixture

`v0.3.3-state.json` models a configured, paused v0.3.3 watchlist with non-default
values. Its cache was emitted by `scripts/fetch_quotes.py` from commit
`90ddf9b58708b3d9040cd7ca63cf82c4f992caa4`, using the existing fictional Yahoo
test response and fixed `now_epoch=1700000000`. No live market or user data is
included. The settings are representative values accepted by that version.

The current helper must still read this cache for explicitly stale fallback;
the current widget normalizer must preserve the settings through unrelated
changes, including disabled consent and stopped ticker motion.
