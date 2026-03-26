# End-to-End Test: Land Acquisition Estimation

This guide shows how to test the current E2E flow with a realistic analytical request:

`Land acquisition estimation`

It is written as an operator procedure, not an implementation note.

## Goal

Verify that MoonClaw can:

1. accept a broad topic
2. optionally accept starter files
3. preserve the requested output format
4. generate a draft workflow
5. run a preprocessing step to gather public context
6. execute the main analytical workflow
7. pause if truly blocked on missing inputs
8. optionally produce a presentation post-process output

## Preconditions

Before testing, make sure:

- the gateway is running
- Feishu channel chat is working
- your configured primary model is healthy
- `/e2e` is working in Feishu
- the workspace root is your normal jobs workspace, for example:
  - `/Users/kq/Workspace/moonclaw-workspace`

If you want to inspect the run visually, open:

- jobs UI: [http://localhost:18123/ui#/jobs](http://localhost:18123/ui#/jobs)
- a specific run: `http://localhost:18123/ui#/runs/<run-id>`
- canvas view: `http://localhost:18123/ui#/runs/<run-id>/canvas`

## Recommended Test Variants

Use these in order.

### Variant 1: Pure broad question

Use this when you want to test preprocessing and missing-data handling.

```text
/e2e Land acquisition estimation
Output format: Board memo
```

Expected behavior:

- the proposal should include a first preprocessing step
- the remaining steps should be analytical phases, not just one `execute` step
- after confirmation, the run should gather public/background context first
- if parcel-specific facts are truly missing, the run may move to `WaitingForInput`

### Variant 2: Broad question plus starter file

Use this when you want to test file-aware planning.

Attach a starter file such as:

- a parcel brief
- seller memo
- zoning note
- market note
- comp sheet

Then send:

```text
/e2e Land acquisition estimation
Output format: Board memo
```

Expected behavior:

- the planner should preserve the file-aware context
- preprocessing should treat the attachment as part of the initial working set
- if the attachment is a scanned image PDF and OCR is unavailable, MoonClaw may still continue with a clearly labeled assumptions-based estimate later in the run
- later steps should use the file plus public context together

### Variant 3: Broad question plus presentation output

Use this when you want to test the presentation post-process.

```text
/e2e Land acquisition estimation
Output format: Board presentation deck
```

Expected behavior:

- the proposal should include:
  - preprocessing
  - analytical steps
  - `presentation_postprocess`
- if a renderer target is configured, it may also include:
  - `presentation_render`

## Feishu Test Procedure

### 1. Create the draft proposal

In Feishu, send:

```text
/e2e Land acquisition estimation
Output format: Board memo
```

Optional:

- attach a land brief or parcel note before sending

### 2. Inspect the proposal

The draft should not be only:

- `execute. Execute requested work`

You should expect a structure more like:

1. preprocess context
2. information collection or scope clarification
3. method or scheme design
4. cost or value estimation
5. financial analysis
6. risk assessment
7. report generation

Exact titles may vary because planning is AI-generated.

### 3. Confirm the proposal

Use the returned proposal id:

```text
/confirm <proposal-id>
```

### 4. Watch the run

Track it from:

- Feishu status messages
- `/job-status <run-or-job-ref>`
- the jobs UI
- the run canvas

### 5. Inspect workspace outputs

The run workspace should contain visible outputs.

For a normal analytical run, expect:

- `report.md`
- `result.json`
- `outputs/`

For the preprocessing step, expect:

- `preprocess_context.md`
- `preprocess_context.json`

If presentation output was requested, also expect:

- `presentation_outline.md`
- `presentation_plan.json`

If a renderer step is configured, also expect something like:

- `presentation_render_report.md`
- `presentation_render_result.json`

## What Good Behavior Looks Like

For `Land acquisition estimation`, good behavior means:

- MoonClaw does not assume the user provided parcel-specific facts
- MoonClaw first builds a context pack from:
  - starter files
  - public context
  - reasonable explicit assumptions
- MoonClaw does not collapse everything into one vague step
- if it lacks essential parcel-specific inputs, it either:
  - continues useful preparatory work
  - or pauses with `WaitingForInput`

## What WaitingForInput Should Look Like

If the run is truly blocked on missing parcel facts, you should see a paused state rather than a fake final answer.

Typical missing inputs for this topic:

- parcel location
- parcel size
- intended use
- zoning / FLU
- seller ask or broker guidance
- comparable sales set
- utility and access constraints

When the run pauses, resume it in Feishu with a slash command reply:

```text
/resume Parcel is in Hangzhou, 28 mu, intended for mixed-use residential, seller asking CNY 42M.
```

You can also attach files in that reply.

If you want MoonClaw to continue with explicit assumptions instead of pausing again, use guidance like:

```text
/resume guess missing data
```

Expected resume behavior:

- the same run id is resumed in place
- already-completed earlier steps are not rerun
- Feishu should show new step progress after the `/resume` acknowledgement
- a stale `WaitingForInput` snapshot should not be re-sent before the next real step event
- if a later step can produce a usable screening result with explicit assumptions, MoonClaw should prefer that result over bouncing back into `WaitingForInput`

Plain non-slash chat should remain normal conversation, not job control.

## What To Check In The Run Workspace

After a successful run, inspect:

- the final report for decision-ready structure
- the preprocessing outputs for source-grounded context gathering
- the step outputs under `outputs/`

Primary output locations:

- `<run-workspace>/report.md`
- `<run-workspace>/result.json`
- `<run-workspace>/outputs/`

For this scenario, the final memo should usually include:

- scope and assumptions
- estimation method
- price / cost range
- financial implications
- key risks
- next recommended diligence actions

If the result is a presentation request, the presentation plan should include:

- page-by-page structure
- headline per page
- visual type per page
- layout instructions
- vendor handoff notes

## Failure Modes To Watch

### Bad planning

Symptoms:

- only one generic `execute` step

Interpretation:

- planner degraded or fell back

### No preprocessing

Symptoms:

- first step is not `context_preprocess`

Interpretation:

- E2E preprocess layer is not being applied

### Fake completion instead of pause

Symptoms:

- final answer gives only generic screening language but the run never paused for key missing facts

Interpretation:

- adaptive execution or missing-input judgment is too permissive

### No visible outputs in workspace

Symptoms:

- artifacts exist only in hidden store paths, not in the run workspace

Interpretation:

- workspace materialization regressed

## Suggested Acceptance Checklist

Use this checklist for the end-to-end test.

- `/e2e` produces a real multi-step proposal
- the first step is preprocessing
- `/confirm` launches the run successfully
- preprocessing outputs are written to the run workspace
- analytical outputs are written to the run workspace
- the run either completes meaningfully or pauses with `WaitingForInput`
- `/resume` can continue a blocked run
- presentation outputs are produced when deck output is requested

## Example Full Test Message

Use this exact message as a practical E2E test:

```text
/e2e Land acquisition estimation

We need a first-pass decision memo for whether this land opportunity is worth pursuing.

Output format: Board memo
```

And for the presentation variant:

```text
/e2e Land acquisition estimation

We need a first-pass decision memo for whether this land opportunity is worth pursuing.

Output format: Board presentation deck
```
