# Omarchy Markets acceptance matrix

Portable tests are automated. The live rows must be completed on the target
Omarchy revision before a release is described as visually or operationally
verified.

| Surface or lifecycle | Portable | Live Omarchy |
| --- | --- | --- |
| Manifest, paths, limits, security patterns | Automated | Reconcile with `omarchy plugin validate` |
| Profile catalog and watchlist mutations | Automated | Profile selection persists |
| Provider parsing, ranges, cache and fallback | Automated fixtures | Fixed-host network smoke test |
| Quote/history process lifecycle and watchdogs | Automated state tests | Kill/restart/suspend recovery |
| Loading, ready, partial, stale, cached, offline | Automated source/fixture checks | Inspect every rendered state |
| Setup consent and disabled/no-poll state | Automated source/state checks | Verify with process/network observation |
| Horizontal single and ticker bar modes | Source checks | Inspect top/bottom bar |
| Vertical bar | Source checks | Inspect left/right bar |
| Panel focus, outside close, Escape and Tab | Source checks | Keyboard/pointer smoke test |
| Add, remove, reorder, inspect and pin | Model/source checks | Keyboard and pointer smoke test |
| Ranges, stats and selected-only history | Model/provider checks | Inspect all five ranges |
| Themes, text scaling and translucent bar | Contrast/model checks | Light/dark themes and scaling |
| Multi-monitor singleton | Lifecycle/source checks | Two monitors, mixed scale |
| Reload, shell restart, disable/re-enable | State tests | Live lifecycle |
| First-party removed-from-bar polling gate | State/source checks | Upstream-port acceptance |
| Remove without credentials or daemon residue | Documentation check | Fresh checkout install/remove |

Record the date, plugin SHA, Omarchy SHA, monitor/scaling details, commands,
screenshots, and failures. A generated preview is not live-shell evidence.
