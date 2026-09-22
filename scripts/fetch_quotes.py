#!/usr/bin/env python3
"""Fetch bounded market quotes and chart history from Yahoo's chart endpoint.

The helper deliberately has a narrow interface: symbols enter on the command
line and one normalized JSON document is written to stdout.  It is intended to
be launched locally by the Omarchy plugin; it is not a server and does not read
credentials or provider configuration from the environment.

``--range`` supports ``1d``, ``5d``, ``1mo``, ``6mo``, and ``1y``.  The default
one-day request accepts the normal bounded watchlist; longer ranges deliberately
accept exactly one valid symbol so opening a chart cannot multiply provider
traffic.  ``--cache-file`` may point at one absolute local path for a bounded,
schema-versioned last-known-good cache.  Cache I/O is atomic, private (0600),
and descriptor-relative: no path component or cache file symlink is followed.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import json
import math
import os
import fcntl
import pathlib
import re
import secrets
import socket
import stat
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any, Callable, Iterable, Mapping, Sequence


SCHEMA_VERSION = 1
PROVIDER_NAME = "Yahoo Finance chart"
ENDPOINT_HOST = "query1.finance.yahoo.com"
ENDPOINT_PREFIX = f"https://{ENDPOINT_HOST}/v8/finance/chart/"
USER_AGENT = "Omarchy-Markets/1.0 (+local desktop widget)"

MAX_SYMBOLS = 12
MAX_SYMBOL_LENGTH = 32
MAX_NAME_LENGTH = 120
MAX_CURRENCY_LENGTH = 12
MAX_EXCHANGE_LENGTH = 80
MAX_TIMEZONE_LENGTH = 80
MAX_INSTRUMENT_TYPE_LENGTH = 40
MAX_PROVIDER_LENGTH = 80
MAX_ERROR_CODE_LENGTH = 40
MAX_ERROR_MESSAGE_LENGTH = 160
MAX_SPARKLINE_POINTS = 78
MAX_RESPONSE_BYTES = 1_048_576
MAX_CACHE_BYTES = 2_097_152
MAX_CACHE_ENTRIES = MAX_SYMBOLS * 5
MAX_HISTORY_FILES = MAX_SYMBOLS * 5
MAX_HISTORY_BYTES = 8 * 1_048_576
MAX_HISTORY_SCAN_ENTRIES = 4096
CACHE_SCHEMA_VERSION = 1
CACHE_1D_MAX_AGE_SECONDS = 7 * 24 * 60 * 60
CACHE_HISTORY_MAX_AGE_SECONDS = 30 * 24 * 60 * 60
DEFAULT_TIMEOUT_SECONDS = 5.0
MIN_TIMEOUT_SECONDS = 0.25
MAX_TIMEOUT_SECONDS = 10.0
MAX_WORKERS = 4

CHART_INTERVALS = {
    "1d": "5m",
    "5d": "15m",
    "1mo": "1d",
    "6mo": "1d",
    "1y": "1wk",
}
CHART_RANGES = tuple(CHART_INTERVALS)
SESSION_STATES = frozenset(
    {"regular", "pre", "post", "closed", "continuous", "unknown"}
)

_SYMBOL_RE = re.compile(r"^[A-Z0-9.^=_+\-]+$")
_ERROR_CODE_RE = re.compile(r"[^a-z0-9_]+")
_HISTORY_FILE_RE = re.compile(r"[A-Z0-9.^=_+\-]{1,32}-(?:5d|1mo|6mo|1y)-v1\.json\Z")
_HISTORY_TEMP_RE = re.compile(
    r"\.[A-Z0-9.^=_+\-]{1,32}-(?:5d|1mo|6mo|1y)-v1\.json\.[0-9]+\.[0-9a-f]{16}\.tmp\Z"
)


class InputLimitError(ValueError):
    """Raised before any I/O when the requested symbol set is too large."""


@dataclass(frozen=True)
class FetchFailure(Exception):
    """A controlled, user-displayable failure for one quote."""

    code: str
    message: str

    def __str__(self) -> str:
        return self.message


class FixedHostRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Permit redirects only when they remain on the fixed HTTPS provider."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        resolved = urllib.parse.urljoin(req.full_url, newurl)
        target = urllib.parse.urlsplit(resolved)
        try:
            target_port = target.port
        except ValueError:
            target_port = -1
        if (
            target.scheme != "https"
            or target.hostname != ENDPOINT_HOST
            or target_port not in (None, 443)
        ):
            raise FetchFailure(
                "unsafe_redirect",
                "Yahoo redirected the quote request outside the approved host.",
            )
        return super().redirect_request(req, fp, code, msg, headers, resolved)


_FIXED_HOST_OPENER = urllib.request.build_opener(FixedHostRedirectHandler())


def _utc_iso_from_epoch(value: Any) -> str | None:
    number = _finite_number(value)
    if number is None or number < 0:
        return None
    try:
        timestamp = dt.datetime.fromtimestamp(number, tz=dt.timezone.utc)
    except (OverflowError, OSError, ValueError):
        return None
    return timestamp.isoformat(timespec="seconds").replace("+00:00", "Z")


def utc_now_iso() -> str:
    return dt.datetime.now(tz=dt.timezone.utc).isoformat(
        timespec="seconds"
    ).replace("+00:00", "Z")


def _bounded_text(value: Any, limit: int, fallback: str = "") -> str:
    if not isinstance(value, str):
        return fallback
    # Provider text is display data.  Collapse whitespace so it cannot inject
    # terminal lines or make the helper's output grow unexpectedly.
    cleaned = " ".join(value.split())
    return cleaned[:limit] if cleaned else fallback


def _finite_number(value: Any) -> int | float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    try:
        finite = math.isfinite(value)
    except OverflowError:
        return None
    if not finite:
        return None
    return value


def _finite_difference(left: int | float, right: int | float) -> int | float | None:
    return _finite_number(left - right)


def _bounded_series(
    values: Any, timestamps: Any = None
) -> tuple[list[int | float], list[int | float]]:
    """Return a finite bounded series and, only when safe, aligned timestamps."""

    if not isinstance(values, list):
        return [], []
    finite = [
        (index, number)
        for index, value in enumerate(values)
        if (number := _finite_number(value)) is not None
    ]
    if len(finite) > MAX_SPARKLINE_POINTS:
        # Keep both endpoints and distribute the remaining samples evenly.
        # Sampling the source indexes also lets timestamps remain aligned.
        last = len(finite) - 1
        finite = [
            finite[round(index * last / (MAX_SPARKLINE_POINTS - 1))]
            for index in range(MAX_SPARKLINE_POINTS)
        ]

    sparkline = [number for _, number in finite]
    if not sparkline or not isinstance(timestamps, list):
        return sparkline, []

    bounded_timestamps: list[int | float] = []
    for source_index, _ in finite:
        if source_index >= len(timestamps):
            return sparkline, []
        timestamp = _finite_number(timestamps[source_index])
        if timestamp is None or timestamp < 0:
            return sparkline, []
        bounded_timestamps.append(timestamp)
    return sparkline, bounded_timestamps


def _bounded_sparkline(values: Any) -> list[int | float]:
    """Compatibility wrapper for callers that do not have timestamps."""

    return _bounded_series(values)[0]


def normalize_chart_range(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    candidate = value.strip().lower()
    return candidate if candidate in CHART_INTERVALS else None


def chart_interval(chart_range: str) -> str:
    normalized = normalize_chart_range(chart_range)
    if normalized is None:
        raise FetchFailure(
            "invalid_range",
            f"Range must be one of {', '.join(CHART_RANGES)}.",
        )
    return CHART_INTERVALS[normalized]


def _safe_error_code(value: Any, fallback: str = "unknown_error") -> str:
    raw = value.lower() if isinstance(value, str) else ""
    cleaned = _ERROR_CODE_RE.sub("_", raw).strip("_")
    return (cleaned or fallback)[:MAX_ERROR_CODE_LENGTH]


def make_error(symbol: str | None, code: str, message: str) -> dict[str, Any]:
    safe_symbol = (
        _bounded_text(symbol, MAX_SYMBOL_LENGTH).upper()
        if isinstance(symbol, str)
        else None
    )
    return {
        "symbol": safe_symbol or None,
        "code": _safe_error_code(code),
        "message": _bounded_text(message, MAX_ERROR_MESSAGE_LENGTH, "Quote unavailable."),
    }


def normalize_symbols(
    raw_symbols: Sequence[str],
) -> tuple[list[str], list[dict[str, Any]]]:
    """Normalize, validate, and deduplicate a bounded Yahoo symbol list."""

    if len(raw_symbols) > MAX_SYMBOLS:
        raise InputLimitError(f"At most {MAX_SYMBOLS} symbols may be requested.")

    symbols: list[str] = []
    errors: list[dict[str, Any]] = []
    seen: set[str] = set()
    for raw in raw_symbols:
        symbol = raw.strip().upper() if isinstance(raw, str) else ""
        if (
            not symbol
            or len(symbol) > MAX_SYMBOL_LENGTH
            or _SYMBOL_RE.fullmatch(symbol) is None
            or re.search(r"[A-Z0-9]", symbol) is None
        ):
            errors.append(
                make_error(
                    _bounded_text(raw, MAX_SYMBOL_LENGTH) if isinstance(raw, str) else None,
                    "invalid_symbol",
                    "Use a Yahoo symbol containing only letters, numbers, '.', '^', '=', '_', '+', or '-'.",
                )
            )
            continue
        if symbol not in seen:
            seen.add(symbol)
            symbols.append(symbol)
    return symbols, errors


def build_chart_url(symbol: str, chart_range: str = "1d") -> str:
    """Build a URL whose path segment cannot escape the fixed Yahoo endpoint."""

    normalized_range = normalize_chart_range(chart_range)
    if normalized_range is None:
        raise FetchFailure(
            "invalid_range",
            f"Range must be one of {', '.join(CHART_RANGES)}.",
        )
    encoded_symbol = urllib.parse.quote(symbol, safe="")
    query = urllib.parse.urlencode(
        {
            "interval": CHART_INTERVALS[normalized_range],
            "range": normalized_range,
            "includePrePost": "false",
            "events": "div,splits",
        }
    )
    return f"{ENDPOINT_PREFIX}{encoded_symbol}?{query}"


def _extract_chart_result(payload: Any) -> Mapping[str, Any]:
    if not isinstance(payload, Mapping):
        raise FetchFailure("malformed_response", "Yahoo returned a non-object response.")
    chart = payload.get("chart")
    if not isinstance(chart, Mapping):
        raise FetchFailure("malformed_response", "Yahoo returned an incomplete chart response.")

    provider_error = chart.get("error")
    if provider_error:
        description = ""
        if isinstance(provider_error, Mapping):
            description = _bounded_text(
                provider_error.get("description"), MAX_ERROR_MESSAGE_LENGTH
            )
        message = "Yahoo did not return this quote."
        if description:
            message = f"Yahoo did not return this quote: {description}"
        raise FetchFailure("provider_error", message)

    results = chart.get("result")
    if not isinstance(results, list) or not results or not isinstance(results[0], Mapping):
        raise FetchFailure("malformed_response", "Yahoo returned no chart result.")
    return results[0]


def _normalized_session_state(value: Any) -> str | None:
    state = _bounded_text(value, 32).lower()
    aliases = {
        "regular": "regular",
        "open": "regular",
        "pre": "pre",
        "prepre": "pre",
        "premarket": "pre",
        "post": "post",
        "postpost": "post",
        "postmarket": "post",
        "closed": "closed",
        "continuous": "continuous",
        "24x7": "continuous",
    }
    return aliases.get(state)


def _session_state(meta: Mapping[str, Any], now_epoch: float) -> str:
    instrument_type = _bounded_text(
        meta.get("instrumentType"), MAX_INSTRUMENT_TYPE_LENGTH
    ).upper()
    if instrument_type in {"CRYPTOCURRENCY", "CRYPTO", "DIGITAL_ASSET"}:
        return "continuous"

    periods_value = meta.get("currentTradingPeriod")
    periods: Mapping[str, Any] = (
        periods_value if isinstance(periods_value, Mapping) else {}
    )
    saw_valid_period = False
    # Prefer the most specific matching phase if the provider returns touching
    # or slightly overlapping boundaries.
    for name in ("pre", "regular", "post"):
        period = periods.get(name)
        if not isinstance(period, Mapping):
            continue
        start = _finite_number(period.get("start"))
        end = _finite_number(period.get("end"))
        if start is None or end is None or start < 0 or end <= start:
            continue
        saw_valid_period = True
        if start <= now_epoch < end:
            return name
    if saw_valid_period:
        return "closed"

    provider_state = _normalized_session_state(meta.get("marketState"))
    return provider_state or "unknown"


def _meta_number(meta: Mapping[str, Any], *names: str) -> int | float | None:
    for name in names:
        number = _finite_number(meta.get(name))
        if number is not None:
            return number
    return None


def _nonnegative_meta_number(
    meta: Mapping[str, Any], *names: str
) -> int | float | None:
    number = _meta_number(meta, *names)
    return number if number is not None and number >= 0 else None


def parse_yahoo_chart(
    payload: Any,
    requested_symbol: str,
    *,
    chart_range: str = "1d",
    now_epoch: float | None = None,
) -> dict[str, Any]:
    """Reduce a Yahoo chart response to the plugin's stable quote schema."""

    normalized_range = normalize_chart_range(chart_range)
    if normalized_range is None:
        raise FetchFailure(
            "invalid_range",
            f"Range must be one of {', '.join(CHART_RANGES)}.",
        )
    result = _extract_chart_result(payload)
    meta_value = result.get("meta")
    meta: Mapping[str, Any] = meta_value if isinstance(meta_value, Mapping) else {}
    provider_symbol = _bounded_text(meta.get("symbol"), MAX_SYMBOL_LENGTH).upper()
    if provider_symbol and provider_symbol != requested_symbol:
        raise FetchFailure(
            "symbol_mismatch",
            "Yahoo returned a quote for a different symbol.",
        )

    close_values: Any = []
    indicators = result.get("indicators")
    if isinstance(indicators, Mapping):
        quote_blocks = indicators.get("quote")
        if (
            isinstance(quote_blocks, list)
            and quote_blocks
            and isinstance(quote_blocks[0], Mapping)
        ):
            close_values = quote_blocks[0].get("close")
    sparkline, sparkline_timestamps = _bounded_series(
        close_values, result.get("timestamp")
    )

    price = _finite_number(meta.get("regularMarketPrice"))
    if price is None and sparkline:
        price = sparkline[-1]
    if price is None:
        raise FetchFailure(
            "quote_unavailable",
            "Yahoo returned no usable price for this quote.",
        )
    previous_close = _finite_number(meta.get("chartPreviousClose"))
    if previous_close is None:
        previous_close = _finite_number(meta.get("previousClose"))

    change: int | float | None = None
    change_percent: int | float | None = None
    if price is not None and previous_close is not None:
        change = _finite_difference(price, previous_close)
        if change is not None and previous_close != 0:
            change_percent = _finite_number((change / previous_close) * 100)

    name = _bounded_text(meta.get("shortName"), MAX_NAME_LENGTH)
    if not name:
        name = _bounded_text(meta.get("longName"), MAX_NAME_LENGTH)
    if not name:
        name = requested_symbol

    currency = _bounded_text(meta.get("currency"), MAX_CURRENCY_LENGTH) or None
    exchange = _bounded_text(
        meta.get("fullExchangeName"), MAX_EXCHANGE_LENGTH
    ) or _bounded_text(meta.get("exchangeName"), MAX_EXCHANGE_LENGTH)
    exchange_timezone = _bounded_text(
        meta.get("exchangeTimezoneName"), MAX_TIMEZONE_LENGTH
    ) or _bounded_text(meta.get("timezone"), MAX_TIMEZONE_LENGTH)
    instrument_type = _bounded_text(
        meta.get("instrumentType"), MAX_INSTRUMENT_TYPE_LENGTH
    )
    observed_now = _finite_number(now_epoch)
    if observed_now is None or observed_now < 0:
        observed_now = time.time()
    session_state = _session_state(meta, float(observed_now))
    return {
        "symbol": requested_symbol,
        "name": name,
        "currency": currency,
        "exchange": exchange or None,
        "exchangeTimezone": exchange_timezone or None,
        "instrumentType": instrument_type or None,
        "marketState": session_state,
        "sessionState": session_state,
        "regularMarketPrice": price,
        "previousClose": previous_close,
        "change": change,
        "changePercent": change_percent,
        "marketTime": _utc_iso_from_epoch(meta.get("regularMarketTime")),
        "regularMarketOpen": _meta_number(meta, "regularMarketOpen"),
        "dayLow": _meta_number(meta, "regularMarketDayLow", "dayLow"),
        "dayHigh": _meta_number(meta, "regularMarketDayHigh", "dayHigh"),
        "fiftyTwoWeekLow": _meta_number(meta, "fiftyTwoWeekLow"),
        "fiftyTwoWeekHigh": _meta_number(meta, "fiftyTwoWeekHigh"),
        "volume": _nonnegative_meta_number(meta, "regularMarketVolume", "volume"),
        "sparkline": sparkline,
        "sparklineTimestamps": sparkline_timestamps,
        "range": normalized_range,
    }


def _read_response(response: Any) -> bytes:
    headers = getattr(response, "headers", None)
    if headers is not None:
        declared = headers.get("Content-Length")
        if declared:
            try:
                if int(declared) > MAX_RESPONSE_BYTES:
                    raise FetchFailure(
                        "response_too_large", "Yahoo's response exceeded the size limit."
                    )
            except ValueError:
                pass

    data = response.read(MAX_RESPONSE_BYTES + 1)
    if len(data) > MAX_RESPONSE_BYTES:
        raise FetchFailure(
            "response_too_large", "Yahoo's response exceeded the size limit."
        )
    return data


def fetch_quote(
    symbol: str,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
    opener: Callable[..., Any] | None = None,
    *,
    chart_range: str = "1d",
    now_epoch: float | None = None,
) -> dict[str, Any]:
    """Fetch and normalize one symbol from the fixed HTTPS endpoint."""

    url = build_chart_url(symbol, chart_range)
    parsed_url = urllib.parse.urlsplit(url)
    if (
        parsed_url.scheme != "https"
        or parsed_url.hostname != ENDPOINT_HOST
        or parsed_url.port not in (None, 443)
    ):
        # This should be unreachable because callers cannot supply an endpoint.
        raise FetchFailure("unsafe_endpoint", "The quote endpoint was rejected.")

    request = urllib.request.Request(
        url,
        headers={"Accept": "application/json", "User-Agent": USER_AGENT},
        method="GET",
    )
    open_url = opener or _FIXED_HOST_OPENER.open
    try:
        response = open_url(request, timeout=timeout)
        with response:
            raw = _read_response(response)
    except FetchFailure:
        raise
    except urllib.error.HTTPError as exc:
        raise FetchFailure(
            "http_error", f"Yahoo returned HTTP {int(exc.code)} for this quote."
        ) from None
    except (TimeoutError, socket.timeout):
        raise FetchFailure("timeout", "Yahoo did not respond before the timeout.") from None
    except urllib.error.URLError as exc:
        if isinstance(exc.reason, (TimeoutError, socket.timeout)):
            raise FetchFailure(
                "timeout", "Yahoo did not respond before the timeout."
            ) from None
        raise FetchFailure("network_error", "Yahoo could not be reached.") from None
    except OSError:
        raise FetchFailure("network_error", "Yahoo could not be reached.") from None

    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError, RecursionError):
        raise FetchFailure("malformed_response", "Yahoo returned invalid JSON.") from None
    return parse_yahoo_chart(
        payload, symbol, chart_range=chart_range, now_epoch=now_epoch
    )


def _status_for(quotes: Sequence[Any], errors: Sequence[Any]) -> str:
    if quotes and errors:
        return "partial"
    if quotes:
        return "ready"
    if errors:
        return "failed"
    return "empty"


def make_document(
    quotes: Sequence[Mapping[str, Any]],
    errors: Sequence[Mapping[str, Any]],
    *,
    provider: str = PROVIDER_NAME,
    generated_at: str | None = None,
) -> dict[str, Any]:
    bounded_quotes = list(quotes[:MAX_SYMBOLS])
    bounded_errors = list(errors[:MAX_SYMBOLS])
    return {
        "schemaVersion": SCHEMA_VERSION,
        "provider": _bounded_text(provider, MAX_PROVIDER_LENGTH, PROVIDER_NAME),
        "generatedAt": generated_at or utc_now_iso(),
        "status": _status_for(bounded_quotes, bounded_errors),
        "quotes": bounded_quotes,
        "errors": bounded_errors,
    }


def normalize_cache_path(value: pathlib.Path | str) -> pathlib.Path:
    """Validate a cache destination without resolving or following it."""

    path = pathlib.Path(value)
    encoded_path = os.fsencode(os.fspath(path))
    encoded_name = os.fsencode(path.name)
    if (
        not path.is_absolute()
        or not path.name
        or b"\x00" in encoded_name
        or len(encoded_path) > 4096
        or len(encoded_name) > 240
        or any(part in {".", ".."} for part in path.parts[1:])
    ):
        raise FetchFailure(
            "invalid_cache_path",
            "The cache file must be a bounded absolute path without '.' or '..'.",
        )
    return path


def _open_cache_parent_fd(path: pathlib.Path, *, create: bool) -> int:
    """Open an absolute parent directory one non-symlink component at a time."""

    directory_flags = (
        os.O_RDONLY
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    descriptor = os.open(os.sep, directory_flags)
    try:
        for component in path.parent.parts[1:]:
            try:
                next_descriptor = os.open(
                    component, directory_flags, dir_fd=descriptor
                )
            except FileNotFoundError:
                if not create:
                    raise
                try:
                    os.mkdir(component, 0o700, dir_fd=descriptor)
                except FileExistsError:
                    # A concurrent helper may have created it; the descriptor
                    # open below still proves it is a directory, not a link.
                    pass
                next_descriptor = os.open(
                    component, directory_flags, dir_fd=descriptor
                )
            metadata = os.fstat(next_descriptor)
            # Shared sticky ancestors such as /tmp are acceptable, but the
            # actual cache directory below them must be private and ours.
            if (metadata.st_uid not in (0, os.getuid()) or
                    (metadata.st_mode & 0o022 and not metadata.st_mode & stat.S_ISVTX)):
                os.close(next_descriptor)
                raise FetchFailure("cache_unsafe", "The cache ancestor is not trusted.")
            os.close(descriptor)
            descriptor = next_descriptor
        metadata = os.fstat(descriptor)
        if metadata.st_uid != os.getuid() or stat.S_IMODE(metadata.st_mode) != 0o700:
            raise FetchFailure("cache_unsafe", "The cache directory must be private (0700).")
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def _read_cache_bytes(path: pathlib.Path) -> bytes | None:
    try:
        parent_fd = _open_cache_parent_fd(path, create=False)
    except FileNotFoundError:
        return None
    except OSError:
        raise FetchFailure(
            "cache_unsafe", "The cache path could not be opened safely."
        ) from None

    file_fd: int | None = None
    try:
        flags = (
            os.O_RDONLY
            | getattr(os, "O_CLOEXEC", 0)
            | getattr(os, "O_NOFOLLOW", 0)
            | os.O_NONBLOCK
        )
        try:
            file_fd = os.open(path.name, flags, dir_fd=parent_fd)
        except FileNotFoundError:
            return None
        except OSError:
            raise FetchFailure(
                "cache_unsafe", "The cache file could not be opened safely."
            ) from None
        metadata = os.fstat(file_fd)
        if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid()
                or stat.S_IMODE(metadata.st_mode) != 0o600 or metadata.st_nlink != 1):
            raise FetchFailure(
                "cache_unsafe", "The cache must be a private, owner-held regular file."
            )
        if metadata.st_size > MAX_CACHE_BYTES:
            raise FetchFailure(
                "cache_too_large", "The cache file exceeded the size limit."
            )
        chunks: list[bytes] = []
        remaining = MAX_CACHE_BYTES + 1
        while remaining:
            chunk = os.read(file_fd, min(65_536, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        raw = b"".join(chunks)
        if len(raw) > MAX_CACHE_BYTES:
            raise FetchFailure(
                "cache_too_large", "The cache file exceeded the size limit."
            )
        return raw
    finally:
        if file_fd is not None:
            os.close(file_fd)
        os.close(parent_fd)


def _cache_key(symbol: str, chart_range: str) -> str:
    return f"{symbol}|{chart_range}"


def _load_cache_entries(
    cache_file: pathlib.Path | str | None,
) -> dict[str, dict[str, Any]]:
    if cache_file is None:
        return {}
    try:
        path = normalize_cache_path(cache_file)
        raw = _read_cache_bytes(path)
        if raw is None:
            return {}
        payload = json.loads(raw.decode("utf-8"))
        if not isinstance(payload, Mapping):
            return {}
        if payload.get("schemaVersion") != CACHE_SCHEMA_VERSION:
            return {}
        raw_entries = payload.get("entries")
        if not isinstance(raw_entries, Mapping) or len(raw_entries) > MAX_CACHE_ENTRIES:
            return {}

        entries: dict[str, dict[str, Any]] = {}
        for key, raw_entry in raw_entries.items():
            if not isinstance(key, str) or not isinstance(raw_entry, Mapping):
                continue
            raw_symbol = raw_entry.get("symbol")
            raw_range = normalize_chart_range(raw_entry.get("range"))
            stored_at = _finite_number(raw_entry.get("storedAt"))
            if not isinstance(raw_symbol, str) or raw_range is None:
                continue
            symbols, symbol_errors = normalize_symbols([raw_symbol])
            if symbol_errors or len(symbols) != 1 or stored_at is None or stored_at < 0:
                continue
            symbol = symbols[0]
            if key != _cache_key(symbol, raw_range):
                continue
            quote = _sanitize_fixture_quote(
                raw_entry.get("quote"), chart_range=raw_range
            )
            if quote is None or quote["symbol"] != symbol:
                continue
            entries[key] = {
                "symbol": symbol,
                "range": raw_range,
                "storedAt": stored_at,
                "quote": quote,
            }
        return entries
    except (
        FetchFailure,
        OSError,
        UnicodeDecodeError,
        json.JSONDecodeError,
        RecursionError,
    ):
        # A cache is an availability aid, never a reason to withhold a fresh
        # provider result.  Unsafe, corrupt, or oversized caches are ignored.
        return {}


def _cache_max_age(chart_range: str) -> int:
    return (
        CACHE_1D_MAX_AGE_SECONDS
        if chart_range == "1d"
        else CACHE_HISTORY_MAX_AGE_SECONDS
    )


def _cached_fallback(
    entries: Mapping[str, Mapping[str, Any]],
    symbol: str,
    chart_range: str,
    now_epoch: float,
) -> dict[str, Any] | None:
    entry = entries.get(_cache_key(symbol, chart_range))
    if not isinstance(entry, Mapping):
        return None
    stored_at = _finite_number(entry.get("storedAt"))
    quote = entry.get("quote")
    if stored_at is None or not isinstance(quote, Mapping):
        return None
    # Reject materially future-dated entries rather than turning clock skew
    # into an effectively immortal cache record.
    if stored_at > now_epoch + 300:
        return None
    age = max(0, int(now_epoch - stored_at))
    if age > _cache_max_age(chart_range):
        return None
    fallback = dict(quote)
    fallback.update({"cached": True, "stale": True, "cacheAgeSec": age})
    return fallback


def _pruned_cache_entries(
    entries: Mapping[str, Mapping[str, Any]], now_epoch: float
) -> dict[str, dict[str, Any]]:
    retained: list[tuple[float, str, dict[str, Any]]] = []
    for key, entry in entries.items():
        if not isinstance(key, str) or not isinstance(entry, Mapping):
            continue
        stored_at = _finite_number(entry.get("storedAt"))
        chart_range = normalize_chart_range(entry.get("range"))
        if stored_at is None or chart_range is None:
            continue
        if stored_at > now_epoch + 300:
            continue
        if now_epoch - stored_at > _cache_max_age(chart_range):
            continue
        retained.append((float(stored_at), key, dict(entry)))
    retained.sort(key=lambda item: (item[0], item[1]), reverse=True)
    return {key: entry for _, key, entry in retained[:MAX_CACHE_ENTRIES]}


def _prune_history_cache(parent_fd: int, incoming_name: str, incoming_size: int) -> None:
    """Reserve space while holding the directory lock; never follow entries.

    Old versions used the same filenames without aggregate eviction. Read only
    metadata, then evict expired/oldest owned files. Bound even the legacy scan;
    an excessive or unsafe directory disables persistence, never fresh quotes.
    """
    now = time.time()
    entries = []
    with os.scandir(parent_fd) as scan:
        for index, entry in enumerate(scan):
            if index >= MAX_HISTORY_SCAN_ENTRIES:
                raise FetchFailure("cache_too_large", "Too many history directory entries.")
            if not (_HISTORY_FILE_RE.fullmatch(entry.name) or
                    _HISTORY_TEMP_RE.fullmatch(entry.name)):
                continue
            metadata = entry.stat(follow_symlinks=False)
            if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid()
                    or metadata.st_nlink != 1 or stat.S_IMODE(metadata.st_mode) != 0o600):
                raise FetchFailure("cache_unsafe", "Unsafe history cache entry.")
            entries.append((metadata.st_mtime, entry.name, metadata.st_size))

    retained = []
    for modified, name, size in entries:
        # No writer can own a temporary file while we hold this directory lock.
        # Clear abandoned writes, including those left by a terminated helper.
        if _HISTORY_TEMP_RE.fullmatch(name) or now - modified > CACHE_HISTORY_MAX_AGE_SECONDS:
            os.unlink(name, dir_fd=parent_fd)
        else:
            retained.append((modified, name, size))

    # Include the old target plus the temporary replacement in the byte budget.
    # For the entry count reserve one only when this is a new symbol/range.
    total = sum(size for _, _, size in retained) + incoming_size
    count = len(retained) + (not any(name == incoming_name for _, name, _ in retained))
    for _, name, size in sorted(retained):
        if total <= MAX_HISTORY_BYTES and count <= MAX_HISTORY_FILES:
            break
        os.unlink(name, dir_fd=parent_fd)
        total -= size
        if name != incoming_name:
            count -= 1
    if total > MAX_HISTORY_BYTES or count > MAX_HISTORY_FILES:
        raise FetchFailure("cache_too_large", "History cache budget exhausted.")


def _replaceable_cache(metadata: os.stat_result | None) -> bool:
    # Older permissive files may be replaced atomically with private data, but
    # never read as a fallback. Hard links and files owned by others are refused.
    return metadata is None or (stat.S_ISREG(metadata.st_mode)
        and metadata.st_uid == os.getuid() and metadata.st_nlink == 1)


def _write_cache_bytes(path: pathlib.Path, data: bytes) -> None:
    if len(data) > MAX_CACHE_BYTES:
        raise FetchFailure("cache_too_large", "The cache data exceeded the size limit.")
    try:
        parent_fd = _open_cache_parent_fd(path, create=True)
    except OSError:
        raise FetchFailure(
            "cache_unsafe", "The cache path could not be created safely."
        ) from None

    temporary_name = f".{path.name}.{os.getpid()}.{secrets.token_hex(8)}.tmp"
    temporary_fd: int | None = None
    try:
        # A nonblocking lock on the retained directory descriptor serializes
        # writers and eviction without a mutable lock-file path. Busy caches
        # are optional: return fresh data without waiting for another helper.
        fcntl.flock(parent_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if path.parent.name == "history" and _HISTORY_FILE_RE.fullmatch(path.name):
            _prune_history_cache(parent_fd, path.name, len(data))
        try:
            target = os.stat(path.name, dir_fd=parent_fd, follow_symlinks=False)
        except FileNotFoundError:
            target = None
        if not _replaceable_cache(target):
            raise FetchFailure(
                "cache_unsafe", "The cache destination is not a regular file."
            )

        flags = (
            os.O_WRONLY
            | os.O_CREAT
            | os.O_EXCL
            | getattr(os, "O_CLOEXEC", 0)
            | getattr(os, "O_NOFOLLOW", 0)
        )
        temporary_fd = os.open(
            temporary_name, flags, 0o600, dir_fd=parent_fd
        )
        os.fchmod(temporary_fd, 0o600)
        view = memoryview(data)
        while view:
            written = os.write(temporary_fd, view)
            if written <= 0:
                raise OSError("short cache write")
            view = view[written:]
        os.fsync(temporary_fd)
        os.close(temporary_fd)
        temporary_fd = None

        # Recheck the leaf immediately before replacement.  Replacing a link is
        # itself non-following, but refusing it also avoids surprising callers.
        try:
            target = os.stat(path.name, dir_fd=parent_fd, follow_symlinks=False)
        except FileNotFoundError:
            target = None
        if not _replaceable_cache(target):
            raise FetchFailure(
                "cache_unsafe", "The cache destination is not a regular file."
            )
        os.replace(
            temporary_name,
            path.name,
            src_dir_fd=parent_fd,
            dst_dir_fd=parent_fd,
        )
        os.fsync(parent_fd)
    finally:
        if temporary_fd is not None:
            os.close(temporary_fd)
        try:
            os.unlink(temporary_name, dir_fd=parent_fd)
        except FileNotFoundError:
            pass
        finally:
            os.close(parent_fd)


def _store_cache_entries(
    cache_file: pathlib.Path | str | None,
    entries: Mapping[str, Mapping[str, Any]],
) -> None:
    if cache_file is None:
        return
    try:
        path = normalize_cache_path(cache_file)
        payload = {
            "schemaVersion": CACHE_SCHEMA_VERSION,
            "entries": dict(sorted(entries.items())),
        }
        data = json.dumps(
            payload, separators=(",", ":"), sort_keys=True, allow_nan=False
        ).encode("utf-8")
        _write_cache_bytes(path, data)
    except (FetchFailure, OSError, TypeError, ValueError):
        # Cache persistence must never turn a valid provider response into an
        # error or follow a caller-controlled unsafe destination.
        return


def fetch_quotes(
    symbols: Sequence[str],
    initial_errors: Iterable[Mapping[str, Any]] = (),
    *,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
    opener: Callable[..., Any] | None = None,
    chart_range: str = "1d",
    cache_file: pathlib.Path | str | None = None,
    now_epoch: float | None = None,
) -> dict[str, Any]:
    normalized_range = normalize_chart_range(chart_range)
    if normalized_range is None:
        return make_document(
            [],
            [
                *list(initial_errors),
                make_error(
                    None,
                    "invalid_range",
                    f"Range must be one of {', '.join(CHART_RANGES)}.",
                ),
            ],
        )
    if normalized_range != "1d" and len(symbols) != 1:
        return make_document(
            [],
            [
                *list(initial_errors),
                make_error(
                    None,
                    "range_symbol_count",
                    "Chart ranges longer than one day require exactly one valid symbol.",
                ),
            ],
        )

    observed_now = _finite_number(now_epoch)
    if observed_now is None or observed_now < 0:
        observed_now = time.time()
    observed_now = float(observed_now)
    cache_entries = _load_cache_entries(cache_file)
    quotes: list[dict[str, Any]] = []
    errors = list(initial_errors)[:MAX_SYMBOLS]
    live_quotes: list[dict[str, Any]] = []
    # Four workers keep a 12-symbol refresh within the service's overall
    # watchdog even when individual requests consume their full timeout, while
    # avoiding an unbounded burst against the unofficial endpoint.  Results are
    # consumed in input order so the watchlist remains deterministic.
    with concurrent.futures.ThreadPoolExecutor(
        max_workers=min(MAX_WORKERS, max(1, len(symbols)))
    ) as executor:
        jobs = [
            (
                symbol,
                executor.submit(
                    fetch_quote,
                    symbol,
                    timeout,
                    opener,
                    chart_range=normalized_range,
                    now_epoch=observed_now,
                ),
            )
            for symbol in symbols
        ]
        for symbol, job in jobs:
            try:
                quote = job.result()
                quotes.append(quote)
                live_quotes.append(quote)
            except FetchFailure as failure:
                errors.append(make_error(symbol, failure.code, failure.message))
                fallback = _cached_fallback(
                    cache_entries, symbol, normalized_range, observed_now
                )
                if fallback is not None:
                    quotes.append(fallback)
            except Exception:
                errors.append(
                    make_error(
                        symbol,
                        "internal_error",
                        "The quote could not be normalized safely.",
                    )
                )
                fallback = _cached_fallback(
                    cache_entries, symbol, normalized_range, observed_now
                )
                if fallback is not None:
                    quotes.append(fallback)

    if live_quotes and cache_file is not None:
        updated_entries = _pruned_cache_entries(cache_entries, observed_now)
        for quote in live_quotes:
            symbol = quote["symbol"]
            key = _cache_key(symbol, normalized_range)
            updated_entries[key] = {
                "symbol": symbol,
                "range": normalized_range,
                "storedAt": observed_now,
                "quote": quote,
            }
        updated_entries = _pruned_cache_entries(updated_entries, observed_now)
        _store_cache_entries(cache_file, updated_entries)

    generated_at = _utc_iso_from_epoch(observed_now) or utc_now_iso()
    return make_document(quotes, errors, generated_at=generated_at)


def _valid_iso(value: Any) -> str | None:
    if not isinstance(value, str) or len(value) > 40:
        return None
    candidate = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = dt.datetime.fromisoformat(candidate)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return None
    return value


def _sanitize_fixture_quote(
    raw: Any, *, chart_range: str | None = None
) -> dict[str, Any] | None:
    if not isinstance(raw, Mapping):
        return None
    raw_symbol = raw.get("symbol")
    if not isinstance(raw_symbol, str):
        return None
    try:
        symbols, errors = normalize_symbols([raw_symbol])
    except InputLimitError:
        return None
    if errors or not symbols:
        return None
    symbol = symbols[0]

    requested_range = (
        normalize_chart_range(chart_range) if chart_range is not None else None
    )
    if chart_range is not None and requested_range is None:
        return None
    raw_range_value = raw.get("range")
    raw_range = (
        normalize_chart_range(raw_range_value)
        if raw_range_value is not None
        else None
    )
    if raw_range_value is not None and raw_range is None:
        return None
    if (
        requested_range is not None
        and raw_range is not None
        and requested_range != raw_range
    ):
        return None
    normalized_range = requested_range or raw_range or "1d"

    price = _finite_number(raw.get("regularMarketPrice"))
    sparkline, sparkline_timestamps = _bounded_series(
        raw.get("sparkline"), raw.get("sparklineTimestamps")
    )
    if price is None and sparkline:
        price = sparkline[-1]
    if price is None:
        return None
    previous_close = _finite_number(raw.get("previousClose"))
    change = _finite_number(raw.get("change"))
    change_percent = _finite_number(raw.get("changePercent"))
    if change is None and price is not None and previous_close is not None:
        change = _finite_difference(price, previous_close)
    if (
        change_percent is None
        and change is not None
        and previous_close not in (None, 0)
    ):
        change_percent = _finite_number((change / previous_close) * 100)

    currency = _bounded_text(raw.get("currency"), MAX_CURRENCY_LENGTH) or None
    market_time = _valid_iso(raw.get("marketTime"))
    if market_time is None:
        market_time = _utc_iso_from_epoch(raw.get("marketTime"))
    instrument_type = _bounded_text(
        raw.get("instrumentType"), MAX_INSTRUMENT_TYPE_LENGTH
    )
    session_state = _normalized_session_state(raw.get("sessionState"))
    if session_state is None:
        session_state = _normalized_session_state(raw.get("marketState"))
    if session_state is None and instrument_type.upper() in {
        "CRYPTOCURRENCY",
        "CRYPTO",
        "DIGITAL_ASSET",
    }:
        session_state = "continuous"
    session_state = session_state or "unknown"
    return {
        "symbol": symbol,
        "name": _bounded_text(raw.get("name"), MAX_NAME_LENGTH, symbol),
        "currency": currency,
        "exchange": _bounded_text(
            raw.get("exchange"), MAX_EXCHANGE_LENGTH
        ) or None,
        "exchangeTimezone": _bounded_text(
            raw.get("exchangeTimezone"), MAX_TIMEZONE_LENGTH
        ) or None,
        "instrumentType": instrument_type or None,
        "marketState": session_state,
        "sessionState": session_state,
        "regularMarketPrice": price,
        "previousClose": previous_close,
        "change": change,
        "changePercent": change_percent,
        "marketTime": market_time,
        "regularMarketOpen": _finite_number(raw.get("regularMarketOpen")),
        "dayLow": _finite_number(raw.get("dayLow")),
        "dayHigh": _finite_number(raw.get("dayHigh")),
        "fiftyTwoWeekLow": _finite_number(raw.get("fiftyTwoWeekLow")),
        "fiftyTwoWeekHigh": _finite_number(raw.get("fiftyTwoWeekHigh")),
        "volume": (
            volume
            if (volume := _finite_number(raw.get("volume"))) is not None
            and volume >= 0
            else None
        ),
        "sparkline": sparkline,
        "sparklineTimestamps": sparkline_timestamps,
        "range": normalized_range,
    }


def _read_bounded_file(path: pathlib.Path) -> bytes:
    with path.open("rb") as handle:
        data = handle.read(MAX_RESPONSE_BYTES + 1)
    if len(data) > MAX_RESPONSE_BYTES:
        raise FetchFailure("fixture_too_large", "The fixture exceeded the size limit.")
    return data


def load_fixture(
    path: pathlib.Path,
    requested_symbols: Sequence[str] = (),
    *,
    select_symbols: bool | None = None,
    chart_range: str = "1d",
) -> dict[str, Any]:
    """Load a normalized, bounded fixture without making a network request."""

    normalized_range = normalize_chart_range(chart_range)
    if normalized_range is None:
        raise FetchFailure(
            "invalid_range", f"Range must be one of {', '.join(CHART_RANGES)}."
        )

    try:
        raw = _read_bounded_file(path)
    except FetchFailure:
        raise
    except OSError:
        raise FetchFailure(
            "fixture_unavailable", "The quote fixture could not be read."
        ) from None
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError, RecursionError):
        raise FetchFailure(
            "fixture_invalid", "The quote fixture is not valid JSON."
        ) from None
    if not isinstance(payload, Mapping):
        raise FetchFailure("fixture_invalid", "The quote fixture must contain an object.")
    if payload.get("schemaVersion") != SCHEMA_VERSION:
        raise FetchFailure(
            "fixture_invalid",
            f"The quote fixture must use schema version {SCHEMA_VERSION}.",
        )

    raw_quotes = payload.get("quotes")
    if not isinstance(raw_quotes, list) or len(raw_quotes) > MAX_SYMBOLS:
        raise FetchFailure(
            "fixture_invalid", f"The quote fixture must contain at most {MAX_SYMBOLS} quotes."
        )
    quotes: list[dict[str, Any]] = []
    by_symbol: dict[str, dict[str, Any]] = {}
    for item in raw_quotes:
        quote = _sanitize_fixture_quote(item, chart_range=normalized_range)
        if quote is None:
            raise FetchFailure(
                "fixture_invalid", "The quote fixture contains an invalid quote."
            )
        if quote["symbol"] in by_symbol:
            raise FetchFailure(
                "fixture_invalid", "The quote fixture contains duplicate symbols."
            )
        by_symbol[quote["symbol"]] = quote
        quotes.append(quote)

    errors: list[dict[str, Any]] = []
    raw_errors = payload.get("errors", [])
    if not isinstance(raw_errors, list) or len(raw_errors) > MAX_SYMBOLS:
        raise FetchFailure(
            "fixture_invalid", f"The quote fixture must contain at most {MAX_SYMBOLS} errors."
        )
    for item in raw_errors:
        if not isinstance(item, Mapping):
            raise FetchFailure("fixture_invalid", "The quote fixture contains an invalid error.")
        raw_symbol = item.get("symbol")
        error_symbol = raw_symbol if isinstance(raw_symbol, str) else None
        errors.append(
            make_error(
                error_symbol,
                item.get("code", "fixture_error"),
                item.get("message", "Quote unavailable."),
            )
        )

    if select_symbols is None:
        select_symbols = bool(requested_symbols)
    if select_symbols:
        selected: list[dict[str, Any]] = []
        selected_errors: list[dict[str, Any]] = []
        errors_by_symbol = {
            error["symbol"]: error for error in errors if error["symbol"] is not None
        }
        for symbol in requested_symbols:
            if symbol in by_symbol:
                selected.append(by_symbol[symbol])
            elif symbol in errors_by_symbol:
                selected_errors.append(errors_by_symbol[symbol])
            else:
                selected_errors.append(
                    make_error(
                        symbol,
                        "fixture_missing",
                        "This symbol is not present in the selected fixture.",
                    )
                )
        quotes, errors = selected, selected_errors

    provider = _bounded_text(
        payload.get("provider"), MAX_PROVIDER_LENGTH, "Local fixture"
    )
    generated_at = _valid_iso(payload.get("generatedAt")) or utc_now_iso()
    return make_document(
        quotes, errors, provider=provider, generated_at=generated_at
    )


def _failure_document(code: str, message: str) -> dict[str, Any]:
    return make_document([], [make_error(None, code, message)])


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Fetch a bounded set of Yahoo chart quotes as normalized JSON."
    )
    parser.add_argument(
        "--fixture",
        type=pathlib.Path,
        help="read normalized quotes from a local JSON fixture instead of the network",
    )
    parser.add_argument(
        "--symbols",
        dest="symbol_csv",
        default="",
        metavar="CSV",
        help="comma-separated Yahoo symbols (may be combined with positional symbols)",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=DEFAULT_TIMEOUT_SECONDS,
        metavar="SECONDS",
        help=f"per-request timeout from {MIN_TIMEOUT_SECONDS:g} to {MAX_TIMEOUT_SECONDS:g} seconds",
    )
    parser.add_argument(
        "--range",
        dest="chart_range",
        default="1d",
        metavar="RANGE",
        help=(
            "chart range: 1d, 5d, 1mo, 6mo, or 1y; ranges longer than "
            "1d require exactly one valid symbol"
        ),
    )
    parser.add_argument(
        "--cache-file",
        type=pathlib.Path,
        metavar="ABSOLUTE_PATH",
        help=(
            "optional private last-known-good cache (absolute path, 2 MiB maximum; "
            "1d entries live 7 days and longer ranges 30 days)"
        ),
    )
    parser.add_argument("symbols", nargs="*", metavar="SYMBOL")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    if (
        not math.isfinite(args.timeout)
        or args.timeout < MIN_TIMEOUT_SECONDS
        or args.timeout > MAX_TIMEOUT_SECONDS
    ):
        document = _failure_document(
            "invalid_timeout",
            f"Timeout must be from {MIN_TIMEOUT_SECONDS:g} to {MAX_TIMEOUT_SECONDS:g} seconds.",
        )
        print(json.dumps(document, separators=(",", ":"), allow_nan=False))
        return 2

    chart_range = normalize_chart_range(args.chart_range)
    if chart_range is None:
        document = _failure_document(
            "invalid_range", f"Range must be one of {', '.join(CHART_RANGES)}."
        )
        print(json.dumps(document, separators=(",", ":"), allow_nan=False))
        return 2

    if args.cache_file is not None:
        try:
            normalize_cache_path(args.cache_file)
        except FetchFailure as failure:
            document = _failure_document(failure.code, failure.message)
            print(json.dumps(document, separators=(",", ":"), allow_nan=False))
            return 2

    csv_symbols = args.symbol_csv.split(",") if args.symbol_csv else []
    raw_symbols = [*csv_symbols, *args.symbols]
    try:
        symbols, input_errors = normalize_symbols(raw_symbols)
    except InputLimitError as exc:
        document = _failure_document("too_many_symbols", str(exc))
        print(json.dumps(document, separators=(",", ":"), allow_nan=False))
        return 2

    if chart_range != "1d" and len(symbols) != 1:
        document = make_document(
            [],
            [
                *input_errors,
                make_error(
                    None,
                    "range_symbol_count",
                    "Chart ranges longer than one day require exactly one valid symbol.",
                ),
            ],
        )
        print(json.dumps(document, separators=(",", ":"), allow_nan=False))
        return 2

    if args.fixture is not None:
        try:
            document = load_fixture(
                args.fixture,
                symbols,
                select_symbols=bool(raw_symbols),
                chart_range=chart_range,
            )
            if input_errors:
                document = make_document(
                    document["quotes"],
                    [*input_errors, *document["errors"]],
                    provider=document["provider"],
                    generated_at=document["generatedAt"],
                )
        except FetchFailure as failure:
            document = _failure_document(failure.code, failure.message)
    else:
        document = fetch_quotes(
            symbols,
            input_errors,
            timeout=args.timeout,
            chart_range=chart_range,
            cache_file=args.cache_file,
        )

    print(json.dumps(document, separators=(",", ":"), allow_nan=False))
    return 1 if document["status"] == "failed" else 0


if __name__ == "__main__":
    raise SystemExit(main())
