# MoonClaw Improvement Plan

This document turns the current architecture direction into a concrete implementation plan.

It is intentionally focused on MoonClaw itself:

- strengthen the durable runtime
- improve end-to-end execution quality
- make document ingestion real
- reduce regressions in channel-driven workflows
- improve operator visibility

## Goals

MoonClaw should become stronger in five areas:

1. reliable end-to-end execution
2. real starter-file ingestion
3. predictable adaptive planning and resume behavior
4. better operator-facing visibility and control
5. stronger test coverage around real-world failure modes

## Guiding Principles

- Keep workflow mechanics in code.
- Keep reasoning and decomposition in AI prompts and skills.
- Keep the core job engine generic.
- Move product policy into `e2e_*` and `adaptive_*` layers.
- Prefer explicit artifacts and run-state visibility over hidden behavior.

## Milestone 1: Stabilize E2E Runtime

### Objective

Make the current `/e2e` path reliable before adding more capability.

### Work

- Finish separating classic `/plan-job` from `/e2e` behavior everywhere.
- Ensure `context_preprocess` is always:
  - job-level
  - first
  - one-time
  - non-blocking
  - non-adaptive
- Ensure `/resume` always:
  - resumes the same run in place
  - resumes the blocked step
  - does not replay stale progress snapshots

### Files likely involved

- `/Users/kq/Workspace/moonclaw/job/application.mbt`
- `/Users/kq/Workspace/moonclaw/job/workflow_engine.mbt`
- `/Users/kq/Workspace/moonclaw/job/executor.mbt`
- `/Users/kq/Workspace/moonclaw/gateway/server/job_chat.mbt`
- `/Users/kq/Workspace/moonclaw/job/e2e_preprocess.mbt`

### Exit criteria

- `/e2e` never collapses into a misleading single-step execution unless planner fallback is unavoidable
- preprocess never asks for user input
- `/resume` never creates a new run
- resumed runs do not replay old `WaitingForInput` snapshots

## Milestone 2: Real Attachment Ingestion

### Objective

Turn starter files into actual working inputs instead of mostly metadata.

### Work

- Add attachment fetch/download pipeline.
- Detect file type at ingestion time.
- Route supported documents through extraction:
  - readable text documents
  - PDFs
  - scanned PDFs through OCR
- Write extracted results into run-visible artifacts and workspace files.

### New internal boundary

Recommended internal flow:

1. attachment collected from channel/gateway
2. file downloaded into run workspace or managed temp area
3. document extractor produces normalized text/markdown
4. extracted content persisted as artifacts
5. preprocess and analysis steps consume those artifacts

### Files likely involved

- `/Users/kq/Workspace/moonclaw/gateway/server/job_chat.mbt`
- `/Users/kq/Workspace/moonclaw/job/e2e_intake.mbt`
- `/Users/kq/Workspace/moonclaw/job/e2e_preprocess.mbt`
- `/Users/kq/Workspace/moonclaw/job/artifact_store.mbt`
- new internal ingestion packages

### Exit criteria

- attached PDF content is available to E2E steps as real text or OCR-derived markdown
- proposal/status surfaces clearly show which files were included
- blocked runs no longer ask for raw file text when the file was already provided and is machine-processable

## Milestone 3: Extract Adaptive Execution Layer

### Objective

Move adaptive runtime policy out of the general analysis handler.

### Work

- Keep `job/analysis.mbt` as the orchestration entrypoint.
- Keep step request composition in:
  - `job/analysis_request_composer.mbt`
- Keep step execution in:
  - `job/analysis_runner.mbt`
  - `job/analysis_execution.mbt`
- Keep prompt and workspace-output support in:
  - `job/analysis_prompt_support.mbt`
  - `job/analysis_workspace_outputs.mbt`
- Keep adaptive modules focused on:
  - verdict judgment
  - missing-input extraction
  - subplan synthesis
  - resume-guidance interpretation

### Files likely involved

- `/Users/kq/Workspace/moonclaw/job/analysis.mbt`
- `/Users/kq/Workspace/moonclaw/job/analysis_request_composer.mbt`
- `/Users/kq/Workspace/moonclaw/job/analysis_runner.mbt`
- `/Users/kq/Workspace/moonclaw/job/analysis_execution.mbt`
- `/Users/kq/Workspace/moonclaw/job/analysis_prompt_support.mbt`
- `/Users/kq/Workspace/moonclaw/job/analysis_workspace_outputs.mbt`
- `/Users/kq/Workspace/moonclaw/job/adaptive_prompts.mbt`
- `/Users/kq/Workspace/moonclaw/job/adaptive_types.mbt`
- `/Users/kq/Workspace/moonclaw/job/adaptive_policy.mbt`
- `/Users/kq/Workspace/moonclaw/job/adaptive_subplan.mbt`

### Exit criteria

- adaptive behavior is modular and testable
- `job/analysis.mbt` no longer carries most product-policy branching or low-level prompt/persistence helpers
- missing-input and subplan behavior can evolve without destabilizing basic analysis execution

## Milestone 4: Strengthen Planner Contract

### Objective

Reduce planner drift and fallback behavior.

### Work

- Keep `job-planning/SKILL.md` as the primary contract.
- Make planner prompt shorter and schema-dominant.
- Add one strict repair pass for invalid output.
- Keep parser compatibility only as a bounded guardrail.
- Stop expanding alias tolerance indefinitely.

### Files likely involved

- `/Users/kq/Workspace/moonclaw/job/proposal.mbt`
- `/Users/kq/Workspace/moonclaw/job/e2e_planner.mbt`
- runtime skills:
  - `~/.moonclaw/skills/job-planning/SKILL.md`

### Exit criteria

- planner usually returns the intended schema directly
- under-decomposed fallback becomes much rarer
- parser compatibility remains modest and intentional

## Milestone 5: Better Missing-Input and Guessing Behavior

### Objective

Pause only when truly blocked, and continue with assumptions when operator guidance allows it.

### Work

- Improve missing-input extraction so waiting messages are explicit.
- Ensure operator guidance like `/resume guess missing data` is passed as authoritative instruction.
- Prefer best-effort completion when a useful screening result is already possible.
- Prevent useful first-pass outputs from being downgraded by weak adaptive follow-up.

### Files likely involved

- `/Users/kq/Workspace/moonclaw/job/adaptive_prompts.mbt`
- `/Users/kq/Workspace/moonclaw/job/adaptive_policy.mbt`
- `/Users/kq/Workspace/moonclaw/job/analysis.mbt`
- `/Users/kq/Workspace/moonclaw/job/chat_service.mbt`
- `/Users/kq/Workspace/moonclaw/job/query_service.mbt`

### Exit criteria

- waiting messages contain a dedicated missing-input block
- `/resume` with assumption guidance does not bounce back unnecessarily
- usable screening outputs remain completed

## Milestone 6: Presentation Post-Processing

### Objective

Make presentation output a reliable post-process path.

### Work

- Keep analytical result generation separate from presentation generation.
- Generate a structured page-by-page presentation spec.
- Persist:
  - `presentation_plan.json`
  - `presentation_outline.md`
- Add a clean vendor/render adapter boundary for later rendering.

### Files likely involved

- `/Users/kq/Workspace/moonclaw/job/e2e_postprocess.mbt`
- `/Users/kq/Workspace/moonclaw/job/presentation_types.mbt`

### Exit criteria

- presentation requests produce structured page-level handoff artifacts
- presentation remains an optional post-process stage, not a replacement for the analytical result

## Milestone 7: Operator UI Accuracy

### Objective

Make the UI reflect actual runtime lineage and state correctly.

### Work

- Ensure selected run always binds to the correct snapshot.
- Improve visibility of:
  - preprocess
  - postprocess
  - waiting state
  - child runs
  - subplans
- Keep canvas/tree correctness ahead of cosmetic changes.

### Files likely involved

- `/Users/kq/Workspace/moonclaw/job/ui_snapshot.mbt`
- `/Users/kq/Workspace/moonclaw/ui/rabbita-job/main/update.mbt`
- `/Users/kq/Workspace/moonclaw/ui/rabbita-job/main/canvas_surface.mbt`

### Exit criteria

- selected runs never show data from the latest unrelated run
- subplans and child runs are obvious in the operator view
- waiting state clearly identifies the blocked step

## Milestone 8: Realistic Regression Coverage

### Objective

Turn the most common live failures into automated tests.

### Priority scenarios

- separate file upload followed by `/e2e`
- classic `/plan-job` versus `/e2e`
- in-place `/resume`
- `/resume` with assumption guidance
- preprocess must not request input
- force-stop while running
- force-stop while waiting
- planner shape drift
- stale progress notification after resume
- waiting message duplication

### Files likely involved

- `/Users/kq/Workspace/moonclaw/gateway/server/job_chat_wbtest.mbt`
- `/Users/kq/Workspace/moonclaw/gateway/server/channel_message_handler_wbtest.mbt`
- `/Users/kq/Workspace/moonclaw/job/analysis_wbtest.mbt`
- `/Users/kq/Workspace/moonclaw/job/workflow_engine_wbtest.mbt`
- `/Users/kq/Workspace/moonclaw/job/executor_wbtest.mbt`
- `/Users/kq/Workspace/moonclaw/job/control_service_wbtest.mbt`
- new E2E-specific integration tests where needed

### Exit criteria

- most regressions found in live Feishu/E2E testing are reproducible in tests
- new policy changes land with scenario-level coverage

## Recommended Order

1. Stabilize E2E runtime behavior.
2. Implement real attachment ingestion.
3. Extract adaptive policy modules.
4. Tighten planner contract and repair logic.
5. Improve missing-input and assumption-guided continuation.
6. Strengthen presentation post-process path.
7. Improve UI accuracy and lineage visibility.
8. Expand regression coverage continuously across all milestones.

## Short-Term Success Criteria

MoonClaw is materially improved when all of the following are true:

- `/plan-job` and `/e2e` are clearly distinct and reliable
- starter files are truly consumed by the workflow
- scanned PDFs can become usable text inputs
- waiting runs resume in place and do not bounce unnecessarily
- planning drift is rarer and easier to repair
- operator UI shows the real run tree and status
- the common real-world regressions are covered by tests
