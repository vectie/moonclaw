# Send completed Claw text to Book

Open a completed run → Artifacts → **Send completed output to Book**.

1. Select the exact retained text artifacts and choose **Freeze selected text**. Inspect run status, original run and artifact records, artifact versions, byte digests and full retained text in the collapsed source details
2. Write your interpretation and limits, observation time, and each Information / Recognition / Decisiveness gap explicitly. If a gap is present, Book's existing contract requires all three proposed-capability fields. This proposal grants no authority
3. Choose **Export outcome for Book**. The source is read again before export: a changed run, artifact record or byte sequence blocks a new export and preserves your old handoff
4. Import the file in Book → Product outcomes, inspect retained evidence, and use the existing named-reviewer controls. Deliverable acceptance and Three-Gap review remain separate. Reject, request revision and escalate keep their existing meanings. Nothing here accepts, activates or sends automatically
5. Download Book's refreshed disposition receipt. Back in Claw, open the exact saved handoff, then import its matching Book receipt. Inspect the returned original text and all imported historical observations. Download exact original UTF-8 bytes with the source-index control

The file retains exact source bytes, including a UTF-8 BOM, non-ASCII text and NUL characters. Invalid UTF-8, binary media types, missing artifacts, wrong owners and oversize sources are refused. The Book payload limit is 8 MiB, including source context and interpretation; source files cannot be truncated or silently omitted. Fort's independent byte download is unaffected by this text-only handoff.

## Recovery and source identity

The browser attempts to save your draft, frozen source, last handoff and receipt history for reload. If browser storage is unavailable or full, the panel tells you to download a handoff or draft recovery before closing. Downloaded handoffs are immutable source snapshots. A recovery file also preserves unexported edits and prior source versions; use **Open draft recovery** to restore it. Earlier source indices reopen old saved handoffs without replacing the live run, and later work remains in history.

Duplicate pending clicks are ignored. Interrupting or navigating to another run/gateway invalidates pending reads. Late replies do not replace newer drafts. Failed reads/imports preserve previous sources. Changed interpretation creates a distinct identity and clears the new handoff's Book observations while keeping the previous handoff and its receipts in history.

Returned Book files are unsigned historical local observations. Import order does not establish freshness: earlier and later observations remain individually visible. A receipt for another source/package is refused until its matching saved handoff is explicitly opened. Reopen Book and refresh before relying on current decisions. Run completion does not prove correctness, customer acceptance, cash or capability activation.

## Bounded implementation

- `POST /v1/jobs/runs/{run}/book-outcome-source` is an authenticated read-only endpoint. Browser input contains artifact IDs only; the host resolves owned records and files. The endpoint does not run work or write Book state
- `ArtifactStore::freeze_book_outcome_source` requires terminal Succeeded/Failed/Cancelled plus recorded finish time, validates exact run/job ownership, strictly decodes UTF-8, and re-reads every selected record and byte sequence before returning a frozen source
- `moonclaw.book-outcome-source.v1` carries exact `source_json`, its SHA-256 and retained texts. Context contains original run/artifact records, byte lengths and digests. The final immutable package includes this context, each original text, and the authored interpretation
- The producer exports the existing `moonbook.product-outcome-package.v1` and reads `moonbook.product-outcome-readback.v1`. Book production code is unchanged

## Verification scope

Native local lifecycle and ArtifactStore fixtures produce actual text with truthful synthetic provenance. The shipped JS producer exports those bytes; the unchanged Book production CLI/store imports them. Isolated tests install synthetic existing reviewer decisions, and the shipped Claw return validator reopens acceptance, rejection, revision and escalation receipts. An actual authenticated local gateway additionally exercises the shipped source controls and transport with only the DOM/download boundary simulated.

These are cloud/native/controller checks, not live-browser file-saving, installed app, Mac, real-provider, real-human-review, hardware, customer or cash acceptance. No provider run is required or implied.
