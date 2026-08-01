# Native supervisor runtime provider

This provider exposes the `supervisor.*` operations declared by the MoonClaw
pack through the daemon HTTP surface at `/v1/supervisors`.

Exact operations:

- `supervisor.activate`
- `supervisor.message.send`
- `supervisor.wake`
- `supervisor.steer`
- `supervisor.stop`
- `supervisor.retry-resume`
- `supervisor.delegate`
- `supervisor.worker.steer`
- `supervisor.worker.stop`
- `supervisor.worker.retry-resume`
- `supervisor.outcome-evidence.propose`
- `supervisor.mailbox.claim`
- `supervisor.mailbox.ack`
- `supervisor.outcome-outbox.claim`
- `supervisor.outcome-outbox.ack`

Child operation-to-route bindings are exact:

- `supervisor.worker.steer` → `POST /v1/supervisors/{id}/commands/worker-steer`
- `supervisor.worker.stop` → `POST /v1/supervisors/{id}/commands/worker-stop`
- `supervisor.worker.retry-resume` → `POST /v1/supervisors/{id}/commands/worker-retry-resume`

Every mutation requires a fresh MoonLib authority decision bound to the exact
canonical payload digest and an executable exact-operation resolution from
MoonGate. Accepted commands are journaled under the MoonClaw jobs root.

Supervisor activation and recovery require the exact model declared by the
immutable runtime binding. A missing model or a running executor registered
under a different model fails closed; no default-model fallback is allowed.
Parent provider replies are journaled only from real assistant lifecycle
events as `supervisor.assistant.responded`, with the response at
`payload.assistant_response` for status/replay consumers.

The delegate operation accepts a human-authored intent plus explicit claim,
budget, artifact, lifetime, workspace, and network bounds. Accounting mode is
not accepted from that DTO: MoonClaw resolves it from the host-only
`MOONCLAW_SUPERVISOR_WORKER_ACCOUNTING_MODE` configuration. An absent or
unknown value fails closed; this provider currently supports explicit
`local-unmetered`, while `metered-external` remains unavailable until exact
cost-meter evidence exists. MoonClaw creates or
restores one child JobRun beneath the canonical supervisor run's existing
job.delegate step, issues a receiver-bound child delegation, and uses the
daemon's existing MoonClaw task provider. The child remains pending until that
provider accepts the message and reaches a terminal state only from provider
lifecycle events.

Worker steer, stop, and retry-resume require the exact persisted child run ID.
They never target or replace the canonical supervisor task. Duplicate and
daemon-restart recovery retain the same child and provider task UUID.

Outcome evidence is not automatic completion. A successful worker result may
carry an exact, artifact-bound ProductOutcomeSubmission candidate. Such a
worker reports `review_ready` and exposes both the candidate and its durable
source event ID; otherwise it reports `outcome_evidence_required`. A caller
explicitly invokes `supervisor.outcome-evidence.propose` with those values. The
outbox then carries the exact MoonBook `ProductOutcomeSubmission` projection;
MoonBook alone reviews or accepts it.

The candidate validator uses MoonBook's exact intake invariants: canonical
lowercase SHA-256 identities, globally unique complete evidence references,
complete capability metadata, and unique in-submission evidence for every
Three-Gap statement. A present gap has severity 1..5; an absent gap has exactly
zero severity. Any mismatch omits the candidate and leaves the worker at
`outcome_evidence_required`; it never becomes `review_ready` by approximation.
