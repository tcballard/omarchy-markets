# Qt Quick smoke test

`./tests/qml/run` loads the shipped BarWidget (including its panel Loader),
Panel, WatchlistEditor, HistoryChart and Sparkline in Qt Quick Test. It renders
the chart offscreen and sends pointer/key events, checking point selection,
focus return, normal range navigation, settings reactivity and named lists.
Fictional data stays in process; the live provider service is not instantiated.
QML load failures and warnings fail the command.

On Ubuntu 24.04, install `qt6-declarative-dev-tools`, `qml6-module-qtquick`,
`qml6-module-qtquick-window`, `qml6-module-qtquick-controls`,
`qml6-module-qtquick-templates`, `qml6-module-qtquick-layouts`,
`qml6-module-qtqml`, `qml6-module-qtqml-models`, `qml6-module-qtqml-workerscript`
and `qml6-module-qttest`, then run the command.
Set `QMLTESTRUNNER` if the Qt 6 runner is at a different path. CI has a dedicated
`qml` job whose failures fail the Test workflow; portable checks remain runnable without Qt.

The separate `qml-qt612` job runs the identical suite on pinned Qt 6.12.0,
distributed by `PySide6-Essentials==6.12.0` and `shiboken6==6.12.0`.
`pyside-runner` invokes Qt Quick Test directly and rejects an unexpected runtime
version. Python is only the test launcher; it adds no plugin dependency.
To reproduce in an environment with those packages installed:

```bash
EXPECTED_QT_VERSION=6.12.0 QMLTESTRUNNER=./tests/qml/pyside-runner ./tests/qml/run
```

Both jobs are required to pass the workflow. Qt 6.12's QtQuick Color singleton
coexists with the host theme because production references use `Omarchy.Color`.

The small `imports/` stubs expose only the Omarchy/Quickshell interfaces used by
these components. They do not execute commands or contact a provider. Their
public API shape was checked against Omarchy
`754d2d04b3828ae5ccfff4c4ab9f0c3b5c14dc7b`; the key-dispatch and theme contracts
are test fixtures, not copied shell implementations.

This establishes real QML parsing, bindings, offscreen painting and the tested
interactions. It does not establish actual Omarchy imports, compositor popup
placement, desktop focus/dismissal, multi-monitor behavior or service lifecycle.
Keep the XPS acceptance checks in `docs/acceptance.md` separate.
