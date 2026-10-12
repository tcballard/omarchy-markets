# Developing and releasing Markets

The v0.5.0 candidate adds named watchlists, persistent viewing preferences and
pointer/keyboard chart inspection. The existing v0.4.0 list becomes the initial
named list without changing its symbols, order, pin or market-data consent.
See [v0.5.0 testing and rollback](releases/v0.5.0-testing.md).
The target is **x86_64 Linux on Omarchy Quattro**, with system Python 3.10+.
ARM64 and other architectures are not claimed as tested.

## Portable checks

```bash
./tests/run
git diff --check
```

Tests execute the real helper command with hostile Python startup variables,
reject a FIFO without blocking, exercise file privacy and history eviction,
and check legacy settings/cache fixtures. Named-watchlist regressions exercise
legacy migration, persistence, isolated edits, limits, consent and selection.
QML JavaScript probes cover secondary text contrast and keyboard scrolling.
The separate `./tests/qml/run` suite renders shipped components with host stubs;
CI runs it on distribution Qt and pinned Qt 6.12.0. These checks do not establish
real Omarchy imports, compositor behaviour or live process cleanup.

The panel sizing follows Omarchy's `KeyboardPanel.fittedContentHeight` and the
weather panel's clipped, overflow-only `Flickable`, inspected at upstream
`947e2fc002d6831c7888b29b5761d59d29e69727`. Process environment properties follow
[Quickshell's Process API](https://quickshell.org/docs/v0.2.1/types/Quickshell.Io/Process/).
These are implementation references, not a claim that this plugin ran on that host.

## Required host checks

Run on the intended release commit after the PR is merged. Record the full
plugin SHA (`git rev-parse HEAD` in its checkout), full Omarchy SHA, architecture
(`uname -m`), date, display scale, themes, commands and results. Preserve the
user's shell configuration when testing fresh install/removal.

| Check | Passing result |
| --- | --- |
| Fresh install and consent | The panel opens; no market request before choosing a profile or enabling a custom watchlist. |
| Update from v0.4.0 | Symbols, order, pin, chart range, refresh, pause and consent are preserved; named-list edits and viewing preferences survive restart. |
| Quotes and history | Profiles, named-list creation/copy/rename/deletion/switching, add/remove/reorder/pin, sorting, refresh, chart inspection and all five ranges work. |
| Panel scrolling, focus and dismissal | All setup and populated content stays inside the border; wheel/trackpad/scrollbar reach the bottom; keyboard selection follows; Escape, outside click and Tab work; rapid reopen keeps focus. |
| Themes and scaling | Popup text remains readable in light/dark themes and at the intended scale; test a short viewport and a full watchlist. |
| Bar orientation | Horizontal ticker/single mode and a vertical bar remain usable. |
| Offline and recovery | Cached values are labelled; restoring connectivity, terminating a helper and suspend/resume recover without stuck Loading or orphan workers. |
| Reload, disable and removal | Shell reload/restart and disable/re-enable recover; removal stops helper processes and polling. Optional cache is the only plugin-owned residue. |

Record multi-monitor results separately if available, including mixed scale.
A single-screen pass does not establish multi-monitor acceptance. First-party
upstream-port checks are outside this third-party release's support claim.
See [the acceptance matrix](acceptance.md) for historical evidence and unrun cases.

## Publication

On pull requests, the Test workflow packages the exact tested merge commit only
after `workflows`, `portable`, `qml` and `qml-qt612` pass. The
`markets-candidate-<full SHA>` download includes the source archive, source and
release manifests, SBOM and checksums. It is for testing: it has no host
acceptance record, tag or public release. A PR update invalidates earlier
candidate evidence. On main the same job packages that main commit.

Merging a manifest change runs portable validation and stages source assets as
a GitHub Actions artifact. **It does not create a tag or publish a release.**

After the required host checks pass, run the **Release** workflow on `main`:

First record acceptance and the current preview provenance, replace the
v0.5.0 preparation notices with the observed release state, and date the
changelog. Carry the test record to the final merged SHA, rerun affected checks
and wait for all four Test jobs plus candidate packaging. The Release workflow
itself reruns portable checks, not the Qt smoke jobs.

- Set `publish` and `host_checks_passed` to true.
- Supply the exact tested plugin and Omarchy commit SHAs and `x86_64`.
- Put the observed results, display/theme details and any remaining limitations
  in `host_notes`. This records the operator's attestation, not automated host testing.

The workflow rejects missing acceptance or a plugin SHA different from its
source. It reruns portable checks, creates the annotated version tag, uploads
and verifies draft assets, then publishes. Existing tags are never moved.
`HOST-ACCEPTANCE.json` ships with the release and is covered by its manifest
and checksums. No user input is interpolated into shell source.

If source changes after testing, re-test the affected behavior and record
acceptance against the new complete SHA. If publication fails after tagging,
rerun only for that same source; fix source under a new version when a published
tag already exists. Marketplace snapshot verification remains a separate step.
