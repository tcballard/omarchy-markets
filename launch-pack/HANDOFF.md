# Launch handoff

- Product: Omarchy Markets
- Release: Marketplace candidate
- Version: 0.3.2
- Build: Exact Git commit and archive digest recorded at final handoff
- Pack status: Prepared for public push and owner live acceptance
- Publication authority: Tom Ballard; no marketplace issue may be created without explicit approval of the final body
- Exact next action: Publish `tcballard/omarchy-markets`, install from that URL on Omarchy, complete `docs/capture.md`, and replace `preview.png`

## Included deliverables

| Channel | Output | Status | Claim IDs | Notes |
| --- | --- | --- | --- | --- |
| Repository | `README.md`, source, docs, CI | Prepared | C01–C05 | Public origin is the remaining distribution step. |
| Marketplace | `submission/marketplace-issue.md` | Prepared | C01–C05 | Exact issue structure; owner approval still required. |
| Review | `submission/reviewer-notes.md` | Prepared | C03–C05 | Discloses process, network, cache, and preview boundaries. |
| Live acceptance | `docs/capture.md` | Qualified | C01–C05 | Must be executed on Omarchy by the owner. |

## Omitted or not-applicable deliverables

- Website, social posts, product demo video, press package, and public launch copy are intentionally omitted.

## Claims

- Verified: Core source behavior, profiles, consent boundary, ranges, caching, dependency and network boundary.
- Qualified: Live rendering, interaction, scaling, and lifecycle behavior await owner Omarchy acceptance.
- Blocked or removed: The deterministic preview must not be called live product evidence.

## Validation performed

- Complete portable tests and strict manifest validation.
- Current local advisory marketplace scan: no findings; one `qml-process` review capability.
- Preview opened at delivery dimensions and checked for fictional-only data.
- Marketplace contract rechecked against `omacom/omarchy-plugin-marketplace` on 1 September 2026.

## Remaining decisions and blockers

- Create and publish the canonical GitHub repository.
- Run the official install/capture checklist and replace the root preview.
- Obtain explicit owner approval for all five marketplace attestations before creating the public issue.
