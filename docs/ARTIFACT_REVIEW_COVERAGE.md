# Know whose exact-revision feedback is still missing

An operator can now save an explicit review plan and compare returned feedback
against it. The existing collection only knows included worksheets; it cannot
answer whether an expected reviewer has replied. This workflow makes that gap
visible without treating silence, an unassigned artifact, or `inspected` as
acceptance. It extends the existing offline artifact review CLI.

## Prepare the plan

Use Python 3.9+ and the standard library. Start with the exact portable artifact
export used by your reviewers. Inspect its IDs, then create `assignments.json`:

```json
{
  "assignments": [
    {"reviewer": "Alex", "artifact_ids": ["draft-2", "image"]},
    {"reviewer": "Bea", "artifact_ids": ["draft-2"]}
  ]
}
```

Use actual exact IDs from your packet. List each person's scope explicitly;
there is no automatic assignment to all current or future artifacts.

```sh
python3 tools/artifact_review.py review-plan review-folder assignments.json --title 'Report review' > plan.json
python3 tools/artifact_review.py review-coverage review-folder plan.json > waiting.json
python3 tools/artifact_review.py review-coverage review-folder plan.json --markdown > review-folder/waiting.md
```

With no collection supplied, every assigned pair is `missing_feedback`. This is
a local checklist, not a sent invitation, authenticated reviewer identity,
deadline, review permission or runtime approval. Create and return worksheets
using the existing [review notes](ARTIFACT_REVIEW_NOTES.md) workflow, and save
explicit returned files with [collect](ARTIFACT_FEEDBACK_COLLECTION.md).

```sh
python3 tools/artifact_review.py collect review-folder alex-review.json --title 'Returned feedback' > feedback.json
python3 tools/artifact_review.py review-coverage review-folder plan.json feedback.json > coverage.json
python3 tools/artifact_review.py review-coverage review-folder plan.json feedback.json --markdown > review-folder/coverage.md
```

Keep Markdown beside the manifest for local content/record links. The saved plan
and collection can move with the packet; original worksheet paths and runtime
store are unnecessary. To revise assignments, create a new plan from a new
explicit assignment input. Older plans remain unchanged; no recency or automatic
supersession is inferred. Always redirect into a new file: shell redirection can
truncate an input before Python starts. Check exit status before using output.

## Read the coverage

Every exported artifact appears in packet order, including artifacts with no
assignment. Expected reviewers appear in plan order. Labels match after trimming
outer whitespace and Unicode case folding, the same convention as collections;
both expected and actual display labels remain visible. Same-named people need
distinct labels. Labels and hashes do not authenticate a person.

For each assigned artifact/reviewer pair:

- `missing_feedback`: no matching worksheet was supplied in this collection
- `unreviewed`: a worksheet was supplied but its annotation is still unreviewed
- `inspected` or `needs-changes`: the reviewer's recorded checklist statement

The complete returned note and worksheet digest accompany a present statement.
An absent worksheet has `feedback: null`; it is never synthesized as a review.
No majority rule, inferred withdrawal, acceptance or completion verdict exists.
A reviewer completing one artifact does not satisfy their other assignments.

Feedback for a reviewer/artifact pair outside the plan is retained separately as
`unassigned_feedback`, including unreviewed statements. It cannot fill a missing
assignment, and change requests are not hidden merely because they are outside
scope. `unassigned_artifacts` counts packet artifacts with no expected reviewer.
Summary states count assigned pairs, while unassigned feedback counts returned
pairs outside that scope; these are not task-completion or quality metrics.

The report carries exact input plan/collection byte hashes, manifest identity,
and original run/job/artifact revision and copied-file references. Missing
collection has a null digest. Formatting changes to an input change its digest
without implying semantic review changes. JSON preserves notes; Markdown escapes
notes and labels as inert text. Neither output is a signature or authority grant.

## Bounds and verification

The saved plan schema is `moonclaw.artifact-review-plan.v1`: schema, title,
source, and assignments. Plans require 1–16 distinct reviewer labels and 1–32
unique known artifact IDs per reviewer. Unknown/repeated IDs, duplicate normalized
labels, unsupported fields or malformed plans refuse. Title/label bounds match
the existing collection contract. Every use verifies the whole plan, packet and
all supplied embedded worksheets, including feedback outside assigned scope.
Packet or plan source drift never transfers assignments to another revision.

Inputs and buffered output are capped at 16 MiB; existing collection and packet
limits still apply (1–32 artifacts, 1–16 returned reviewers, 4 MiB per worksheet,
8 MiB combined worksheet bytes). Exit 0 is success, 1 is validation/read failure
with no successful stdout, 2 is an argument error. Output I/O failure can leave
a partial redirected file. Reads assume stable local inputs, not atomic snapshots
against concurrent edits. Inputs/runtime state are never written. No scrubbing,
upload, invitation, dispatch, acceptance or Book promotion occurs.

## Product and test evidence

This implements a bounded reviewer-inspection extension of original PRD MC-W02,
MOONCLAW-B04 and B10: retain exact revisions and distinguish pending inspection
from actual returned statements. It does not qualify the PRD's full plan,
authority, journal, secret-redaction or native host workflow.

```sh
python3 scripts/test-artifact-review.py
python3 scripts/test-artifact-review-collection.py
python3 scripts/test-artifact-review-progress.py
python3 scripts/test-artifact-review-coverage.py
```

The new eight real-file CLI journeys cover no replies, partial replies, explicit
recollection, unreviewed vs missing, extra feedback, portable reopen, revised
scope and exact-source refusal. Each invocation verifies input bytes unchanged.
Set `MOONCLAW_COVERAGE_EVIDENCE` to a fresh directory to retain its files and logs.
Native exporter/runtime, browser/viewer, providers, authenticated identity and
full-product execution were not run. No Moon command or dependency installation
is required for this Python lane. R50 is still the last fully verified cumulative
checkpoint; R51–55 remain separate.
