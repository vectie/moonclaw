# Supervisor runtime v1

MoonClaw is the sole generic execution runtime for durable supervisors. Profile
producers activate an opaque, immutable snapshot using contract
`moonsuite.supervisor-profile-activation.v1`; `source_product` is a canonical
lowercase product ID and is not restricted to any particular producer.

## Authority and command identity

Every mutation carries `moonclaw.supervisor-command.v1` with `command_id`,
`request_digest`, `issued_at`, canonical `evaluated_at`, optional
`expected_cursor`, and a MoonLib authority decision. The digest is SHA-256 over
the exact operation payload JSON only. MoonClaw publishes canonical builders in
`job/supervisor_types.mbt` for activate, message, wake, steer, stop,
retry/resume, delegation, and outcome evidence. The daemon also resolves the
exact `moonclaw/supervisor.<operation>@0.1.5` operation through MoonGate before
accepting it.

`issued_at` and all supervisor-owned epoch-millisecond provenance fields use a
canonical non-negative decimal-string wire backed by Int64. Town values above
JavaScript's safe-integer range therefore round-trip exactly. They are never
converted into legacy JobRun timestamps: those boundaries use an independent
process-local runtime tick. Worker evidence correlates the two lanes as
`timestamp_correlation.issued_at_ms` and
`timestamp_correlation.runtime_timestamp`.

Accepted HTTP responses are top-level
`moonclaw.supervisor-command-receipt.v1` objects with `status: "accepted"`, a
durable cursor/event ID, `duplicate`, and an operation-specific `response`.
The delegate endpoint returns a `moonclaw.supervisor-delegate-intent-result.v1`
wrapper containing the durable intent receipt, optional provider-acceptance
receipt, and exact worker status.
Same command ID plus same digest is idempotent; a divergent reuse is rejected.

## HTTP surface

- `POST /v1/supervisors/activate`
- `POST /v1/supervisors/{id}/commands/message`
- `POST /v1/supervisors/{id}/commands/{wake|steer|stop|retry-resume|delegate}`
- `POST /v1/supervisors/{id}/commands/worker-steer`
- `POST /v1/supervisors/{id}/commands/worker-stop`
- `POST /v1/supervisors/{id}/commands/worker-retry-resume`
- `POST /v1/supervisors/{id}/commands/{mailbox-claim|mailbox-ack}`
- `POST /v1/supervisors/{id}/commands/outcome-evidence`
- `POST /v1/supervisors/{id}/commands/{outbox-claim|outbox-ack}`
- `GET /v1/supervisors/{id}/status`
- `GET /v1/supervisors/{id}/events?after_cursor=<n>&limit=<n>`

Activation installs the exact digest-bound `runtime_profile` as the executor's
system prompt before accepting a new command. A profile upgrade reinstalls it
even when the executor is already running. Duplicate activation can respawn the
same stopped executor UUID, reinstall the snapshot, and drain pending messages.
The immutable runtime binding must name an exact model. Activation, restore,
and resume fail closed if that model is unavailable or if an already-running
executor registered a different model; task spawning never falls back to the
daemon default.

## Runtime, recovery, and delegation

Each supervisor has one canonical daemon task UUID, used as the existing
MoonClaw `JobRun` ID. Stop retains that identity; wake and retry resume it rather
than allocating a second runtime. The JSONL journal at
`.moonsuite/products/moonclaw/jobs/supervisors/journal.v1.jsonl` is authoritative
and startup replay restores active executors. Message and steer delivery is
outbox-driven and acknowledged only after the task accepts the message.

A real parent-executor `AssistantMessage` followed by `PostConversation` is
durably journaled as event type `supervisor.assistant.responded`. The exact
reply is `latest_event.payload.assistant_response` in supervisor status, with
contract `moonclaw.supervisor-assistant-response.v1`, source/delivery event
IDs, conversation/task correlation, exact `responded_at`, executor identity,
content, and provider evidence. It is paired with the earliest delivered
message that has not yet received a response and inherits that message's
already-verified authority; recording a response cannot delegate or grant new
authority.

The delegate command accepts a high-level instruction with explicit task,
claim, budget, artifact, lifetime, workspace, and network bounds. It does not
accept an accounting assertion. MoonClaw resolves accounting from the
host-only `MOONCLAW_SUPERVISOR_WORKER_ACCOUNTING_MODE`; unknown mode fails
closed, and metered-external remains unavailable without cost-meter evidence.
MoonClaw owns
worker IDs, creates or restores the actual child JobRun beneath the existing
job.delegate step, issues the receiver-bound delegation, and dispatches it
through the daemon's existing agent-task provider. Provider acceptance is the
only transition to running; provider lifecycle events are the only ordinary
terminal transition.

Child-specific worker-steer, worker-stop, and worker-retry-resume endpoints validate
persisted lineage and target that exact provider task. Canonical supervisor
controls and ordinary supervisor messages remain separate.

The immutable runtime binding must declare max_active_workers. MoonClaw counts
nonterminal persisted child lineage before every new delegation. Each provider
gets a unique runtime-owned execution directory, while the requested cwd
remains the explicit governed target workspace, so multiple bounded workers
can operate concurrently without sharing daemon task identity.

Delegation use is authorized before provider dispatch and its use receipt is
durable. Runtime is deadline-enforced; token and artifact consumption are
checked from provider terminal evidence. Exact token usage is enforced when
the backend emits it. A local-unmetered backend that omits token usage records
`degraded_tokens_unavailable` visibly rather than fabricating a count. The
current daemon provider has no cost-in-micro-USD telemetry; local-unmetered
records zero billable cost while retaining the requested ceiling.

## MoonBook evidence bridge

Product outcome submission is explicitly triggered through the
`outcome-evidence` command; it is not inferred automatically from a chat result
and does not close work. The request must cite real supervisor journal event
IDs and contain the exact MoonBook `ProductOutcomeSubmission` projection.
MoonBook-owned `observed_at` and `recorded_at` remain JSON integers for schema
compatibility. When a successful worker supplies a valid projection whose
evidence references and digests match its verified artifacts, status exposes
the projection as `review_ready` with its provider-success source event ID.
Validation also requires globally unique, fully versioned evidence identities,
canonical lowercase SHA-256 digests, complete capability metadata, and unique
in-submission evidence for each gap. Present gaps require severity 1..5;
absent gaps require severity zero. Any mismatch omits the candidate and keeps
the status at `outcome_evidence_required`.
The parent can pass those exact values to the existing outcome-evidence
operation; MoonClaw never auto-submits or invents acceptance. Missing or
invalid candidate fields leave `outcome_evidence_required`.
`outbox-claim` returns those exact projections and `outbox-ack` records the
actual MoonBook receipts. MoonBook retains exclusive review, acceptance, and
closure authority.
