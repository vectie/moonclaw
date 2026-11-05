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

## Output And Recovery

Small output remains bounded inline. Large output may carry a signed opaque
`output_artifact` reference. Retrieval remains subject to the configured Fort
reader's authorization, binding, size, expiry, and digest validation.

Live output uses the configured reader. Generic progress exposes bounded
availability/status information rather than copying raw output, signatures,
private paths, or credentials into unrelated event streams.

A timeout, cancelled wait, or missing terminal receipt does not establish that
an external effect did not occur. Preserve the operation identity and reconcile
against existing receipts/state before retry. Do not substitute a host execution
or report an unknown operation as successfully completed.

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
