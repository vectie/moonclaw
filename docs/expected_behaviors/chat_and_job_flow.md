# Chat And Job Flow

This document describes the expected behavior of the current chat-driven job system.

## Normal Chat

Expected behavior:

- A normal Feishu message is handled as conversation input.
- If the message is a recognized job command, it is routed into the job chat path instead.
- If the message is a stop command for the active conversation, the conversation is cancelled cooperatively.
- Normal channel chat should use the configured primary model from `~/.moonclaw/moonclaw.json`.
- Stale thread/session-local bare model ids like `qwen3.5-plus` should not override the configured primary model.

For Feishu, the important command groups are:

- proposal commands
- job status/control commands
- memory commands

Job control rule:

- job-related control should require slash commands
- `WaitingForInput` resume should only happen on a reply beginning with `/resume`
- ordinary non-slash chat should remain normal conversation input

## Proposal Drafting

Expected behavior for `/plan-job <description>`:

1. MoonClaw creates a draft proposal.
2. MoonClaw replies with:
   - title
   - summary
   - planned steps
   - inferred family/template/capabilities when available
3. No job is executed yet.

Expected behavior for `/e2e <description>`:

1. MoonClaw creates an E2E draft proposal.
2. The draft may include:
   - `context_preprocess`
   - normal planned analysis steps
   - optional postprocess steps such as `presentation_postprocess`
3. No job is executed yet.

Safety rule:

- planning is allowed before confirmation
- execution is not

## Proposal Revision

Expected behavior for `/revise <proposal_id> <guidance>` or reply-thread `revise ...`:

- the proposal stays in `Draft`
- revision guidance accumulates
- the next draft should build on the latest revision chain, not restart from the original text

## Proposal Confirmation

Expected behavior for `/confirm <proposal_id>` or reply-thread `confirm`:

1. The proposal must still be in `Draft`.
2. MoonClaw compiles it into:
   - `JobDefinition`
   - `WorkflowDefinition`
   - optional chat bindings
3. A run is created.
4. The run is launched by the gateway background runtime.
5. The proposal is marked confirmed.

## Job Execution

Expected behavior after confirmation:

- the job moves from `Pending` to `Running`
- status reports should show:
  - job id
  - run id
  - job title
  - created time
  - current step
  - progress
  - elapsed time
- if the workflow has 3 steps, status should report `0/3`, `1/3`, `2/3`, `3/3` rather than `0/0`
- new ids should be readable and time-prefixed rather than opaque UUIDs when possible

## Notifications

Expected behavior when notifications are enabled:

- send a start message when the run begins
- send progress messages while running
- in `normal`, send `step.started` and `step.failed`
- in `verbose`, also send more detailed step-level progress like `step.succeeded`
- send a warning when a run is long-running
- do not interrupt automatically on long-running warning
- send a finish message on success/failure/cancel

Verbosity:

- `off`
- `normal`
- `verbose`

## Long-Running Jobs

Expected behavior:

- MoonClaw should tell the operator that the job is still running
- MoonClaw should include current status
- MoonClaw should not interrupt the job by itself
- the operator decides whether to stop or force-stop

## Stop And Force-Stop

Expected behavior:

- `/job-stop <job_id|run_id>` requests cooperative stop
- `/job-force-stop <job_id|run_id>` requests force-stop through the runtime control path
- force-stop is higher impact and may require approval depending on security policy

## Delegated And Subjob Workflows

Expected behavior:

- a parent workflow may spawn child runs
- child runs inherit lineage metadata
- status should make parent/child relationships understandable
- child work should not silently lose traceability

## Failure Behavior

Expected behavior:

- if a run fails before the first step completes, status may remain `0/N`
- the run should still move to `Failed`, not remain stuck in `Running`
- the operator should be able to inspect status and workspace state to understand the failure
