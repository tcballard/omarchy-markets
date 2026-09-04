# Launch brief

- Product: Omarchy Markets
- Release: Marketplace candidate
- Version: 0.3.2
- Build: Exact Git commit recorded after submission-prep changes
- Release state: Prepared for public-repository publication and owner live acceptance
- Release date or window: After live Omarchy capture and owner checklist approval
- Authoritative source: `manifest.json`, committed source, tests, and `docs/acceptance.md`

## Audience and outcome

- Primary audience: Omarchy users who want a native market ticker and compact quote scanner
- User outcome: Start from a useful profile, scan prices in the bar, and inspect history without an account or API key
- Launch objective: Earn a reviewed community marketplace listing and provide evidence suitable for a future default-plugin proposal
- Primary call to action: Install the public repository, enable the widget, and choose a profile
- Canonical destination: `https://github.com/tcballard/omarchy-markets`

## Availability and boundaries

- Platforms and minimum versions: Omarchy 4 with Quattro plugin support; Python 3.10+
- Rollout or eligibility: Community plugin; no account required
- Pricing: Free and open source under MIT
- Material limitations: Yahoo chart data is unofficial and best effort; no trading, holdings, recommendations, alerts, or real-time guarantee
- Required disclosures: Unsandboxed plugin code, fixed Yahoo network destination, bounded local cache, fixture preview until live capture

## Delivery contract

- Included channels: Repository, marketplace submission, release archive, owner capture checklist
- Deliberately omitted channels: Website, social launch, demo video, press, and public release announcement
- Format or submission constraints: One public root plugin, root README/license/preview, category `Widgets`, tags `bar` and `quickshell`, exact six-heading issue body
- Accessibility requirements: Signed arrows and text accompany colour; ticker motion is pausable; screenshot text must remain readable
- Publication authority: Tom Ballard must approve the exact issue checklist before submission

## Evidence summary

- Release artifact or verified build: Exact-commit ZIP produced locally after final commit
- Tests and measurements: 64 Python/source tests, 50 model tests, 23 lifecycle tests, fixture validation, strict manifest validation
- Specification and acceptance criteria: `docs/design.md` and `docs/acceptance.md`
- Build logs and decisions: Git history and `CHANGELOG.md`
- Existing assets and copy: `preview.png`, `preview-profiles.png`, README, submission issue draft, reviewer notes
