# Context projection and journal recovery

MoonCode uses one deterministic context compiler for initial planning and every
follow-up. It projects the next provider request; it does not rewrite commands,
tool results, the execution journal or artifacts. No additional model request,
summary service, feature flag or human confirmation is required.

## Model window

The configured model's `safe_zone_tokens` supplies the window. Optional
`payload.planner_context_window_tokens` can narrow a known window, or supply an
otherwise unknown one. Input budget is the smaller of 75% of that window and
the window minus the request's output-token allowance. Tool schemas count
toward the input budget. Counts use the existing cl100k tokenizer, so they are
estimates for other providers. Its immutable vocabulary is initialized lazily
once per process rather than rebuilt for every planner request.

In-budget messages remain unchanged. On overflow, the existing compiler first
omits older tool output, then replaces a coherent history span with a bounded,
deterministic checkpoint. The complete instruction/task prefix and latest
complete exchange remain. Follow-ups refresh the canonical task, including its
ordered revisions, before projection. Tool calls and results stay paired.

Unknown windows, unsupported provider message shapes and compiler errors leave
the original messages intact with a reason. Malformed overflowing tool batches
are not transformed. An immutable prefix or newest exchange that cannot fit
remains a minimum safe projection with `within_budget=false`; this is not a
promise that every possible input fits. There is no secondary suffix fallback.

The 32-message suffix, active/shadow experiments, threshold knobs, provenance-v1
reader and repeated per-follow-up output clipping were removed. Tool execution
still owns its explicit output limits and artifact references. Tool results
enter Context as complete JSON with their evidence reference; they are no
longer cut mid-JSON at a separate 4k/40k planner limit. Transport retries the
same compiled request and never changes the task to handle provider overload.

## Evidence and recall

Task revisions and saved cross-command notes have one owner in the task
prefix. Current checkpoints remain in tool history. The former automatic
task/recent-results message is removed. A compact cumulative index retains
read paths/completeness and errors, without copying shell commands, excerpts
or output hashes. Model result projection also omits verification-input
inventories and internal grant digests; canonical journal facts remain intact.

Projection is lossy. A checkpoint contains working observations, not exact
source evidence or a proof of completion. Retained messages preserve provenance. Cleared tool messages keep their result
ID; a compacted span keeps its first/last result IDs, including across repeated
compaction. Existing file reads,
installed-skill reads and available artifact/backend retrieval remain the
recall paths. Do not replay a mutation to recover its old output.

The read-only `read_result` tool scans the current session journal by
`evidence_ref`. With `end_ref`, it lists result references in that inclusive
range; then an individual reference retrieves the canonical retained result.
`start_line`/`end_line` select lines of its JSON representation and
`max_output_chars` defaults to 12000. Metadata reports line count and truncation.
Missing references return an ordinary tool error. No original operation runs.
This recovers retained tool output, not stdout already truncated by the tool,
missing artifacts or overwritten source versions. There is no new index,
automatic recall model call or mandatory retrieval stage.

## Journal

One checkpoint writer stores the current plan, compact historical step metadata,
completed-result references and the position in the existing loop. A single
`MoonCodeResumePoint` decoder covers tool positions, explicit approval, planner
quantum pauses, transport interruption and empty-response replanning. It is a
decoded value, not another scheduler or state machine. Approval IDs still bind
the exact command and tool occurrence. Rejected finish recovery retains its
specific execution fact; guidance wording and generated ID formatting are not
authorization requirements.

A completed operation event owns its execution header and canonical
`tool_result` once. Checkpoint references carry only `event_id` and
`event_digest`; synthetic results without that committed representation
carry `inline_execution`. There is no duplicate header or `journaled_result`
Boolean in a reference. Storage shape, not display event name, selects the
representation, so patch/finish events can be referenced too. Operation
recovery and checkpoint hydration use the same
`mooncode_tool_execution_from_event` projection. No legacy-format adapter
or new validation stage is introduced.

The existing ResumePoint also chooses model continuation directly: tools
reuse the saved plan, initial transport retry uses initial planning, and
quantum/transport/replan follow-ups share one request assembly with their
retained steering/guidance. The enum and execution loop states are unchanged.

Only the latest checkpoint is hydrated. Referenced result IDs must be unique,
in order and present before that checkpoint, with matching event digests.
Malformed references raise `InvalidJournal`, rather than looking like an empty
session. The redundant digest over the whole accumulated result body and old
inline-checkpoint fallback are removed. Synthetic nonjournaled results can still
be represented inline by the current reference format. Existing operation
identity prevents replay of completed effects; an intent without a committed
result remains unknown and requires reconciliation.

Every append synchronizes file bytes. The existing size/boundary-validated
append cache also remembers successful directory synchronization. A cache hit
avoids reopening every ancestor. First observation, restart or cache invalidation
conservatively syncs the directory chain; a failed sync is retried even when the
record's identity already exists. Archive/restore and other directory mutations
invalidate cached durability before transition intent and retain their own
synchronization. Supported-platform filesystem semantics still
apply; the Windows directory-sync helper remains a no-op. This is not a new
index or a universal external-writer durability guarantee.

Checkpoint construction still traverses accumulated references and retains the
current model transcript once. Removing duplicate body hashing does not make
arbitrary checkpoint size constant. Normal journal append reuses the existing
incremental scan cache instead of scanning all prior records.

Normal context counting still costs time proportional to input and schema size;
the cached tokenizer avoids repeated vocabulary construction, not tokenization.

## Observability and checks

Planner results expose `context_projection`: `applied`, `input_budget_tokens`,
before/after token estimates, redacted-result and compacted-message counts, and
`within_budget`; unprojectable input reports a reason. These metrics carry no
prompt text or tool output. They do not decide task acceptance.

```sh
moon test --target native cmd/daemon/mooncode_context_wbtest.mbt
moon test --target native internal/context_pruner
moon test --target native cmd/daemon/mooncode_runtime_continuation_wbtest.mbt
moon test --target native cmd/daemon/mooncode_session_journal_streaming_wbtest.mbt
```

Tests cover default compaction, current-task preservation after hydration, recent
verification, source provenance, unknown effects, cancellation, torn-tail
repair, append-cache invalidation and directory-sync failure/retry. Local
fixtures do not establish live-provider deliverable quality or power-cut behavior.
