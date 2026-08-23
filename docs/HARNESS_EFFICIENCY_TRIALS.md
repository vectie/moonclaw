# MoonClaw harness efficiency trials

This document describes the production-safe rollout surface for prompt/cache
metrics, tool bundles, read batching, atomic edits, output retention, and
long-horizon compaction. Compatibility remains the default unless noted.

The executable cohort matrix and quality-first promotion order are documented
in [HARNESS_REGRESSION_GATES.md](HARNESS_REGRESSION_GATES.md).
Offline paired baseline/variant replay and its anonymized fixture contract are
documented in [HARNESS_REPLAY.md](HARNESS_REPLAY.md).

## Runtime controls

| Control | Default | Effect |
| --- | --- | --- |
| `payload.planner_dynamic_tool_bundles` | `false` | Selects a task-specific initial schema and exposes bounded `tool_search` discovery for omitted capabilities. The default still sends the complete coding catalog and does not expose `tool_search`. |
| `payload.planner_tool_output_chars` | absent | Supplies a default inline output cap for tools that did not specify one. Absence preserves 12,000 characters. Values are bounded to 200,000; explicit tool arguments win. |
| parallel model-planned `read` calls | enabled for safe batches | Runs independent paths concurrently and commits results/events in model-call order. Resumed, approval-gated, mixed, duplicate, post-commit-sealed, or discovery-budget-crossing batches stay sequential. |
| `edit.arguments.edits` | optional | Applies ordered replacements in memory and performs one write only after every replacement validates. Legacy `old_string`/`new_string` remains supported. |
| `payload.planner_hybrid_semantic_compaction_trial` | `false` | Emits shadow evaluation data only; no additional model call and no transcript replacement. Eligibility also requires measured context pressure. |
| `payload.planner_hybrid_semantic_compaction_active` | `false` | Applies the deterministic long-context projection only after the very-long-task and measured-pressure gates pass. The durable journal is unchanged and invariant failures return the exact input projection. |
| `payload.planner_semantic_compaction_message_threshold` | `96` | Very-long-task lower bound shared by shadow and active modes, bounded to 64–512 messages. |
| `payload.planner_context_window_tokens` | absent | Required for eligibility; MoonClaw estimates serialized context pressure against this model window. Unknown windows remain ineligible. |
| `payload.planner_semantic_compaction_pressure_threshold_ppm` | `750000` | Pressure threshold shared by shadow and active modes (75%), bounded to 600000–900000. |
| `payload.planner_semantic_compaction_target_pressure_ppm` | `500000` | Active projection target (50%), bounded to 300000–700000 and at least 100000 ppm below the trigger. |
| `MOONCLAW_PLANNER_METRICS_EXPORT` | unset/disabled | When set to `1`, `true`, `yes`, or `on`, sends a privacy-bounded planner observation to the MoonGate instance advertised by validated suite status. Discovery, timeout, rejection, and transport failures are ignored. |
| MoonFort receipt `output_artifact` | absent for small complete output | Validates a signed opaque reference bound to the run, digest, size, media type, expiry, key, signature, and approved output ceiling when complete output must spill. IDs are never interpreted as host paths. |

The 12,000-character default is now the named
`MOONCODE_DEFAULT_TOOL_OUTPUT_CHARS` compatibility policy rather than a
scattered literal. The separate opt-in maximum allows larger operator-selected
output without silently expanding every model turn. The wire field retains its
historical `*_chars` name, but truncation now selects the largest valid UTF-8
prefix or head/tail projection within the bounded encoded length. A limit that
lands inside a multibyte scalar steps back to the preceding boundary instead
of aborting or emitting malformed text.

## Deferred tool discovery

Dynamic coding bundles include `tool_search` in the initial request. Search is
limited to a registry derived from the authoritative typed MoonCode tool
definitions. Tools in the always-exposed coding bundle are removed; every
other current or future authoritative definition is deferred automatically.
First occurrence wins for duplicate names, and authoritative definition order
is the stable tie-breaker. Search terms come from each definition's name,
description, and parameter schema rather than a second hand-maintained name
list. Queries are non-empty, contain no control characters, and are at most 256
characters; `max_results` defaults to three and is bounded to one through five.
An unknown query returns no matches instead of broadening the schema.

A successful search does not execute a matched capability. Its bounded receipt
is fed back as an ordinary tool result, and matching schemas are added only to
the next planner request. Already exposed tools are excluded from results.
Before loading, MoonClaw rechecks the execution status, catalog contract,
query, bound, command-specific exposure set, match count, and exact
deterministic match set against the current authoritative registry. Rejected,
failed, malformed, forged, duplicate, or out-of-registry receipts load nothing.
Explicit `planner_allowed_tools` remains authoritative and disables deferred
expansion even when dynamic bundles are enabled.

## Planner metrics

Each successful model-planner round includes
`moonclaw.planner.metrics.v1` under `planner_metrics`:

- configured/effective request characters and message counts;
- system-prompt and selected-tool-schema characters;
- selected tool names, tool count, and returned tool-call count;
- provider prompt, completion, total, and cache-read tokens;
- fresh input tokens and cache-read ratio in parts per million;
- end-to-end planner latency at the runtime integration boundary, optional
  model retry count, and a closed selected/no-tool outcome;
- whether provider-overload shaping reduced the request.

These fields are observation only. They do not alter routing, cache policy,
prompt content, or tool execution. Export is disabled by default and has a
named 300 ms observation timeout when enabled. Only aggregate numeric,
boolean, contract, and closed outcome fields cross the boundary; session IDs,
prompts, paths, tool names, and tool arguments remain local. The MoonGate
aggregation mapping and cardinality policy live in
`../moongate/docs/MOONCLAW_HARNESS_METRICS.md`.

## Local native benchmark, 2026-08-23

The reproducible benchmark tests use the same tool-catalog selector and
parallel-read executor as production.

Dynamic bundle schema size:

| Case | Baseline tools/chars | Dynamic tools/chars | Reduction |
| --- | ---: | ---: | ---: |
| Read-only summary | 3 / 1,202 | 3 / 1,202 | 0.0% |
| Generic edit | 15 / 9,860 | 9 / 5,053 | 48.75% |
| MoonBit change | 15 / 9,860 | 12 / 7,641 | 22.50% |
| UI/browser change | 15 / 9,860 | 11 / 6,841 | 30.61% |
| Delegated workers | 15 / 9,860 | 11 / 6,029 | 38.85% |

The dynamic coding cohorts include the bounded `tool_search` schema. This
reduces the apparent byte saving compared with the earlier heuristic-only
bundle, while keeping deferred capabilities discoverable instead of silently
unavailable.

Authoritative deferred-registry lookup benchmark (isolated native run):

- 15 authoritative definitions produce seven deferred entries after the eight
  always-exposed coding tools are removed;
- the generic initial dynamic bundle remains nine schemas and 5,053 serialized
  characters versus 15 schemas and 9,860 characters for compatibility mode
  (48.75% reduction);
- 4,000 deterministic registry lookups complete in 144 ms, or 36 µs per
  lookup on this machine.

The timing is a machine-local regression signal, not a production SLO. The
benchmark also checks stable authoritative ordering, duplicate-name handling,
schema expansion, bounded results, and a nonzero lookup checksum.

Parallel read batch:

- workload: eight cached 524,288-character files, eight iterations;
- current isolated native run: 313 ms sequential versus 175 ms parallel
  (44.1% lower elapsed time); earlier repeated runs measured 51.6% lower
  median elapsed time;
- every bounded output and metadata record was asserted equal and results were
  retained in source order.

Machine-local timings are directional, not a production SLO. Production
rollout should compare success and verification first, then fresh input tokens,
cache ratio, request bytes, latency, and tool-call count by the representative
cohorts listed in the MoonGate metrics document.

## Validation state

- deferred discovery and bundle tests pass 13/13; the combined deferred,
  bundle, benchmark, and regression selection passes 16/16;
- process-tool and shell-analysis suites pass 37/37 without weakening the
  missing-deployment refusal;
- artifact adversarial tests pass 4/4, wire compatibility passes 2/2, and the
  execute-command integration suite passes 8/8;
- MoonGate's native suite passes 894/894 and MoonFort's native suite passes
  137/137;
- the complete MoonClaw daemon run completes 645 tests: 626 pass and 19 legacy
  temporary-MoonBook cases remain red because they still need per-fixture
  MoonFort config injection for native command, commit, eval/build/test proof,
  and task-scope coverage. None of the new harness, scheduler, metrics,
  deferred-discovery, semantic-shadow, or artifact-contract tests fail. That
  fixture migration plus a configured MoonFort run remains a release gate and
  is not converted into a skip or host fallback.

Do not enable the semantic trial as an active summarizer from this evidence.
First collect shadow cohorts on genuinely long tasks and compare retained
requirements, exact-path evidence, verification success, and recovery after a
failed edit.

The active lifecycle is a separate default-off rollout control. Its integration
contract, invariant checks, deterministic metrics, and adversarial validation
are documented in [LONG_CONTEXT_COMPACTION.md](LONG_CONTEXT_COMPACTION.md).
