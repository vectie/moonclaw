# Context projection and journal recovery

MoonCode uses one deterministic context compiler for initial planning and every
follow-up. It projects the next provider request; it does not rewrite commands,
tool results, the execution journal or artifacts. No additional model request,
summary service, feature flag or human confirmation is required.

## Model window

The default working window is the smaller of 9,472 tokens and the configured
model's `safe_zone_tokens`. The existing `payload.planner_context_window_tokens`
can request a larger or smaller window, bounded by known model capacity, or
supply an otherwise unknown one. Input budget is the smaller of 75% of that window and
the window minus the request's output-token allowance. Tool schemas count
toward the input budget. Counts use the existing cl100k tokenizer, so they are
estimates for other providers. Its immutable vocabulary is initialized lazily
once per process rather than rebuilt for every planner request.

In-budget messages remain unchanged. On overflow, the existing compiler
replaces a coherent history span, including old calls and results, with its
bounded deterministic checkpoint. The separate output-clearing pass is removed:
it kept large historical edit arguments and call/result wrappers after omitting
the observations. The complete instruction/task prefix and latest
complete exchange remain. Follow-ups refresh the canonical task, including its
ordered revisions, before projection. Tool calls and results stay paired.

Unknown windows, unsupported provider message shapes and compiler errors leave
the original messages intact with a reason. Malformed overflowing tool batches
are not transformed. An immutable prefix or newest exchange that cannot fit
remains a minimum safe projection with `within_budget=false`; this is not a
promise that every possible input fits or an execution stop/approval gate.

The 32-message suffix, active/shadow experiments, provenance-v1
reader and repeated per-follow-up output clipping were removed. Tool execution
still owns its explicit output limits and artifact references. Tool results
enter Context as complete JSON with their evidence reference; they are no
longer cut mid-JSON at a separate 4k/40k planner limit. Transport retries the
same compiled request and never changes the task to handle provider overload.

## Evidence and recall

The bundled MoonBit skill is maintained under `internal/skills/system` and
embedded with the existing generator. Its small entrypoint links optional
language/build references. The complete Markdown instruction body has one copy
in the protected prefix. The existing YAML parser separates standard routing
frontmatter (`name`, `description`, `license`, `allowed-tools`), whose full data
stays in the registry and canonical result. Unknown/custom frontmatter, plain
resources and reference files remain verbatim; no instruction summary is made.
Its tool message keeps status/location
and the journal reference. Later follow-ups rebuild this prefix from existing
results, including after restart. The separate loaded-skill receipt and its
string-prefix filter were removed; instruction bytes survive context pressure.
Failed or unlocated skill reads still return their output. Generic
long guides should not be duplicated into the always-read entrypoint.

Task revisions and saved cross-command notes have one owner in the task
prefix. Current checkpoints remain in tool history. The former automatic
task/recent-results message and cumulative read/error index are removed. The
transcript retains observations; compacted spans use the existing result ranges.
Model result projection uses a JSON status/reference header followed by raw
output text, avoiding JSON escaping of source and logs. It omits repeated audit
fields, verification-input inventories and internal grant digests; canonical
journal facts remain intact. Empty task/context sections are not sent.
Status, message, metadata and evidence_ref share one header object; there is no
outer result wrapper or duplicate tool name (the tool_call_id already binds the
protocol call). This changes only model presentation, not the canonical result.
Exact result JSON remains available through `read(evidence_ref=..., details=true)`.
Exit/error/truncation/limit/artifact data remain.

Projection is lossy. A checkpoint contains working observations, not exact
source evidence or a proof of completion. Retained messages preserve provenance.
A compacted span keeps its first/last result IDs, including across repeated
compaction. Existing file reads,
installed-skill reads and available artifact/backend retrieval remain the
recall paths. Do not replay a mutation to recover its old output.

The read-only `read` tool selects a workspace file with `path`, or scans the
current session journal with `evidence_ref`. The latter reuses the existing
reader; there is no separate `read_result` model schema or compatibility alias.
With `end_ref`, it lists result references in that inclusive
range; an individual reference reads the saved output directly.
`start_line`/`end_line` select saved output lines, preserving their exact text.
Use `details=true` for canonical result JSON, including metadata; line ranges
then address JSON lines. The default receipt's `source` records the original
ok/message/truncated status, separately from successful retrieval. Original
tool truncation cannot be repaired by reading a retained result.
`max_output_chars` defaults to 12000. Metadata reports line count and truncation.
Missing references return an ordinary tool error. No original operation runs.
This recovers retained tool output, not stdout already truncated by the tool,
missing artifacts or overwritten source versions. There is no new index,
automatic recall model call or mandatory retrieval stage.

The working window remains9,472 after the earlier ABI calibration; the latest
cleanup does not shrink it. Same-window ablations separate the read ABI,
bundled-guide duplication and complete-exchange compaction. The default producer
replays12 frozen responses at51,208 tokens (one warmup plus seven measurements),
with edit inputs, full selected instructions and final verdicts retained.
Conditional profile/recall/directory-plus-recall cases include all13/13/14 requests.
The earlier ABI sweep's rejected windows remain historical evidence, not a claim
that this implementation has been qualified at other defaults.
This is the existing soft projection, not an execution stop/budget gate. The original
test file is still read whole; older presentations are replaced by journal
references after consumption. Fixed-trace savings do not prove new model
decisions, zero recall requests, cash savings or quality across larger tasks.
See the [same-window benchmark](../../moondesk/docs/MOONCODE_INPUT_BENCHMARK_2026-11-08.md#整段历史压缩与读取接口收敛).

The protected skill prefix keeps complete selected instructions. The default
system index contains IDs; `read_skill()` reuses the full catalog for descriptions,
and `read_skill(name=...)` retains full instruction/reference loading. Native
tool selection derives declared `allowed_tools` from accepted, journal-backed
skill results at each model request. There is no second selected-tool store.
Explicit tool selection and existing read-only/MCP/worker boundaries still
apply; visibility grants no execution authority. Normal follow-ups reuse their
retained system index instead of reloading an ignored catalog argument.

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
before/after token estimates, compacted-message counts, and
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

Referenced omitted results carry only `evidence_ref` and `context_omitted`;
the same generic recall paragraph is no longer repeated in every handle.
Unreferenced results keep the existing omission/no-effect-replay notice. The
source journal, exact result reader and pressure/window rules are unchanged.
The measured follow-up in the sibling Pi input-gap report counts schema,
skill listing and reference changes through continuous compilation; smaller
framing can retain more older evidence, so field savings do not add linearly.
