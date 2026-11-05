# MoonCode harness regression

The runtime follows one primary agent through execution, verification,
repair and delivery. Its tests protect that path without adding another
acceptance engine or model role. See the [runtime boundary](executable_book_runtime_boundary.md).

## Behavioral coverage

| Area | Contract |
| --- | --- |
| Native tools | Default tasks retain the same tools regardless of language or inferred purpose. Only explicit selection or read-only mode narrows the catalog. |
| Shared program | Model selection does not select a different working method. Initial context, skill catalog, steering, tool protocol and recovery use the existing shared path. |
| Explicit selection | `planner_allowed_tools` selects from the same catalog; workers remain optional and absent by default. |
| Read-only work | Inspection and findings need no manufactured edit. |
| Completion | Explicit required checks and current tracked inputs support `finish`; prompt keywords and successful-tool quotas add no requirements. |
| Repair | The model's next batch is preserved after edit failure. Safe observations and transient-check retries are not converted into synthetic errors. |
| Context | Task instructions, tool-call pairing and recent verification survive compaction. |
| Recovery | Checkpoints retain position, intent and completed-result references. Reuse results and reconcile uncertain effects. |
| Empty model follow-up | Preserve the claim and resume from existing results without requiring milestones; cancellation remains effective. |
| Authority | Actual sandbox grants, approval bindings and cancellation remain enforced. |

The retired bundle/search experiment and its simulated baseline/variant
catalog benchmark are removed. Performance observations are not task-success
proof. Runtime metrics and the generic [offline replay evaluator](HARNESS_REPLAY.md)
remain available for measured comparisons with real evidence.

## Run locally

```sh
moon test cmd/daemon/mooncode_model_tools_wbtest.mbt --target native --strip -j 2
moon test cmd/daemon/mooncode_runtime_completion_wbtest.mbt --target native --strip -j 2
moon test cmd/daemon/mooncode_runtime_replan_compaction_wbtest.mbt --target native --strip -j 2
moon test cmd/daemon/mooncode_parallel_read_benchmark_wbtest.mbt --target native --strip -j 2
moon test --target native --strip -j 2
```

The native suite includes command, commit, eval, build, test, task-scope and
restart fixtures. Temporary MoonBooks use their own MoonFort configuration;
they do not inherit a host-shell fallback. Passing these tests establishes
fixture behavior. Production deployment and live-model delivery quality need
their own observations, including success, intervention, rework, cost and
latency. Do not trade a quality regression for fewer tokens or faster replies.

Run `moon info` and `moon fmt`, inspect interface changes, and complete the
release checks described in [Responsibility and testability](RESPONSIBILITY_AND_TESTABILITY.md).
