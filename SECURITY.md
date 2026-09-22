# Security

Omarchy Markets runs inside the unsandboxed, long-lived `omarchy-shell`
process. Please report suspected vulnerabilities privately through GitHub's
[security-advisory interface](https://github.com/tcballard/omarchy-markets/security/advisories/new). Do not include
credentials or private market/watchlist data in a public issue.

## Boundary

- No `sudo`, `pkexec`, package installation, executable download, account,
  API key, telemetry, or plugin-owned daemon.
- One bundled Python helper uses only the standard library and contacts the
  fixed HTTPS host `query1.finance.yahoo.com`.
- `/usr/bin/python3 -I -S` disables inherited Python paths and site startup.
  Both workers clear their environment and pass only a fixed UTF-8 locale;
  inherited proxies, custom certificate paths and loader variables are omitted.
- Symbols are syntax-checked, capped, and percent-encoded. They never enter a
  shell command.
- Response bytes, output, errors, symbols, workers, points, cache size,
  request duration, retries, and refresh frequency are bounded.
- Regenerable last-known-good quote data and per-symbol/range history data use
  separate bounded files under the user's XDG cache directory with owner-only
  permissions. They contain public symbols and quote data, never credentials.
- Cache reads open nonblocking and validate regular-file type, owner, 0600
  permissions and a single link on the opened descriptor. Directory traversal
  refuses symlinks and untrusted writable ancestors; the final directory must
  be owned by the user with mode 0700. Unsafe caches are ignored.
- Per-symbol history files share a 60-file / 8 MiB budget, including temporary
  replacement bytes, and 30-day expiry. A nonblocking directory lock serializes
  eviction and writes. Busy or unsafe storage never prevents fresh quotes.

Static validation is useful evidence for an exact commit, not a security audit
or guarantee.
