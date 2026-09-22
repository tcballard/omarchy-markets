from __future__ import annotations

import json
import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PLUGIN_ID = "io.github.tcballard.omarchy-markets"
QML_FILES = [
    ROOT / "BarWidget.qml",
    ROOT / "Panel.qml",
    ROOT / "Service.qml",
    ROOT / "Sparkline.qml",
]


def strip_strings_and_comments(source: str) -> str:
    """Remove lexical noise before simple delimiter checks.

    This is intentionally not presented as a QML parser. It catches accidental
    truncation and brace damage portably; live Omarchy/qmllint remains the
    authoritative runtime layer.
    """

    output: list[str] = []
    index = 0
    state = "code"
    quote = ""
    while index < len(source):
        char = source[index]
        following = source[index + 1] if index + 1 < len(source) else ""
        if state == "code":
            if char in {'"', "'"}:
                state = "string"
                quote = char
                output.append(" ")
            elif char == "/" and following == "/":
                state = "line-comment"
                output.extend("  ")
                index += 1
            elif char == "/" and following == "*":
                state = "block-comment"
                output.extend("  ")
                index += 1
            else:
                output.append(char)
        elif state == "string":
            output.append("\n" if char == "\n" else " ")
            if char == "\\" and following:
                output.append(" ")
                index += 1
            elif char == quote:
                state = "code"
        elif state == "line-comment":
            if char == "\n":
                state = "code"
                output.append("\n")
            else:
                output.append(" ")
        else:
            output.append("\n" if char == "\n" else " ")
            if char == "*" and following == "/":
                output.append(" ")
                index += 1
                state = "code"
        index += 1
    if state in {"string", "block-comment"}:
        raise AssertionError(f"unterminated {state}")
    return "".join(output)


def assert_balanced(test: unittest.TestCase, path: pathlib.Path) -> None:
    source = strip_strings_and_comments(path.read_text(encoding="utf-8"))
    pairs = {")": "(", "]": "[", "}": "{"}
    stack: list[tuple[str, int]] = []
    for position, char in enumerate(source):
        if char in "([{":
            stack.append((char, position))
        elif char in pairs:
            test.assertTrue(stack, f"{path.name}: unexpected {char} at {position}")
            opening, opening_position = stack.pop()
            test.assertEqual(
                opening,
                pairs[char],
                f"{path.name}: {opening} at {opening_position} closed by {char}",
            )
    test.assertEqual(stack, [], f"{path.name}: unclosed delimiters {stack[-3:]}")


class QmlSourceContractTests(unittest.TestCase):
    def test_qml_sources_are_balanced(self) -> None:
        for path in QML_FILES:
            with self.subTest(path=path.name):
                assert_balanced(self, path)

    def test_entry_points_exist_and_use_hosted_items(self) -> None:
        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        for entry_point in manifest["entryPoints"].values():
            self.assertTrue((ROOT / entry_point).is_file())
        combined = "\n".join(path.read_text(encoding="utf-8") for path in QML_FILES)
        self.assertNotRegex(combined, r"\bShellRoot\s*\{")

    def test_canonical_id_is_consistent(self) -> None:
        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["id"], PLUGIN_ID)
        self.assertIn(f'moduleName: "{PLUGIN_ID}"', (ROOT / "BarWidget.qml").read_text())
        self.assertIn(f'target: "{PLUGIN_ID}"', (ROOT / "Service.qml").read_text())
        self.assertNotIn("omarchy.", manifest["id"])

    def test_scan_first_defaults_are_release_contract(self) -> None:
        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        defaults = manifest["barWidget"]["defaults"]
        self.assertEqual(defaults["barMode"], "ticker")
        self.assertEqual(defaults["tickerWidth"], 220)
        source = (ROOT / "Panel.qml").read_text(encoding="utf-8")
        self.assertIn("id: marketToolbar", source)
        self.assertIn("readonly property int rowHeight: Style.space(44)", source)
        self.assertIn("PanelSeparator { foreground: root.foreground }", source)

    def test_panel_fits_host_insets_and_scrolls_overflow(self) -> None:
        source = (ROOT / "Panel.qml").read_text(encoding="utf-8")
        self.assertIn("centerOnBar: false", source)
        self.assertIn("contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)", source)
        self.assertIn("ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }", source)
        self.assertIn("interactive: contentHeight > height", source)
        self.assertIn("clip: true", source)
        self.assertIn("Qt.callLater(function() { keyCatcher.forceActiveFocus() })", source)
        self.assertIn('text: "STARTING PROFILES"', source)
        self.assertIn('text: "▲"', source)
        self.assertIn('text: "▼"', source)
        self.assertIn('text: "Keyboard: ↑/↓ select · [/] reorder · P pin · X/Delete remove · A add · M back"', source)

    def test_widget_has_private_popout_contract(self) -> None:
        source = (ROOT / "BarWidget.qml").read_text(encoding="utf-8")
        for token in [
            'source: Qt.resolvedUrl("Panel.qml")',
            "readonly property bool opened:",
            "function open()",
            "function close()",
            "function closeForPopoutSwitch()",
        ]:
            self.assertIn(token, source)

    def test_service_uses_direct_argv_and_bounds_requests(self) -> None:
        source = (ROOT / "Service.qml").read_text(encoding="utf-8")
        self.assertIn('readonly property string pythonInterpreterPath: "/usr/bin/python3"', source)
        self.assertEqual(source.count("var command = helperCommand(["), 2)
        self.assertNotIn('"/usr/bin/env", "python3"', source)
        self.assertNotIn('Quickshell.env("PATH")', source)
        self.assertNotRegex(source, r'["\'](?:ba)?sh["\']\s*,\s*["\']-c')
        self.assertIn("requestWatchdog", source)
        helper = (ROOT / "scripts" / "fetch_quotes.py").read_text(encoding="utf-8")
        self.assertIn("MAX_SYMBOLS = 12", helper)
        self.assertIn("MAX_RESPONSE_BYTES", helper)

    def test_all_display_text_is_plain_text(self) -> None:
        for path in [ROOT / "BarWidget.qml", ROOT / "Panel.qml"]:
            source = path.read_text(encoding="utf-8")
            text_blocks = len(re.findall(r"\bText\s*\{", source))
            plain_blocks = len(re.findall(r"textFormat:\s*Text\.PlainText", source))
            self.assertEqual(text_blocks, plain_blocks, path.name)

    def test_accessible_buttons_expose_press_actions(self) -> None:
        bar_source = (ROOT / "BarWidget.qml").read_text(encoding="utf-8")
        panel_source = (ROOT / "Panel.qml").read_text(encoding="utf-8")
        self.assertIn("Accessible.onPressAction: root.togglePanel()", bar_source)
        for action in [
            "root.refresh()",
            "root.openFocusedQuote()",
            "root.inspectSymbol(quoteRow.modelData, quoteRow.index)",
            "root.pinFocused()",
            "root.startCustom()",
            "root.addEnteredSymbol()",
            "root.chooseProfile(profileCard.modelData.id)",
        ]:
            self.assertIn(f"Accessible.onPressAction: {action}", panel_source)

    def test_panel_manages_watchlists_without_opening_raw_configuration(self) -> None:
        source = (ROOT / "Panel.qml").read_text(encoding="utf-8")
        self.assertNotIn("shell.json", source)
        self.assertNotIn("omarchy-launch-config-editor", source)
        for token in [
            "hostWidget.addSymbol",
            "hostWidget.removeSymbol",
            "hostWidget.moveSymbol",
            "hostWidget.applyProfile",
            "hostWidget.setPrimarySymbol",
            "service.requestHistory",
        ]:
            self.assertIn(token, source)

    def test_setup_is_consent_gated_and_profiles_are_visible(self) -> None:
        panel_source = (ROOT / "Panel.qml").read_text(encoding="utf-8")
        bar_source = (ROOT / "BarWidget.qml").read_text(encoding="utf-8")
        self.assertIn("readonly property bool setupRequired: !dataEnabled", panel_source)
        self.assertIn("MarketModel.profiles()", panel_source)
        self.assertIn("Market data is off", panel_source)
        self.assertIn('setting("dataEnabled", false) === true', bar_source)

    def test_panel_wires_time_aware_charts_and_keyboard_modes(self) -> None:
        panel_source = (ROOT / "Panel.qml").read_text(encoding="utf-8")
        sparkline_source = (ROOT / "Sparkline.qml").read_text(encoding="utf-8")
        self.assertIn("sparklineTimestamps", panel_source)
        self.assertNotIn("quote.timestamps", panel_source)
        self.assertIn("blocked: symbolInput.activeFocus", panel_source)
        for token in [
            "function activateCurrent()",
            "function managerShortcut(text)",
            "function moveRange(delta)",
            "onDeleteRequested:",
            "Keys.onEscapePressed",
            "Keys.onTabPressed",
        ]:
            self.assertIn(token, panel_source)
        self.assertIn("minimum = Math.min(minimum, referenceValue)", sparkline_source)


if __name__ == "__main__":
    unittest.main()
