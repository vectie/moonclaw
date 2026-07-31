# Native agent-goal adapter port

`moonclaw-agent-goal-v1` implements
`moonclaw/agent.goal.execute@0.1.5` by adapting to the one existing MoonClaw
daemon runtime. It does not own a queue, scheduler, agent loop, goal reducer or
acceptance decision.

Submission uses the existing durable paths in this order:

1. `POST /v1/code/sessions/{session}/commands` appends one deterministic,
   idempotency-derived command to the session journal.
2. `PUT /v1/code/sessions/{session}/goal-runtime` installs or verifies the
   strict criteria-only goal genesis.
3. `POST /v1/code/sessions/{session}/runtime-service` starts or reuses the
   existing leased goal supervisor.

Reconciliation reads
`GET /v1/code/sessions/{session}/goal-runtime`. Cancellation submits the
existing exact-target `cancel` control through
`POST /v1/code/sessions/{session}/turns`. All three operations therefore share
the existing MoonClaw journal, lifecycle gate, execution lease, runtime claim,
checkpoint and restart-recovery paths.

The generic request's `role` and `profile` select behavior inside that runtime.
Values such as `mooncode` and `wiki` are roles, not products and not separate
agent runtimes. The public default model is `gpt-5.6-sol`; the local daemon
adapter may resolve that name to its provider-qualified catalog selector
without changing the recorded profile.

The operation's claim ceiling is `digital-artifact`: terminal receipts retain
workspace-relative artifact references and observed SHA-256 digests from the
goal evidence, while the generic invocation receipt also binds the adapter
receipt and session journal through `output_artifacts` and `output_digest`.
This does not promote runtime success to human acceptance.

The host must probe `/v1/health` and `/v1/code/capabilities`, retain the exact
probe bytes, hash them with SHA-256, and issue a short-lived
`moonflow.adapter-health.v1` for the canonical operation. A static declaration
is never health evidence.
