# MoonClaw Documentation Guide

Start with the [product contract](PRODUCT_CONTRACT.md) for current maturity,
capability labels, boundaries and release gates.

For saved result inspection, keep [exact-revision reviewer notes](ARTIFACT_REVIEW_NOTES.md)
and [collect feedback from several reviewers](ARTIFACT_FEEDBACK_COLLECTION.md).
The collection reopens locally and exposes change requests, mixed checklist
states and pending inspections without making an acceptance decision.
Use [CSV review editing](ARTIFACT_REVIEW_CSV.md) to exchange selected worksheet
rows with local editors and preview exact-base note changes before import.

For task input from a spreadsheet export, [select CSV records and columns](SELECTED_TABLE_INPUTS.md)
in Work, inspect exact cells and original record positions, then preview and
apply only the chosen table to the ordinary task draft.

For nested exported observations, [select exact JSON or JSON Lines values](SELECTED_JSON_INPUTS.md)
by document and JSON Pointer. Inspect complete subtrees, preserve large numeric
IDs and original syntax, and preview only the chosen values in the task draft.

MoonClaw is the agent execution runtime for MoonSuite. It owns agent execution,
job/session state, tool use, runtime evidence, gateway APIs, and MoonCode
execution behavior. It should not become a desktop shell, durable knowledge
store, town scheduler, or shared filesystem contract library.

## Scope And Boundary

MoonClaw owns:

- chat, job, proposal, run, and native MoonCode session runtimes
- gateway and daemon APIs
- bounded tool execution and runtime events
- artifacts, workspaces, provider-backed tasks, and memory records
- MoonCode command queues, stream events, package proof, eval proof, and test
  proof
- durable MoonCode tool approvals and active task/process cancellation
- operator surfaces for inspecting runtime activity

MoonClaw does not own accepted book truth, scheduled cross-book routing, desktop
file browsing, suite metrics, or layout contracts. MoonBook accepts durable
outputs, MoonTown owns recurring coordination, MoonFlow owns cross-product workflow
execution, MoonDesk projects the UI, MoonGate owns authority/provider control,
and MoonLib defines shared paths.

## Reading Order

1. [Product contract](PRODUCT_CONTRACT.md): runtime scope and capability status.
2. [Responsibility and testability](RESPONSIBILITY_AND_TESTABILITY.md):
   product-owned policy, installed packs, and focused/release checks.
3. [Executable book runtime boundary](executable_book_runtime_boundary.md):
   current single-agent MoonCode execution, completion, and recovery.
4. [Daemon reference](../cmd/daemon/README.md) and
   [daemon/gateway selection](daemon_vs_gateway.md): service entry points.
5. [System architecture](system_architecture.md) and
   [job architecture](job_system_architecture.md): existing runtime call chains.
6. [Execution sandbox](EXECUTION_SANDBOX.md): existing Fort integration,
   authorization, receipts, and uncertain outcomes.
7. [Context provenance](MOONCODE_CONTEXT_PROVENANCE.md),
   [compaction](LONG_CONTEXT_COMPACTION.md), and
   [stream resume](MOONCODE_STREAM_RESUME.md): current context/transport contracts.
8. [Harness regression](HARNESS_REGRESSION_GATES.md) and
   [paired replay](HARNESS_REPLAY.md): fixtures, qualification, and measured comparison.
9. [Capability invocation](CAPABILITY_INVOCATION.md): pack resolution, health,
   execution receipts, and restart reconciliation.
10. [Events](events.md), [HTTP](http.md), and
    [expected behaviors](expected_behaviors/README.md): API and operator behavior.

## Implementation Direction

For MoonCode, reuse the current loop, journal, continuation, tool results, and
`finish`. Keep one primary agent, one task definition, and one completion
decision. Return repairable errors to that agent; request human input only for
real authority or decision gaps. Remove duplicate mechanisms before adding
abstractions. The [runtime boundary](executable_book_runtime_boundary.md)
describes the implemented path and the limits of its verification evidence.

Do not introduce a permanent agent Router, a checker registry, a second
operation database, or a new runtime framework. Optional generic job and worker
capabilities remain available without defining the default coding path.

Runtime files use MoonLib-resolved product homes. The journal owns ordered
facts; the desktop consumes canonical conversation projections rather than
merging raw events or claiming independent completion.

## Validation And Evidence

Use focused checks for changed packages and the release gate in
[Responsibility and testability](RESPONSIBILITY_AND_TESTABILITY.md). Verify
relevant first/multiple turns, completion repair, stale evidence, approval
rejection, cancellation, and restart recovery. Ordinary authorized work should
not acquire additional user-confirmation steps.

Fixture results, historical test counts, and dated experiments do not establish
current deployment or live task quality. Keep task success, user intervention,
rework, latency, and total cost visible. The dated
[long-horizon comparison](MOONCODE_LONG_HORIZON_PROMPT_COMPARISON_2026-07-28.md)
is historical evidence, not a current execution policy.

Old Goal/journal migration diaries and unimplemented distributed/controller
expansion proposals were retired. Current source and the focused contract
documents above replace their conflicting intermediate status reports.

## Retained revision comparison

See [Compare retained text artifacts](COMPARE_ARTIFACTS.md) for the local
`compare_artifacts` command and host API.

- [Portable retained-artifact export](EXPORT_ARTIFACTS.md): copy selected exact text/binary revisions with original records, lineage and standard checksums.

- [Search saved artifact revisions](SEARCH_ARTIFACTS.md): find exact outputs by metadata and literal text, inspect bounded line excerpts, then export the observed matches.

- [Import portable artifacts for inspection](IMPORT_ARTIFACTS.md): reopen received exports with exact original-record provenance and use saved-store search, comparison and re-export.

- [Compare saved job runs](COMPARE_RUNS.md): align steps and inspect changed observations.
