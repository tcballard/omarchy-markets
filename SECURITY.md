# Security

Omarchy Markets runs inside the unsandboxed, long-lived `omarchy-shell`
process. Please report suspected vulnerabilities privately through GitHub's
security-advisory interface once this repository is public. Do not include
credentials or private market/watchlist data in a public issue.

## Boundary

- No `sudo`, `pkexec`, package installation, executable download, account,
  API key, telemetry, or plugin-owned daemon.
- One bundled Python helper uses only the standard library and contacts the
  fixed HTTPS host `query1.finance.yahoo.com`.
- Symbols are syntax-checked, capped, and percent-encoded. They never enter a
  shell command.
- Response bytes, output, errors, symbols, workers, points, cache size,
  request duration, retries, and refresh frequency are bounded.
- Regenerable last-known-good quote data and per-symbol/range history data use
  separate bounded files under the user's XDG cache directory with owner-only
  permissions. They contain public symbols and quote data, never credentials.

Static validation is useful evidence for an exact commit, not a security audit
or guarantee.
