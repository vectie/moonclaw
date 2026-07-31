# MoonClaw operator UI-to-UI qualification

Last reviewed: 2026-07-31

The visible application is the Rabbita operator UI served by the MoonClaw
gateway at `/ui`. The qualification uses MoonClaw as the sole agent runtime;
it does not substitute a fixture screen for a running gateway.

## MC-01 — request to inspected outcome

1. Open `/ui` and confirm the first viewport names one next action.
2. Choose **Work**, create a thread, and enter an ordinary outcome request.
3. Start plan mode, inspect the preview, then promote the reviewed plan.
4. Confirm the proposal only when its authority and limits are correct.
5. Open the linked run and follow Ask → Plan → Review → Run → Inspect.
6. Open the final result and at least one evidence artifact.

Expected result: the selected thread and run remain correlated; the result is
durable after refresh; the UI never describes runtime completion as human
acceptance.

## MC-N1 — denied pack capability

Submit a work item whose receiving adapter is absent, stale, unhealthy or has
the wrong schema/authority identity.

Expected result: the run stops with the exact missing fact. No domain effect is
invented. The UI points the operator to install/refresh the receiving pack or
correct the declared capability before retry.

## MC-R1 — refresh and restart recovery

Refresh during a running job, then restart the gateway over the same durable
home and reopen the run.

Expected result: the same run, current step, retained evidence and reconciled
status return. An uncertain external effect reconciles before it is retried.

## MC-X1 — exact cross-product receipt

Execute one installed-pack operation through the generic capability seam.
Inspect the exact product/tool version, schemas, input digest, authority,
idempotency key, adapter health and returned receipt. Continue only when the
receiver reconciles the same attempt.

Authoritative references:

- [Operator UI behavior](../expected_behaviors/operator_ui.md)
- [Capability invocation](../CAPABILITY_INVOCATION.md)
- [Responsibility and testability](../RESPONSIBILITY_AND_TESTABILITY.md)
- [Rabbita UI launch](../../ui/rabbita-job/README.md)

## Qualification record

```text
date:
operator:
MoonClaw commit:
gateway home:
browser URL:
MC-01: PASS | FAIL | BLOCKED
MC-N1: PASS | FAIL | BLOCKED
MC-R1: PASS | FAIL | BLOCKED
MC-X1: PASS | FAIL | BLOCKED
thread id:
run id:
receiver receipt:
screenshots:
console or failed-request observations:
notes:
```
