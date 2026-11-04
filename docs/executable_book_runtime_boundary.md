# Executable Book Runtime Boundary

MoonCode is MoonClaw's coding role. The normal direction is one primary agent
working from the user's goal through implementation, checks, repair, and
delivery. The runtime owns execution facts; the agent owns reasoning and
planning. This is a responsibility split, not a permanent Router/Worker team.

## Standalone Project Rule

MoonClaw must run as its own checkout. Building, testing, and starting it must
not require adjacent MoonDesk, MoonBook, or MoonTown checkouts. Clients use
published packages, configured paths, and runtime protocols.

## MoonClaw Standalone Agent Runtime

MoonClaw standalone agent runtime provides the shared runtime substrate:
model/tool loops, session journals, authorization, cancellation, process
lifecycle, and recovery. MoonDesk presents input, progress, results, and
necessary decisions. MoonBook and Bookkeeper own accepted book truth.

MoonCode should not be implemented as generic task chat. Coding sessions use
`/v1/code/*`; generic task/job APIs remain separate. Existing job, coordination,
and worker capabilities are optional execution facilities, not mandatory stages
of every coding task.

## Current Execution

The current native path is:

```text
turns -> durable command queue -> runtime service
      -> runtime turn -> model/tool results -> continuation or terminal receipt
      -> canonical conversation and artifact references
```

- `POST /v1/code/sessions/<id>/turns` appends a command and starts or reuses
  execution. Append and startup are recoverable, not one crash-atomic action.
- Runtime claim, loop, and service execution coordinate through a stable
  per-session execution lease. A competing owner receives HTTP 409.
- Positive `planner_max_steps` values are resumable scheduling quanta. Exhaustion
  persists the next position and completed results rather than proving failure
  or completion. The default value is zero.
- An optional criteria-only goal uses `mooncode-goal-runtime.v1`. Its current
  genesis is immutable and rejects aggregate budget fields. For an active
  goal, `max_turns` is a local service quantum.
- Current terminal goal decisions come from validated `finish.goal_runtime`
  or active-target cancellation. Plain `finish` does not settle an active goal.
  Criterion-reference coverage is structural validation, not a semantic proof
  that the deliverable satisfies the user's request.
- Current implementation tasks use horizon checkpoints and mutation/verification
  checks, with an explicit `no_change` path. These overlapping completion
  mechanisms are consolidation targets below.
- Completed tool results and the actual model transcript survive milestone
  checkpoints. Context projection is handled separately; a checkpoint does not
  itself justify discarding source observations.

The API details are in the [daemon reference](../cmd/daemon/README.md).
Current capabilities and source types, rather than old migration logs, define
the available routes and fields.

## Durable Facts And Recovery

The selected workspace resolves the MoonClaw product home through MoonLib:

```text
<moonclaw-product-home>/mooncode/sessions/<session-id>/
  journal.jsonl
  session.json
```

The journal is authoritative. The snapshot and in-memory bindings are
replaceable projections. Continuations retain the plan, resume position,
approval binding, and completed-result references.

Journal sequences are exact canonical decimal strings. Append checks the
committed prefix, identity conflicts, and exact successor under stable locks;
only a torn final suffix is repaired. Physical record sequences are positive;
derived empty/read cursors may be zero. File data is synchronized, with
directory synchronization on supported platforms. These are ordinary
process/crash guarantees, not strongest sudden-power-loss qualification.

Restore existing results before continuing. A missing result after an external
side effect does not prove that the operation failed: reconcile the actual
outcome before retry. Checkpoints alone cannot provide universal exactly-once
execution.

## Tools And Human Decisions

File and process tools stay within their declared scope and authorization.
Process execution requires the configured MoonFort route; missing configuration
does not select a host-shell fallback. Direct `/tool-exec` currently returns 503.
See [Execution sandbox](EXECUTION_SANDBOX.md).

Approval requests bind the exact operation and parameters. Recovery uses the
stored approved operation; rejection records non-execution and returns feedback
to the agent. Timeout remains pending. Cancellation targets the active command
and must reach its process before a cancellation result is claimed.

Ordinary errors should be repaired by the same agent when possible. Human
intervention is for real authority or decision gaps. Explicit book adoption or
product acceptance is separate from engineering completion and delivery;
ordinary tasks do not acquire a mandatory independent reviewer.

## Approved Simplification

Implement through the current runtime, without a new runtime package,
checker registry, Operation database, or `submit_candidate` tool:

1. Remove the legacy Goal implementation and dual-authority branches.
2. Retain one task definition and one completion decision through `finish`;
   return repairable gaps to the same agent.
3. Bind necessary verification to actual results and relevant source/artifact
   versions. Package labels and caller-supplied success fields are not proofs.
4. Reuse journal and continuation for execution intent, result persistence,
   and recovery; consolidate duplicate continuation structures.
5. Remove forced-mutation/discovery-count rules, permissive tool-call repair,
   duplicated prompt rules, and desktop-owned acceptance inference.

Default to a single primary agent, proportional checks, and autonomous repair.
Do not impose universal packaging, isolated snapshots, or human acceptance.
The new design has no old-protocol compatibility or dual-write requirement.
These changes are approved work, not implemented by this documentation update.

The complete discussion and final plan are retained in the optional sibling
[MoonDesk archive](../../moondesk/docs/mooncode-discussion-2026-11-04/README.md).
The runtime and the summary above remain usable without that checkout.

## Validation

Use focused native tests for the changed boundary, then the repository release
gate described in [Responsibility and testability](RESPONSIBILITY_AND_TESTABILITY.md).
Cover incomplete finish recovery, changed task instructions, stale verification,
approval rejection, cancellation, and crash reconciliation. Compare deliverable
quality, user intervention, rework, latency, and total cost.

[Harness regression](HARNESS_REGRESSION_GATES.md) describes existing test
fixtures; [replay](HARNESS_REPLAY.md) compares recorded observations. Fixture
success and dated test counts do not establish current live delivery quality.
