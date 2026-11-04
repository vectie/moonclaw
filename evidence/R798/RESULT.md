# R798: saved Git unified-diff intake

Implemented 2026-10-20 in the isolated R798 MoonClaw working copy. Baseline:
`sources/moonclaw`, HEAD provenance `67b9ea298f538dbb48a20cc2356f4d3b5ce9ae4c`,
including the source handoff's existing authored overlays, untouched.

Grounding: authored MoonClaw PRD MC-W01 (objective/input references before plan),
`docs/PRODUCT_CONTRACT.md` (operator-reviewed runtime work), existing
`source-brief.js`, `source-brief-controls.js`, `main/cowork_surface.mbt` and
`main/update.mbt`. This fills saved unified-diff selection, distinct from the
already implemented two-snapshot comparison and generic line selection.
Workspace AGENTS and MoonBit Agent Guide were read. No authored PRD changed.

## Implementation

- Parse saved Git file sections and complete text hunks, retaining exact bytes.
- Navigate files/hunks, keep/drop exact hunks across files, preview in patch order.
- Capture request and checks, then transactionally stage one selected-diff source
  excerpt into the existing source brief, with original-file digest provenance.
- Reuse existing brief preview/apply and composer input event. Preserve ordinary
  Plan endpoint and all subsequent user-controlled execution/release gates.
- Existing source budgets and file decoding are reused. No new dependencies,
  native changes, provider access, repository mutation or approvals introduced.

## Test evidence

`functional-tests.txt`: 70 tests, 70 passed, zero failed/skipped.
Command is documented in `docs/SAVED_DIFF_INTAKE.md`.
Three `node --check` invocations passed for saved-diff.js,
saved-diff-controls.js and source-brief-controls.js.
Node v24.19.0. Available MoonBit CLI observed as moon0.1.20261016
(1af328f, 2026-10-16), but no native/MoonBit build was required or run for this
JavaScript-only change; no historical compiler pin is claimed tested.

The first test run had a test-only assumption that Plan sends `content`; source
inspection showed the actual field is `request_text`. The assertion was corrected
to the production contract and all tests rerun. No runtime behavior was changed
to satisfy that incorrect assertion.

Independent review identified actual Git combined-file headers (`diff --cc` and
`diff --combined`) were not explicitly diagnosed, including in mixed normal/
combined patches. Added a small explicit unsupported-input check and realistic
combined-only/mixed regression cases within the focused parser test. Reran all
70 tests successfully after the fix; neither mixed patch is partially imported.

Limits: mounted fake DOM and source-level ordinary Plan wiring only; no visual
browser test, compiled MoonBit UI, real gateway/provider, remote agents, clean
installation or multi-day runtime tests. No claim of release readiness. Parent
independent review/acceptance and Library delivery are separate pending steps.
No generated build caches or package staging were created by this round.
