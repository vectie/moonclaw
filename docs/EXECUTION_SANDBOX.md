# Execution Sandbox Integration

MoonClaw executes governed process tools through its existing MoonFort adapter.
The runtime validates scope and authority; MoonFort supplies the configured
execution environment and receipts. Missing or invalid configuration refuses
execution rather than falling back to an unrestricted host shell.

## Existing Implementation

| Boundary | Owner |
| --- | --- |
| Typed grants, execution receipts, and result validation | `internal/execution_sandbox/sandbox_protocol.mbt` |
| Fixed executor/publisher/reader processes | `internal/execution_sandbox_adapter` |
| Operator execution configuration | `internal/moonfort_config` |
| MoonCode tool and approval binding | `cmd/daemon/mooncode_execution_sandbox_gate.mbt` and `mooncode_runtime_approvals.mbt` |
| Reviewed artifact promotion and outcome inspection | Existing promotion adapters and [recovery owner](PROMOTION_RECOVERY_OWNER.md) |

The execution protocol is v3. Promotion uses its separate v4 protocol. Read
the corresponding typed adapter for exact fields; do not use the initial
prototype's v2 examples or introduce a second executor abstraction.

## Execution Flow

1. Resolve trusted operator configuration and prepare the exact execution plan.
2. Execute within operator-configured capabilities. Only an explicit approval
   annotation waits for a human; persist that exact bound plan before waiting.
   Command names or model `planner`/approval claims cannot grant authority.
3. Revalidate the approved plan, configuration, expiry, and requested action.
4. Invoke the fixed grant publisher and executor with bounded typed input.
5. Validate the returned run, approval, command, enforcement, and output binding.
6. Persist the execution result and return a bounded model/UI projection.

Executor paths, trusted registries, workspace identities, and credential
references come from operator configuration. Model/tool arguments cannot
replace them. Configuration changes or different command arguments do not
inherit an unrelated approval.

MoonCode's direct `/tool-exec` route is currently disabled. The runtime
process-tool path requires a configured sandbox route. Existing safe local
operations need not ask for human approval merely because they execute a tool;
the actual authority policy decides.

Absolute SDK/environment paths in a shell command are resolved by that same
executor profile; MoonCode does not reject them by HOME/Users/temp substring.
The macOS [Native configuration](../../moonfort/docs/EXECUTOR_CONFIG.md#macos-moonbit-native-commands)
uses existing Shell assignments, not a new environment API. Those assignments
do not carry over into a later moon_cmd invocation.
On macOS, a registered executable resolving to `SDK/bin/moon` supplies its
companion `MOON_HOME=SDK` while HOME remains private scratch. This fixes the
IDE registry lookup; Native compiler/SDK selection still uses the explicit
Shell configuration above. Workspace snapshots preserve source execute bits
without copying group/other read or write permissions.

Publisher refusal preserves its existing error code/message, including the
requested timeout and deployment ceiling. A refused plan has not executed;
report the reason so the agent can correct its arguments. Do not replace it
with a generic grant failure or silently raise/clamp the configured limit.

## Output And Recovery

Use the operator's release-built Fort publisher/executor/readers for live runs.
Debug snapshot hashing can dominate a short command's transport deadline;
changing build profile does not change grants, limits or enforcement mode.

Each shell call uses a fresh snapshot of current MoonBook files. Another call
does not continue that snapshot or clean its build outputs. Fort owns scratch
cleanup and optional retention; terminal results identify the per-call scope.
Native file editing tools own persistent MoonBook source changes. Seeing `.tmp`
in a command's own Git output does not mean it was created in the canonical Book.

Small output remains bounded inline. Large output may carry a signed opaque
`output_artifact` reference. Retrieval remains subject to the configured Fort
reader's authorization, binding, size, expiry, and digest validation.
The existing `max_output_chars` projection also applies to non-Exited receipts
before returning their error. Failure excerpts preserve the diagnostic tail;
the complete artifact and receipt references remain available.

MoonCode's model projection omits full sandbox change inventories and requested
policy, internal grant digests/IDs and verification-input inventories, retaining
the change count, output/error, execution status, enforcement,
cleanup and retained evidence/artifact references. Native file edits also omit
the redundant whole-file diff from this projection. The original result stays
in the journal for UI inspection and existing read_result recall. Follow-ups
keep one compact read/error index with distinct failure summaries, without
repeating general repair guidance. Invocation counts remain in the journal.
Pipeline ambiguity stays in the tool metadata and evidence checks; there is no
separate planner user warning that can outlive the call. Follow-ups do not
duplicate shell excerpts or
emit another task/recent-results progress message. Saved cross-command notes
are included in the existing task prompt, with new checkpoints in tool history.
User/project-required skills and needed workflows load through read_skill;
matching a catalog description alone does not mandate loading a general guide.
Selected skill instructions remain complete.

An exit-zero inspection pipeline remains a successful observation. Its existing
ambiguity marker still prevents it from proving a required check; tool success
and verification evidence are separate facts.

Live output uses the configured reader. Generic progress exposes bounded
availability/status information rather than copying raw output, signatures,
private paths, or credentials into unrelated event streams.

A timeout, cancelled wait, or missing terminal receipt does not establish that
an external effect did not occur. Preserve the operation identity and reconcile
against existing receipts/state before retry. Do not substitute a host execution
or report an unknown operation as successfully completed.

Recover the recorded operation before binding a new random execution grant.
Otherwise a new grant changes the call digest before the old intent/result can
be matched. Existing outcome-unknown and execution rules remain authoritative.

## Promotion

Reviewed artifact promotion is a separate operation. Its closed outcomes
distinguish `applied-durable`, `not-applied`, and `recovery-required`.
Cleanup failure after an applied mutation is not permission to repeat it.
Unknown destination state requires the existing owner/recovery path.

[Promotion recovery owner](PROMOTION_RECOVERY_OWNER.md) documents the current
read-only inspection contract and its limitations. Do not turn inspection into
an implicit retry, approval, or book-acceptance decision.

## Verification

Use the existing protocol, adapter, approval, and promotion tests for the
changed seam. Live executor/backend qualification requires its real configured
environment; deterministic fixtures alone do not establish deployment,
backend isolation, or strongest power-loss guarantees.

This integration reuses the current adapter. It does not require an additional
sandbox planner, microservice, agent role, or general execution framework.
