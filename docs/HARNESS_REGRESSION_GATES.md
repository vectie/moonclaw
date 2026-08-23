# MoonClaw harness regression gates

The harness regression suite protects task capability and verification behavior
while measuring prompt, schema, cache, retry, outcome, and latency fields. It is
an observation and test surface only: it does not enable dynamic bundles,
semantic compaction, metric export, or any other runtime feature.

## Cohorts

The deterministic native suite covers seven representative request shapes:

| Cohort | Required contract |
| --- | --- |
| Read-only inspection | `read`, `finish`, and `read_skill` remain available; completion does not require mutation evidence. |
| Generic edit | Core read/write/edit/patch/checkpoint capabilities and bounded deferred `tool_search` remain available; successful mutation plus verification is accepted. |
| MoonBit validation | `moon_ide`, `moon_cmd`, and `moon_check` remain available in catalog order. |
| UI/browser | `browser` and `view_image` remain available without losing core edit and verification tools. |
| Delegated workers | `spawn_workers` and `wait_workers` remain available with the normal coding capabilities. |
| Long-context follow-up | The canonical task and latest verifier evidence survive bounded transcript compaction deterministically. |
| Failure/retry | A failed attempt followed by mutation and typed verification produces the same accepted completion contract while recording retry and closed outcome fields. |

Each tool-bundle cohort evaluates the compatibility catalog and the dynamic
catalog from the same task contract. The suite asserts:

- every required capability is available in both catalogs;
- dynamic coding cohorts retain `tool_search` so omitted capabilities remain
  discoverable;
- repeated catalog selection has identical ordering;
- required tools retain their relative canonical order;
- the compatibility and dynamic paths produce the same completion-verdict
  result for identical tool evidence;
- prompt and schema byte counts are present and the dynamic schema never
  exceeds the compatibility schema;
- cache reads, fresh input, cache ratio, model retries, planner latency, and a
  closed outcome are present in the privacy-bounded metrics projection.

Latency values in this deterministic suite are fixtures. They prove that the
field is retained through the metrics contract; they are deliberately not a
machine-speed threshold. The existing parallel-read benchmark continues to
measure local elapsed time directionally and asserts source-order result and
metadata equivalence.

The production-safe baseline/variant evaluator, anonymized fixture contract,
per-cohort p50/p95 distributions, and offline CLI are documented in
[HARNESS_REPLAY.md](HARNESS_REPLAY.md).
Malformed transport, provenance and receipt mutation, compaction invariants,
Unicode output boundaries, and expanded distribution qualification are
documented in
[HARNESS_ADVERSARIAL_QUALIFICATION.md](HARNESS_ADVERSARIAL_QUALIFICATION.md).

## Run locally

Use an isolated target directory so validation does not reuse or overwrite the
ordinary repository build tree:

```sh
moon test --target native \
  --target-dir /tmp/moonclaw-harness-regression \
  cmd/daemon/mooncode_harness_benchmark_wbtest.mbt

moon test --target native \
  --target-dir /tmp/moonclaw-harness-parallel-read \
  cmd/daemon/mooncode_parallel_read_benchmark_wbtest.mbt

moon check --target native --warn-list +73 \
  --target-dir /tmp/moonclaw-harness-check \
  cmd/daemon

moon info --target native \
  --target-dir /tmp/moonclaw-harness-info \
  cmd/daemon

moon run --target native \
  --target-dir /tmp/moonclaw-harness-replay \
  cmd/harness_replay -- \
  testdata/harness_replay/anonymized_cases.json
```

The complete daemon matrix also contains native command, commit, eval, build,
test-proof, and task-scope cohorts. Nineteen legacy cases still create a fresh
temporary MoonBook and therefore need migration to an injected, per-fixture
MoonFort deployment; one process-wide operator config cannot safely authorize
their unrelated roots. Without that fixture they must fail closed. Do not skip
them or restore a host fallback to make the matrix green. A release candidate
is green only after the migrated cases pass through the real grant/executor
boundary in a configured MoonFort integration environment.

Run `moon fmt cmd/daemon/mooncode_harness_benchmark_wbtest.mbt` after changing
the suite. `moon info` should not alter the daemon interface for test-only
changes; any generated interface diff is an explicit review stop.

## Rollout decision order

Feature trials are compared against the compatibility path by cohort. A lower
token count or faster response never compensates for a quality regression.
Promotion gates are evaluated in this order:

1. **Task success:** the requested outcome is completed with all required
   capabilities available. Any statistically or operationally material task
   success regression blocks rollout.
2. **Verifier success:** required checks, tests, builds, UI assertions, and
   artifact validation succeed at least as often as the compatibility path.
3. **Safety and recovery:** approvals, mutation boundaries, deterministic tool
   order, failure recovery, and retained long-context requirements remain
   equivalent or improve.
4. **Cost and cache:** only after the first three gates pass, compare fresh
   input tokens, cache-read ratio, prompt bytes, schema bytes, output bytes,
   and tool-call count.
5. **Latency:** compare distributions by cohort and transport, including retry
   cohorts. Do not gate on a single machine-local duration or an absolute
   microbenchmark threshold.

Production trials should report cohort sample counts, task-success and verifier
rates, retry/outcome counts, and percentile latency alongside token/cache byte
metrics. Roll back a flag independently when its own cohort gate fails; do not
average a failure away with gains from unrelated cohorts.
