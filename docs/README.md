# MoonClaw Documentation Guide

MoonClaw is the bounded agent runtime for MoonSuite. It owns agent execution,
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
- operator surfaces for inspecting runtime activity

MoonClaw does not own accepted book truth, scheduled cross-book routing, desktop
file browsing, suite metrics, or layout contracts. MoonBook accepts durable
outputs, MoonTown schedules work, MoonDesk projects the UI, MoonGate observes
health/usage, and MoonLib defines shared paths.

## Reading Order

1. [../README.mbt.md](../README.mbt.md): product overview and current news.
2. [executable_book_runtime_boundary.md](executable_book_runtime_boundary.md):
   MoonCode and executable-book runtime boundary.
3. [events.md](events.md): runtime event model.
4. [http.md](http.md): HTTP surface.
5. [daemon_vs_gateway.md](daemon_vs_gateway.md): service boundary.
6. [job_system_architecture.md](job_system_architecture.md): job runtime
   internals.
7. [e2e_architecture.md](e2e_architecture.md): end-to-end test direction.
8. [expected_behaviors/README.md](expected_behaviors/README.md): expected
   operator and job behavior.
9. [evidence_quality.md](evidence_quality.md): dossier policy, local retrieval
   artifacts, and fail-closed workspace containment.

## Implementation Guidance

Keep native MoonCode behavior separate from generic task/job behavior.
MoonCode commands should append to durable session queues, emit normalized
runtime events, and close with explicit proof. Generic task events are not a
substitute for a book-scoped coding transcript.

Use product-home paths derived from the selected book or suite root. Runtime
artifacts belong under `.moonsuite/products/moonclaw`; disposable traces belong
under `.tmp/products/moonclaw`.

## Testing Guidance

```sh
moon check
moon test
moon info
moon fmt
```

For MoonCode changes, test first-turn and multi-turn sessions, command queue
claiming, stream order, tool events, patch proof, test proof, package proof,
reload/cold-session reads, steering, cancel, accept, and reject. For gateway
changes, include auth, redaction, startup, and failure-path tests.

## Worth Noticing

- A UI saying "working" is not enough; progress should come from a runtime
  event or explicit daemon state.
- Native MoonCode sessions must not silently spawn duplicate generic tasks.
- Event order matters because MoonDesk renders directly from the transcript
  stream.
- Provider-backed execution should preserve partial artifacts and failure
  evidence instead of dropping runs.

## Future Plan

- Harden persistent MoonCode agent service behavior across long sessions.
- Expand model-backed coding eval coverage.
- Tighten stream attribution so every UI turn can link user command, thinking,
  tools, tests, package, and final assistant output.
- Keep operator surfaces focused on actionable runtime state rather than raw
  debug noise.
