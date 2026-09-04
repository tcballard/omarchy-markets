# Release checklist

| Gate | Requirement | Evidence or observation | Result | Owner | Next action |
| --- | --- | --- | --- | --- | --- |
| Release identity | Version and candidate commit agree | Manifest 0.3.2; exact commit recorded at handoff | Pass | Tom Ballard | Preserve identity through public push. |
| Claims | Every used claim is verified or visibly qualified | `CLAIMS_LEDGER.md` | Pass | Tom Ballard | Do not promote fixture image as live evidence. |
| Assets | Required outputs exist and open correctly | Root images, issue draft, archive | Pass | Tom Ballard | Replace root preview after live capture. |
| Technical | Submission structure and portable validation pass | Strict validator and complete test suite | Pass | Tom Ballard | Run official validator on installed checkout. |
| Accessibility | Direction is not colour-only and motion can pause | QML/source tests | Pass | Tom Ballard | Confirm keyboard and scaling live. |
| Privacy | No secrets or personal market data | Fixture-only preview and static scan | Pass | Tom Ballard | Capture on a clean workspace. |
| Links | Canonical GitHub and provider disclosures are consistent | README and issue draft | Pass | Tom Ballard | Confirm repository is public before submission. |
| Provenance | Source, preview type, and limitations are explicit | README, capture guide, reviewer notes | Pass | Tom Ballard | Record live screenshot commit and Omarchy SHA. |
| Authority | Publisher and manual action are explicit | Owner approval boundary in issue draft | Pass | Tom Ballard | Approve only after live acceptance. |
