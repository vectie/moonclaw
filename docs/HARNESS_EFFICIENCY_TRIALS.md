# MoonCode harness efficiency

Quality deliverables and reliable autonomous execution come first. Compare
actual task success, verifier results and rework before optimizing prompt
size, latency or tool-call counts. See the [runtime boundary](executable_book_runtime_boundary.md).

## Tool selection

Native tools come from one authoritative catalog. Coding requests receive
the normal coding tools without worker tools; read-only requests keep a
smaller inspection surface. Explicit `payload.planner_allowed_tools` selects
from that same catalog, including optional workers when authorized.

The default-off `planner_dynamic_tool_bundles` experiment, keyword catalog,
native `tool_search`, deferred receipt validation and schema expansion were
removed. Their schema-reduction benchmarks are not current runtime evidence.
The existing MCP inventory/call path remains for external tools.

## Existing controls

| Control | Default | Purpose |
| --- | --- | --- |
| `payload.planner_tool_output_chars` | absent | Inline tool output defaults to 12,000 encoded bytes; explicit tool arguments win. |
| Safe model-planned read batches | enabled | Execute independent observations concurrently and commit results in model order. Mixed effects, approval boundaries and resumed batches remain sequential. |
| `edit.arguments.edits` | optional | Validate ordered replacements in memory before one file write. |
| Context projection | enabled | Use the configured model window and reserve output space; preserve durable results. `planner_context_window_tokens` may narrow the window. |
| `MOONCLAW_PLANNER_METRICS_EXPORT` | unset | Export bounded aggregate observations to MoonGate without changing execution. |

Output truncation respects UTF-8 boundaries. Large complete outputs use
validated MoonFort artifact references; IDs are not interpreted as host paths.
The precise limits and result retrieval behavior remain in the tool contracts.

## Measurements and checks

`planner_metrics` records request/schema characters, tool counts, provider
tokens and cache reads, planner latency, retry count and outcome. Export
contains aggregate fields rather than prompts, paths, sessions or arguments.
The observer remains optional and cannot determine task acceptance.

The native catalog regression checks required capabilities across task
languages, stable ordering, explicit tool selection and read-only behavior.
The parallel-read benchmark measures local execution while asserting output
equivalence and order. Compaction tests preserve task requirements, provider
tool-call pairing and recent verification. Machine-local timings are not
production latency or live-model quality qualification.

Use [harness regression](HARNESS_REGRESSION_GATES.md),
[paired replay](HARNESS_REPLAY.md), [adversarial qualification](HARNESS_ADVERSARIAL_QUALIFICATION.md)
and [long-context compaction](LONG_CONTEXT_COMPACTION.md) for the current
behavioral checks. Do not promote a flag or a release from prompt-size
savings or historical fixture counts alone.
