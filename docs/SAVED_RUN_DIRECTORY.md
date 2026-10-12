# Discover saved runs before inspecting them

`list_runs` turns explicit saved MoonClaw JSONL journals into a browsable run
directory. Operators can find the run behind an old objective, see its latest
recorded run-level status, then open its evidence with `run_journal`. This avoids
knowing a run ID in advance or paging through thousands of observations. It is
an offline discovery workflow supporting PRD MC-W01/MC-W07 and MOONCLAW-B10,
not a recovery controller or release qualification.

## Use

```sh
list_runs saved/events.jsonl saved/archived-events.jsonl --markdown
list_runs saved/events.jsonl --query "cost report" --job job-1
list_runs saved/events.jsonl --offset 50 --limit 50
run_journal saved/events.jsonl --run RUN_ID_FROM_DIRECTORY --markdown
```

Use the same stable input files when opening a discovered run. A directory card
is one exact `(job_id, run_id)` pair. A reused run ID in different jobs produces
separate cards with `ambiguous_run_id: true`, including when a job filter hides
the other pair. Existing run-only commands do not accept a job selector. For an
ambiguous ID, inspect the original source records directly; do not treat a
run-only result as the selected job or silently discard another job's events.

`--job` matches exactly and case-sensitively. `--query` is a case-insensitive
substring across either ID or any message in that run. The combination is AND.
Matching a message selects the complete pair's history, not just its matching
events. Cards sort by latest timestamp descending, then job ID and run ID in
lexical order. Within a card, equal timestamps retain input-file and physical
line order. Duplicate observations count separately. Source lists are in first
chronological-observation order. No durations, terminal states, safe actions,
effects, retry eligibility or factual acceptance are inferred.

Each card contains event and distinct step counts, first/last producer integer
timestamps, contributing filenames, the complete last event and provenance,
and the latest status-bearing run-level event with its provenance. A step's
`Succeeded` status never becomes the run's status. A later status-less event
does not erase an earlier recorded run status. An empty step ID is still a step.
Unknown structured statuses and explicit JSON null are preserved.

Default output is JSON (`moonclaw.saved-run-directory.v1`); `--markdown` gives
inert escaped text without generated links. In derived JSON objects, an absent
optional value is an omitted property. A present value is unwrapped: numeric
`next_offset`, object `status_source`, or any recorded `last_run_status` JSON.
Explicit null status is a present `last_run_status: null` with `status_source`;
no run-level status omits both. Follow `next_offset` until it is absent.

## Bounds and limits

The default page has 50 cards; `--limit` permits 1–100 and `--offset` must be
nonnegative. Out-of-range offsets and empty selections return an empty page.
Inputs are 1–32 distinct explicit filenames, each bounded by the existing reader
to 4 Mi UTF-16 code units, with at most 10,000 combined events. File spelling
aliases are not detected. Use `./--name.jsonl` for filenames beginning `--`.
All supplied events are validated, including records later excluded by filters.
The command buffers output and refuses over 16 Mi UTF-16 code units before
writing successful stdout. Reduce the page limit if needed. Files are read
before their text bound is checked, and output is assembled before its bound
is checked; this is not constant-memory streaming.

Success exits 0; invalid flags, bounds, records or files exit 1 with a diagnostic
on stderr and no successful stdout. OS output failures can leave partial output.
Work from stable saved files: no atomic snapshot or live refresh is taken. These
are old producer timestamps, with no wall-clock conversion. Messages and event
data are not redacted; review results before sharing. Shell output redirection
can overwrite destinations independently of the program.

## Host API and verification

```moonbit
let entries = @job_journal.parse_journal(text, source="saved/events.jsonl")
let directory = @job_journal.journal_run_directory(entries, query="cost report")
```

Four added tests and the existing 24 package tests pass on the pinned JS target.
The retained native smoke discovers runs across two journals, opens an
unambiguous result through the existing explorer, checks status provenance,
collisions, pagination beyond 100 runs, unknown/null/missing statuses, unchanged
inputs and visible failures. Run this round's `verify.sh NEW_LABEL` for a fresh
retained reproduction. Coverage is local synthetic fixture evidence, not a live
runtime, actual operator study, provider result or cumulative product test.
