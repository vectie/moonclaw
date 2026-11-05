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

Output truncation respects UTF-8 boundaries. Large complete outputs use
validated MoonFort artifact references; IDs are not interpreted as host paths.
The precise limits and result retrieval behavior remain in the tool contracts.

## Measurements and checks

`planner_metrics` records compiled request/schema size, tool counts, reported
provider tokens/cache reads, model-call wall elapsed time and outer transport
retry count. It is attached to the existing final planner event, including an
empty response. Conversation usage sums these durable observations once;
compacted historical plans and repeated receipts cannot overwrite the total.
The existing daemon UUID source distinguishes responses sharing a timestamp.

The synchronous MoonGate exporter, environment switch, export-only SDK wrapper,
duplicate configured/effective size calculations, selected-tool-name list and
derived cache-ratio counters were removed. Collection performs no external IO,
adds no journal round, and does not decide task acceptance. Missing/invalid
provider usage remains unmeasured. The compiled request size is not the final
provider HTTP body, and the outer retry count excludes internal transport
fallbacks. There is no price estimate or claim that all billed attempts were
observed. Existing error/tool/result records and offline replay remain the
source for failure analysis; no always-on evaluator was added.

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
