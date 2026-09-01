#!/usr/bin/env python3
"""Portable unit tests for the standard-library quote helper."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import math
import pathlib
import socket
import stat
import sys
import tempfile
import unittest
import urllib.error


ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "fetch_quotes", ROOT / "scripts" / "fetch_quotes.py"
)
assert SPEC is not None and SPEC.loader is not None
fetch_quotes = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = fetch_quotes
SPEC.loader.exec_module(fetch_quotes)


def yahoo_payload(
    symbol: str = "AAPL",
    *,
    price: float = 102.0,
    previous: float = 100.0,
    closes: list[float | None] | None = None,
    timestamps: list[int | float | None] | None = None,
    meta: dict | None = None,
) -> dict:
    normalized_meta = {
        "symbol": symbol,
        "shortName": "Example Incorporated",
        "currency": "USD",
        "regularMarketPrice": price,
        "chartPreviousClose": previous,
        "regularMarketTime": 1_700_000_000,
    }
    if meta:
        normalized_meta.update(meta)
    result = {
        "meta": normalized_meta,
        "indicators": {
            "quote": [{"close": closes or [100.0, None, 101.0, price]}]
        },
    }
    if timestamps is not None:
        result["timestamp"] = timestamps
    return {
        "chart": {
            "result": [result],
            "error": None,
        }
    }


class FakeResponse:
    def __init__(self, body: bytes, headers: dict[str, str] | None = None):
        self.body = body
        self.headers = headers or {}
        self.read_amounts: list[int] = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback):
        return False

    def read(self, amount: int = -1) -> bytes:
        self.read_amounts.append(amount)
        return self.body if amount < 0 else self.body[:amount]


class SymbolTests(unittest.TestCase):
    def test_familiar_yahoo_symbols_are_normalized_and_deduplicated(self):
        symbols, errors = fetch_quotes.normalize_symbols(
            [" aapl ", "^ftse", "BTC-USD", "GBPUSD=X", "aapl"]
        )
        self.assertEqual(symbols, ["AAPL", "^FTSE", "BTC-USD", "GBPUSD=X"])
        self.assertEqual(errors, [])

    def test_invalid_symbol_is_a_bounded_partial_error(self):
        symbols, errors = fetch_quotes.normalize_symbols(
            ["AAPL", "../../etc/passwd", "^^", "="]
        )
        self.assertEqual(symbols, ["AAPL"])
        self.assertEqual(
            [error["code"] for error in errors],
            ["invalid_symbol", "invalid_symbol", "invalid_symbol"],
        )
        self.assertLessEqual(
            len(errors[0]["message"]), fetch_quotes.MAX_ERROR_MESSAGE_LENGTH
        )

    def test_more_than_twelve_inputs_are_rejected_before_io(self):
        with self.assertRaises(fetch_quotes.InputLimitError):
            fetch_quotes.normalize_symbols([f"SYM{i}" for i in range(13)])

    def test_url_path_quotes_reserved_symbol_characters(self):
        index_url = fetch_quotes.build_chart_url("^GSPC")
        forex_url = fetch_quotes.build_chart_url("GBPUSD=X")
        plus_url = fetch_quotes.build_chart_url("TEST+A")
        self.assertIn("/chart/%5EGSPC?", index_url)
        self.assertIn("/chart/GBPUSD%3DX?", forex_url)
        self.assertIn("/chart/TEST%2BA?", plus_url)
        self.assertTrue(index_url.startswith("https://query1.finance.yahoo.com/"))

    def test_supported_ranges_map_to_bounded_yahoo_intervals(self):
        expected = {
            "1d": "5m",
            "5d": "15m",
            "1mo": "1d",
            "6mo": "1d",
            "1y": "1wk",
        }
        for chart_range, interval in expected.items():
            with self.subTest(chart_range=chart_range):
                parsed = fetch_quotes.urllib.parse.urlsplit(
                    fetch_quotes.build_chart_url("AAPL", chart_range)
                )
                query = fetch_quotes.urllib.parse.parse_qs(parsed.query)
                self.assertEqual(query["range"], [chart_range])
                self.assertEqual(query["interval"], [interval])
                self.assertEqual(query["includePrePost"], ["false"])

    def test_invalid_range_never_builds_a_provider_url(self):
        with self.assertRaises(fetch_quotes.FetchFailure) as caught:
            fetch_quotes.build_chart_url("AAPL", "2y")
        self.assertEqual(caught.exception.code, "invalid_range")


class ParserTests(unittest.TestCase):
    def test_yahoo_response_is_reduced_to_exact_quote_schema(self):
        quote = fetch_quotes.parse_yahoo_chart(yahoo_payload(), "AAPL")
        self.assertEqual(
            set(quote),
            {
                "symbol",
                "name",
                "currency",
                "exchange",
                "exchangeTimezone",
                "instrumentType",
                "marketState",
                "sessionState",
                "regularMarketPrice",
                "previousClose",
                "change",
                "changePercent",
                "marketTime",
                "regularMarketOpen",
                "dayLow",
                "dayHigh",
                "fiftyTwoWeekLow",
                "fiftyTwoWeekHigh",
                "volume",
                "sparkline",
                "sparklineTimestamps",
                "range",
            },
        )
        self.assertEqual(quote["symbol"], "AAPL")
        self.assertEqual(quote["name"], "Example Incorporated")
        self.assertEqual(quote["regularMarketPrice"], 102.0)
        self.assertEqual(quote["change"], 2.0)
        self.assertEqual(quote["changePercent"], 2.0)
        self.assertEqual(quote["marketTime"], "2023-11-14T22:13:20Z")
        self.assertEqual(quote["sparkline"], [100.0, 101.0, 102.0])
        self.assertEqual(quote["sparklineTimestamps"], [])
        self.assertEqual(quote["sessionState"], "unknown")
        self.assertEqual(quote["range"], "1d")

    def test_missing_values_remain_null_and_name_falls_back_to_symbol(self):
        payload = {
            "chart": {
                "result": [
                    {
                        "meta": {},
                        "indicators": {"quote": [{"close": [None, 12.5]}]},
                    }
                ],
                "error": None,
            }
        }
        quote = fetch_quotes.parse_yahoo_chart(payload, "ACME")
        self.assertEqual(quote["name"], "ACME")
        self.assertEqual(quote["regularMarketPrice"], 12.5)
        self.assertIsNone(quote["previousClose"])
        self.assertIsNone(quote["change"])
        self.assertIsNone(quote["changePercent"])
        self.assertIsNone(quote["currency"])
        self.assertIsNone(quote["marketTime"])

    def test_metadata_stats_and_aligned_timestamps_are_normalized(self):
        payload = yahoo_payload(
            closes=[100.0, None, 101.0, 102.0],
            timestamps=[10, 20, 30, 40],
            meta={
                "fullExchangeName": "Nasdaq Global Select Market",
                "exchangeTimezoneName": "America/New_York",
                "instrumentType": "EQUITY",
                "regularMarketOpen": 100.5,
                "regularMarketDayLow": 99.75,
                "regularMarketDayHigh": 103.25,
                "fiftyTwoWeekLow": 80.0,
                "fiftyTwoWeekHigh": 120.0,
                "regularMarketVolume": 12_345_678,
                "currentTradingPeriod": {
                    "pre": {"start": 50, "end": 100},
                    "regular": {"start": 100, "end": 200},
                    "post": {"start": 200, "end": 250},
                },
            },
        )
        quote = fetch_quotes.parse_yahoo_chart(
            payload, "AAPL", chart_range="5d", now_epoch=150
        )
        self.assertEqual(quote["exchange"], "Nasdaq Global Select Market")
        self.assertEqual(quote["exchangeTimezone"], "America/New_York")
        self.assertEqual(quote["instrumentType"], "EQUITY")
        self.assertEqual(quote["marketState"], "regular")
        self.assertEqual(quote["sessionState"], "regular")
        self.assertEqual(quote["regularMarketOpen"], 100.5)
        self.assertEqual(quote["dayLow"], 99.75)
        self.assertEqual(quote["dayHigh"], 103.25)
        self.assertEqual(quote["fiftyTwoWeekLow"], 80.0)
        self.assertEqual(quote["fiftyTwoWeekHigh"], 120.0)
        self.assertEqual(quote["volume"], 12_345_678)
        self.assertEqual(quote["sparkline"], [100.0, 101.0, 102.0])
        self.assertEqual(quote["sparklineTimestamps"], [10, 30, 40])
        self.assertEqual(quote["range"], "5d")

    def test_session_state_covers_pre_regular_post_and_closed(self):
        periods = {
            "pre": {"start": 10, "end": 20},
            "regular": {"start": 20, "end": 30},
            "post": {"start": 30, "end": 40},
        }
        for now_epoch, expected in ((15, "pre"), (25, "regular"), (35, "post"), (50, "closed")):
            with self.subTest(expected=expected):
                quote = fetch_quotes.parse_yahoo_chart(
                    yahoo_payload(meta={"currentTradingPeriod": periods}),
                    "AAPL",
                    now_epoch=now_epoch,
                )
                self.assertEqual(quote["marketState"], expected)
                self.assertEqual(quote["sessionState"], expected)

    def test_crypto_is_continuous_and_provider_state_is_a_safe_fallback(self):
        crypto = fetch_quotes.parse_yahoo_chart(
            yahoo_payload(
                symbol="BTC-USD",
                meta={
                    "instrumentType": "CRYPTOCURRENCY",
                    "currentTradingPeriod": {
                        "regular": {"start": 1, "end": 2}
                    },
                },
            ),
            "BTC-USD",
            now_epoch=99,
        )
        self.assertEqual(crypto["sessionState"], "continuous")

        post = fetch_quotes.parse_yahoo_chart(
            yahoo_payload(meta={"marketState": "POSTPOST"}),
            "AAPL",
            now_epoch=99,
        )
        self.assertEqual(post["sessionState"], "post")

    def test_untrustworthy_timestamps_are_omitted_without_losing_prices(self):
        quote = fetch_quotes.parse_yahoo_chart(
            yahoo_payload(
                closes=[100.0, 101.0, 102.0],
                timestamps=[10, None, 30],
            ),
            "AAPL",
        )
        self.assertEqual(quote["sparkline"], [100.0, 101.0, 102.0])
        self.assertEqual(quote["sparklineTimestamps"], [])

    def test_sparkline_is_numeric_finite_and_capped_at_78_points(self):
        closes = list(range(200)) + [None, math.nan, math.inf]
        timestamps = list(range(len(closes)))
        quote = fetch_quotes.parse_yahoo_chart(
            yahoo_payload(closes=closes, timestamps=timestamps), "AAPL"
        )
        self.assertEqual(len(quote["sparkline"]), 78)
        self.assertEqual(quote["sparkline"][0], 0)
        self.assertEqual(quote["sparkline"][-1], 199)
        self.assertEqual(len(quote["sparklineTimestamps"]), 78)
        self.assertEqual(quote["sparklineTimestamps"][0], 0)
        self.assertEqual(quote["sparklineTimestamps"][-1], 199)
        self.assertTrue(all(math.isfinite(value) for value in quote["sparkline"]))

    def test_extreme_numbers_cannot_emit_non_finite_json_values(self):
        quote = fetch_quotes.parse_yahoo_chart(
            yahoo_payload(price=1e308, previous=-1e308), "AAPL"
        )
        self.assertIsNone(quote["change"])
        self.assertIsNone(quote["changePercent"])
        # The complete normalized quote remains strict JSON.
        json.dumps(quote, allow_nan=False)

    def test_provider_error_is_controlled_and_bounded(self):
        payload = {
            "chart": {
                "result": None,
                "error": {"description": "x" * 1000},
            }
        }
        with self.assertRaises(fetch_quotes.FetchFailure) as caught:
            fetch_quotes.parse_yahoo_chart(payload, "AAPL")
        self.assertEqual(caught.exception.code, "provider_error")
        self.assertLessEqual(
            len(fetch_quotes.make_error("AAPL", caught.exception.code, caught.exception.message)["message"]),
            fetch_quotes.MAX_ERROR_MESSAGE_LENGTH,
        )

    def test_provider_cannot_bind_another_symbol_to_the_requested_row(self):
        with self.assertRaises(fetch_quotes.FetchFailure) as caught:
            fetch_quotes.parse_yahoo_chart(yahoo_payload(symbol="MSFT"), "AAPL")
        self.assertEqual(caught.exception.code, "symbol_mismatch")

    def test_chart_without_a_finite_price_is_rejected(self):
        payload = yahoo_payload(price=None, closes=[None])
        with self.assertRaises(fetch_quotes.FetchFailure) as caught:
            fetch_quotes.parse_yahoo_chart(payload, "AAPL")
        self.assertEqual(caught.exception.code, "quote_unavailable")


class NetworkTests(unittest.TestCase):
    def test_redirects_cannot_leave_the_fixed_https_host(self):
        request = fetch_quotes.urllib.request.Request(
            "https://query1.finance.yahoo.com/v8/finance/chart/AAPL"
        )
        handler = fetch_quotes.FixedHostRedirectHandler()
        with self.assertRaises(fetch_quotes.FetchFailure) as caught:
            handler.redirect_request(
                request,
                None,
                302,
                "Found",
                {},
                "https://example.invalid/collect",
            )
        self.assertEqual(caught.exception.code, "unsafe_redirect")

    def test_redirects_cannot_change_the_fixed_https_port(self):
        request = fetch_quotes.urllib.request.Request(
            "https://query1.finance.yahoo.com/v8/finance/chart/AAPL"
        )
        handler = fetch_quotes.FixedHostRedirectHandler()
        with self.assertRaises(fetch_quotes.FetchFailure) as caught:
            handler.redirect_request(
                request,
                None,
                302,
                "Found",
                {},
                "https://query1.finance.yahoo.com:8443/v8/finance/chart/AAPL",
            )
        self.assertEqual(caught.exception.code, "unsafe_redirect")

    def test_fetch_uses_get_headers_timeout_and_bounded_read(self):
        response = FakeResponse(json.dumps(yahoo_payload()).encode())
        observed = {}

        def opener(request, timeout):
            observed["request"] = request
            observed["timeout"] = timeout
            return response

        quote = fetch_quotes.fetch_quote("AAPL", timeout=1.25, opener=opener)
        self.assertEqual(quote["symbol"], "AAPL")
        self.assertEqual(observed["timeout"], 1.25)
        self.assertEqual(observed["request"].method, "GET")
        self.assertEqual(observed["request"].get_header("Accept"), "application/json")
        self.assertIn("Omarchy-Markets", observed["request"].get_header("User-agent"))
        self.assertEqual(response.read_amounts, [fetch_quotes.MAX_RESPONSE_BYTES + 1])

    def test_fetch_forwards_requested_range_and_parses_it(self):
        response = FakeResponse(json.dumps(yahoo_payload()).encode())
        observed = {}

        def opener(request, timeout):
            observed["url"] = request.full_url
            return response

        quote = fetch_quotes.fetch_quote(
            "AAPL", opener=opener, chart_range="1y", now_epoch=1_700_000_000
        )
        query = fetch_quotes.urllib.parse.parse_qs(
            fetch_quotes.urllib.parse.urlsplit(observed["url"]).query
        )
        self.assertEqual(query["range"], ["1y"])
        self.assertEqual(query["interval"], ["1wk"])
        self.assertEqual(quote["range"], "1y")

    def test_declared_oversized_response_is_rejected_without_reading(self):
        response = FakeResponse(
            b"{}", {"Content-Length": str(fetch_quotes.MAX_RESPONSE_BYTES + 1)}
        )
        with self.assertRaises(fetch_quotes.FetchFailure) as caught:
            fetch_quotes.fetch_quote("AAPL", opener=lambda *args, **kwargs: response)
        self.assertEqual(caught.exception.code, "response_too_large")
        self.assertEqual(response.read_amounts, [])

    def test_actual_oversized_response_is_rejected(self):
        response = FakeResponse(b"x" * (fetch_quotes.MAX_RESPONSE_BYTES + 1))
        with self.assertRaises(fetch_quotes.FetchFailure) as caught:
            fetch_quotes.fetch_quote("AAPL", opener=lambda *args, **kwargs: response)
        self.assertEqual(caught.exception.code, "response_too_large")

    def test_timeout_and_http_failures_have_stable_codes(self):
        for failure, expected in (
            (socket.timeout(), "timeout"),
            (
                urllib.error.HTTPError(
                    "https://example.invalid", 429, "rate limited", {}, None
                ),
                "http_error",
            ),
            (urllib.error.URLError("offline"), "network_error"),
        ):
            with self.subTest(expected=expected):
                def opener(*args, _failure=failure, **kwargs):
                    raise _failure

                with self.assertRaises(fetch_quotes.FetchFailure) as caught:
                    fetch_quotes.fetch_quote("AAPL", opener=opener)
                self.assertEqual(caught.exception.code, expected)

    def test_partial_fetch_preserves_success_and_per_symbol_error(self):
        good = FakeResponse(json.dumps(yahoo_payload()).encode())

        def opener(request, timeout):
            if "MSFT" in request.full_url:
                raise socket.timeout()
            return good

        document = fetch_quotes.fetch_quotes(["AAPL", "MSFT"], opener=opener)
        self.assertEqual(document["status"], "partial")
        self.assertEqual([quote["symbol"] for quote in document["quotes"]], ["AAPL"])
        self.assertEqual(document["errors"][0]["symbol"], "MSFT")
        self.assertEqual(document["errors"][0]["code"], "timeout")

    def test_longer_range_rejects_zero_or_multiple_symbols_without_io(self):
        calls = []

        def opener(*args, **kwargs):
            calls.append(args)
            raise AssertionError("provider I/O must not run")

        for symbols in ([], ["AAPL", "MSFT"]):
            with self.subTest(symbols=symbols):
                document = fetch_quotes.fetch_quotes(
                    symbols, opener=opener, chart_range="5d"
                )
                self.assertEqual(document["status"], "failed")
                self.assertEqual(
                    document["errors"][-1]["code"], "range_symbol_count"
                )
        self.assertEqual(calls, [])

    def test_price_less_symbol_becomes_an_error_in_a_mixed_batch(self):
        good = FakeResponse(json.dumps(yahoo_payload()).encode())
        empty = FakeResponse(
            json.dumps(yahoo_payload(symbol="MSFT", price=None, closes=[None])).encode()
        )

        def opener(request, timeout):
            return empty if "MSFT" in request.full_url else good

        document = fetch_quotes.fetch_quotes(["AAPL", "MSFT"], opener=opener)
        self.assertEqual(document["status"], "partial")
        self.assertEqual([quote["symbol"] for quote in document["quotes"]], ["AAPL"])
        self.assertEqual(document["errors"][0]["symbol"], "MSFT")
        self.assertEqual(document["errors"][0]["code"], "quote_unavailable")

    def test_all_price_less_symbols_produce_a_failed_document(self):
        def opener(request, timeout):
            symbol = "MSFT" if "MSFT" in request.full_url else "AAPL"
            return FakeResponse(
                json.dumps(yahoo_payload(symbol=symbol, price=None, closes=[None])).encode()
            )

        document = fetch_quotes.fetch_quotes(["AAPL", "MSFT"], opener=opener)
        self.assertEqual(document["status"], "failed")
        self.assertEqual(document["quotes"], [])
        self.assertEqual(
            [error["code"] for error in document["errors"]],
            ["quote_unavailable", "quote_unavailable"],
        )

    def test_malformed_json_produces_failed_document(self):
        document = fetch_quotes.fetch_quotes(
            ["AAPL"], opener=lambda *args, **kwargs: FakeResponse(b"not-json")
        )
        self.assertEqual(document["status"], "failed")
        self.assertEqual(document["errors"][0]["code"], "malformed_response")


class CacheTests(unittest.TestCase):
    @staticmethod
    def _success_opener(request, timeout):
        encoded_symbol = request.full_url.split("/chart/", 1)[1].split("?", 1)[0]
        symbol = fetch_quotes.urllib.parse.unquote(encoded_symbol)
        return FakeResponse(json.dumps(yahoo_payload(symbol=symbol)).encode())

    @staticmethod
    def _timeout_opener(request, timeout):
        raise socket.timeout()

    def test_live_success_creates_schema_versioned_private_atomic_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "nested" / "quotes.json"
            document = fetch_quotes.fetch_quotes(
                ["AAPL"],
                opener=self._success_opener,
                cache_file=path,
                now_epoch=1_700_000_000,
            )

            self.assertEqual(document["status"], "ready")
            self.assertNotIn("cached", document["quotes"][0])
            payload = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(payload["schemaVersion"], fetch_quotes.CACHE_SCHEMA_VERSION)
            self.assertEqual(set(payload["entries"]), {"AAPL|1d"})
            self.assertEqual(payload["entries"]["AAPL|1d"]["storedAt"], 1_700_000_000)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(
                [item.name for item in path.parent.iterdir()], ["quotes.json"]
            )

    def test_provider_failure_returns_fresh_enough_cache_and_exact_error(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "quotes.json"
            fetch_quotes.fetch_quotes(
                ["AAPL"],
                opener=self._success_opener,
                cache_file=path,
                now_epoch=100,
            )
            document = fetch_quotes.fetch_quotes(
                ["AAPL"],
                opener=self._timeout_opener,
                cache_file=path,
                now_epoch=145,
            )

            self.assertEqual(document["status"], "partial")
            self.assertEqual(document["errors"], [
                {
                    "symbol": "AAPL",
                    "code": "timeout",
                    "message": "Yahoo did not respond before the timeout.",
                }
            ])
            quote = document["quotes"][0]
            self.assertTrue(quote["cached"])
            self.assertTrue(quote["stale"])
            self.assertEqual(quote["cacheAgeSec"], 45)
            self.assertEqual(quote["range"], "1d")

    def test_cache_is_keyed_by_symbol_and_range(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "quotes.json"
            fetch_quotes.fetch_quotes(
                ["AAPL"],
                opener=self._success_opener,
                cache_file=path,
                chart_range="1d",
                now_epoch=100,
            )
            fetch_quotes.fetch_quotes(
                ["AAPL"],
                opener=self._success_opener,
                cache_file=path,
                chart_range="5d",
                now_epoch=200,
            )
            payload = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(
                set(payload["entries"]), {"AAPL|1d", "AAPL|5d"}
            )

            history = fetch_quotes.fetch_quotes(
                ["AAPL"],
                opener=self._timeout_opener,
                cache_file=path,
                chart_range="5d",
                now_epoch=230,
            )
            self.assertEqual(history["quotes"][0]["range"], "5d")
            self.assertEqual(history["quotes"][0]["cacheAgeSec"], 30)

            missing = fetch_quotes.fetch_quotes(
                ["MSFT"],
                opener=self._timeout_opener,
                cache_file=path,
                chart_range="5d",
                now_epoch=230,
            )
            self.assertEqual(missing["status"], "failed")
            self.assertEqual(missing["quotes"], [])

    def test_cache_expiry_is_seven_days_for_1d_and_thirty_for_history(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "quotes.json"
            fetch_quotes.fetch_quotes(
                ["AAPL"],
                opener=self._success_opener,
                cache_file=path,
                now_epoch=100,
            )
            expired = fetch_quotes.fetch_quotes(
                ["AAPL"],
                opener=self._timeout_opener,
                cache_file=path,
                now_epoch=100 + fetch_quotes.CACHE_1D_MAX_AGE_SECONDS + 1,
            )
            self.assertEqual(expired["status"], "failed")

            fetch_quotes.fetch_quotes(
                ["AAPL"],
                opener=self._success_opener,
                cache_file=path,
                chart_range="1y",
                now_epoch=200,
            )
            still_valid = fetch_quotes.fetch_quotes(
                ["AAPL"],
                opener=self._timeout_opener,
                cache_file=path,
                chart_range="1y",
                now_epoch=200 + fetch_quotes.CACHE_HISTORY_MAX_AGE_SECONDS,
            )
            self.assertEqual(still_valid["status"], "partial")
            self.assertEqual(
                still_valid["quotes"][0]["cacheAgeSec"],
                fetch_quotes.CACHE_HISTORY_MAX_AGE_SECONDS,
            )

    def test_corrupt_and_wrong_schema_cache_are_ignored_and_repaired(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "quotes.json"
            for broken in ("{not json", '{"schemaVersion":99,"entries":{}}'):
                with self.subTest(broken=broken):
                    path.write_text(broken, encoding="utf-8")
                    document = fetch_quotes.fetch_quotes(
                        ["AAPL"],
                        opener=self._success_opener,
                        cache_file=path,
                        now_epoch=100,
                    )
                    self.assertEqual(document["status"], "ready")
                    repaired = json.loads(path.read_text(encoding="utf-8"))
                    self.assertEqual(
                        repaired["schemaVersion"], fetch_quotes.CACHE_SCHEMA_VERSION
                    )

    def test_oversized_cache_is_never_read_as_a_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "quotes.json"
            path.write_bytes(b" " * (fetch_quotes.MAX_CACHE_BYTES + 1))
            document = fetch_quotes.fetch_quotes(
                ["AAPL"],
                opener=self._timeout_opener,
                cache_file=path,
                now_epoch=100,
            )
            self.assertEqual(document["status"], "failed")
            self.assertEqual(document["quotes"], [])
            self.assertEqual(path.stat().st_size, fetch_quotes.MAX_CACHE_BYTES + 1)

    def test_cache_file_symlink_is_not_followed_or_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            target = root / "target.json"
            target.write_text("sentinel", encoding="utf-8")
            link = root / "quotes.json"
            link.symlink_to(target)

            document = fetch_quotes.fetch_quotes(
                ["AAPL"],
                opener=self._success_opener,
                cache_file=link,
                now_epoch=100,
            )
            self.assertEqual(document["status"], "ready")
            self.assertEqual(target.read_text(encoding="utf-8"), "sentinel")
            self.assertTrue(link.is_symlink())

    def test_cache_parent_symlink_is_not_followed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            real_parent = root / "real"
            real_parent.mkdir()
            linked_parent = root / "linked"
            linked_parent.symlink_to(real_parent, target_is_directory=True)
            cache_path = linked_parent / "quotes.json"

            document = fetch_quotes.fetch_quotes(
                ["AAPL"],
                opener=self._success_opener,
                cache_file=cache_path,
                now_epoch=100,
            )
            self.assertEqual(document["status"], "ready")
            self.assertFalse((real_parent / "quotes.json").exists())

    def test_replacing_existing_cache_tightens_permissions_to_0600(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "quotes.json"
            path.write_text("{}", encoding="utf-8")
            path.chmod(0o666)
            fetch_quotes.fetch_quotes(
                ["AAPL"],
                opener=self._success_opener,
                cache_file=path,
                now_epoch=100,
            )
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)


class FixtureAndCliTests(unittest.TestCase):
    def setUp(self):
        self.fixture_path = ROOT / "demo" / "fixtures" / "quotes.json"

    def test_demo_fixture_is_schema_bounded_and_can_be_filtered(self):
        document = fetch_quotes.load_fixture(self.fixture_path, ["NORTH", "MISSING"])
        self.assertEqual(document["provider"], "Fictional demo fixture")
        self.assertEqual(document["status"], "partial")
        self.assertEqual([quote["symbol"] for quote in document["quotes"]], ["NORTH"])
        self.assertEqual(document["errors"][0]["code"], "fixture_missing")
        self.assertLessEqual(len(document["quotes"][0]["sparkline"]), 78)

    def test_fixture_supports_range_timestamps_metadata_and_session_state(self):
        payload = {
            "schemaVersion": fetch_quotes.SCHEMA_VERSION,
            "provider": "Deterministic fixture",
            "generatedAt": "2026-01-02T03:04:05Z",
            "quotes": [
                {
                    "symbol": "BTC-USD",
                    "name": "Bitcoin USD",
                    "currency": "USD",
                    "exchange": "CCC",
                    "exchangeTimezone": "UTC",
                    "instrumentType": "CRYPTOCURRENCY",
                    "regularMarketPrice": 102,
                    "previousClose": 100,
                    "regularMarketOpen": 100.5,
                    "dayLow": 98,
                    "dayHigh": 103,
                    "fiftyTwoWeekLow": 50,
                    "fiftyTwoWeekHigh": 150,
                    "volume": 1234,
                    "sparkline": [100, 101, 102],
                    "sparklineTimestamps": [10, 20, 30],
                }
            ],
            "errors": [],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "history.json"
            path.write_text(json.dumps(payload), encoding="utf-8")
            document = fetch_quotes.load_fixture(
                path, ["BTC-USD"], chart_range="6mo"
            )
        quote = document["quotes"][0]
        self.assertEqual(document["generatedAt"], "2026-01-02T03:04:05Z")
        self.assertEqual(quote["range"], "6mo")
        self.assertEqual(quote["sparklineTimestamps"], [10, 20, 30])
        self.assertEqual(quote["sessionState"], "continuous")
        self.assertEqual(quote["exchangeTimezone"], "UTC")
        self.assertEqual(quote["fiftyTwoWeekHigh"], 150)

    def test_fixture_mode_prints_one_json_document_and_never_fetches(self):
        stdout = io.StringIO()
        original = fetch_quotes.fetch_quote

        def forbidden(*args, **kwargs):
            raise AssertionError("fixture mode attempted a network fetch")

        fetch_quotes.fetch_quote = forbidden
        try:
            with contextlib.redirect_stdout(stdout):
                exit_code = fetch_quotes.main(
                    [
                        "--fixture",
                        str(self.fixture_path),
                        "--timeout",
                        "8",
                        "--symbols",
                        "ACME,LUMA",
                    ]
                )
        finally:
            fetch_quotes.fetch_quote = original
        document = json.loads(stdout.getvalue())
        self.assertEqual(exit_code, 0)
        self.assertEqual(document["status"], "ready")
        self.assertEqual(
            [quote["symbol"] for quote in document["quotes"]], ["ACME", "LUMA"]
        )

    def test_empty_invocation_is_an_empty_success(self):
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            exit_code = fetch_quotes.main([])
        document = json.loads(stdout.getvalue())
        self.assertEqual(exit_code, 0)
        self.assertEqual(document["status"], "empty")
        self.assertEqual(document["quotes"], [])
        self.assertEqual(document["errors"], [])

    def test_too_many_symbols_prints_bounded_failure_without_fetch(self):
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            exit_code = fetch_quotes.main([f"SYM{i}" for i in range(13)])
        document = json.loads(stdout.getvalue())
        self.assertEqual(exit_code, 2)
        self.assertEqual(document["status"], "failed")
        self.assertEqual(document["errors"][0]["code"], "too_many_symbols")

    def test_invalid_timeout_is_rejected_before_network_io(self):
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            exit_code = fetch_quotes.main(["--timeout", "30", "--symbols", "AAPL"])
        document = json.loads(stdout.getvalue())
        self.assertEqual(exit_code, 2)
        self.assertEqual(document["status"], "failed")
        self.assertEqual(document["errors"][0]["code"], "invalid_timeout")

    def test_invalid_range_prints_one_json_failure_before_network_io(self):
        stdout = io.StringIO()
        original = fetch_quotes.fetch_quote

        def forbidden(*args, **kwargs):
            raise AssertionError("invalid range attempted a network fetch")

        fetch_quotes.fetch_quote = forbidden
        try:
            with contextlib.redirect_stdout(stdout):
                exit_code = fetch_quotes.main(["--range", "2y", "AAPL"])
        finally:
            fetch_quotes.fetch_quote = original
        document = json.loads(stdout.getvalue())
        self.assertEqual(exit_code, 2)
        self.assertEqual(document["status"], "failed")
        self.assertEqual(document["errors"][0]["code"], "invalid_range")

    def test_longer_range_cli_requires_exactly_one_valid_symbol(self):
        for args in (
            ["--range", "5d"],
            ["--range", "5d", "AAPL", "MSFT"],
        ):
            with self.subTest(args=args):
                stdout = io.StringIO()
                with contextlib.redirect_stdout(stdout):
                    exit_code = fetch_quotes.main(args)
                document = json.loads(stdout.getvalue())
                self.assertEqual(exit_code, 2)
                self.assertEqual(
                    document["errors"][-1]["code"], "range_symbol_count"
                )

    def test_longer_range_fixture_with_one_symbol_is_deterministic(self):
        payload = json.loads(self.fixture_path.read_text(encoding="utf-8"))
        for quote in payload["quotes"]:
            quote["range"] = "1y"
        with tempfile.TemporaryDirectory() as directory:
            fixture_path = pathlib.Path(directory) / "one-year.json"
            fixture_path.write_text(json.dumps(payload), encoding="utf-8")
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                exit_code = fetch_quotes.main(
                    [
                        "--fixture",
                        str(fixture_path),
                        "--range",
                        "1y",
                        "ACME",
                    ]
                )
        document = json.loads(stdout.getvalue())
        self.assertEqual(exit_code, 0)
        self.assertEqual(document["generatedAt"], "2026-08-31T12:00:00Z")
        self.assertEqual(document["quotes"][0]["range"], "1y")

    def test_relative_cache_path_is_rejected_before_network_io(self):
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            exit_code = fetch_quotes.main(
                ["--cache-file", "relative/cache.json", "AAPL"]
            )
        document = json.loads(stdout.getvalue())
        self.assertEqual(exit_code, 2)
        self.assertEqual(document["errors"][0]["code"], "invalid_cache_path")

    def test_help_documents_ranges_and_cache_contract(self):
        help_text = fetch_quotes._parser().format_help()
        self.assertIn("--range RANGE", help_text)
        self.assertIn("1d, 5d, 1mo, 6mo, or 1y", help_text)
        self.assertIn("--cache-file ABSOLUTE_PATH", help_text)
        self.assertIn("2 MiB", help_text)

    def test_invalid_only_fixture_selection_does_not_leak_other_quotes(self):
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            exit_code = fetch_quotes.main(
                ["--fixture", str(self.fixture_path), "--symbols", "BAD/SYMBOL"]
            )
        document = json.loads(stdout.getvalue())
        self.assertEqual(exit_code, 1)
        self.assertEqual(document["status"], "failed")
        self.assertEqual(document["quotes"], [])
        self.assertEqual(document["errors"][0]["code"], "invalid_symbol")

    def test_fixture_requires_the_supported_schema_version(self):
        payload = json.loads(self.fixture_path.read_text(encoding="utf-8"))
        payload["schemaVersion"] = 99
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "future.json"
            path.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaises(fetch_quotes.FetchFailure) as caught:
                fetch_quotes.load_fixture(path)
        self.assertEqual(caught.exception.code, "fixture_invalid")

    def test_fixture_rejects_a_quote_without_price_or_finite_history(self):
        payload = json.loads(self.fixture_path.read_text(encoding="utf-8"))
        payload["quotes"] = [
            {
                "symbol": "NONE",
                "name": "No Price",
                "currency": "USD",
                "regularMarketPrice": None,
                "previousClose": 10,
                "change": None,
                "changePercent": None,
                "marketTime": None,
                "sparkline": [None],
            }
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "price-less.json"
            path.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaises(fetch_quotes.FetchFailure) as caught:
                fetch_quotes.load_fixture(path)
        self.assertEqual(caught.exception.code, "fixture_invalid")

    def test_oversized_fixture_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "too-large.json"
            path.write_bytes(b" " * (fetch_quotes.MAX_RESPONSE_BYTES + 1))
            with self.assertRaises(fetch_quotes.FetchFailure) as caught:
                fetch_quotes.load_fixture(path)
        self.assertEqual(caught.exception.code, "fixture_too_large")


if __name__ == "__main__":
    unittest.main()
