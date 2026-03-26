# E2E Job Architecture

This document describes the intended layering for MoonClaw's end-to-end job flow.

## Goal

Support a user workflow like:

1. provide a general topic
2. attach starter files
3. specify the desired output format

Then MoonClaw should:

- plan the work
- explore the local context and public data when needed
- execute the workflow end to end
- pause only when truly blocked
- generate the requested final output

## Recommended Layers

### 1. Core Job Engine

Keep generic:

- proposal persistence
- workflow compilation
- step execution
- child runs
- waiting/resume
- run/canvas rendering

Core files include:

- `/Users/kq/Workspace/moonclaw/job/application.mbt`
- `/Users/kq/Workspace/moonclaw/job/proposal.mbt`
- `/Users/kq/Workspace/moonclaw/job/compiler.mbt`
- `/Users/kq/Workspace/moonclaw/job/workflow_engine.mbt`
- `/Users/kq/Workspace/moonclaw/job/analysis.mbt`

The core engine should not know about the product concept of "topic + files + output format".

### 2. E2E Intake and Planning Layer

Own the product-specific front door.

Suggested files:

- `/Users/kq/Workspace/moonclaw/job/e2e_types.mbt`
- `/Users/kq/Workspace/moonclaw/job/e2e_intake.mbt`
- `/Users/kq/Workspace/moonclaw/job/e2e_planner.mbt`
- `/Users/kq/Workspace/moonclaw/job/e2e_policy.mbt`

Responsibilities:

- normalize user intake
- define planner guidance
- preserve the requested output contract
- set default execution expectations like:
  - use skills
  - use tools when needed
  - prefer fetching over guessing

### 3. Adaptive Execution Layer

Own the second-pass runtime judgment.

Suggested files:

- `/Users/kq/Workspace/moonclaw/job/adaptive_types.mbt`
- `/Users/kq/Workspace/moonclaw/job/adaptive_policy.mbt`
- `/Users/kq/Workspace/moonclaw/job/adaptive_judge.mbt`
- `/Users/kq/Workspace/moonclaw/job/adaptive_subplan.mbt`

Responsibilities:

- decide whether a step is:
  - `completed`
  - `needs_input`
  - `needs_subplan`
- create child proposals when expansion is worthwhile
- pause the workflow only when no useful work can proceed

This is where the current "second pass" belongs.

## Current Refactor Status

Started:

- `job/e2e_types.mbt`
- `job/e2e_intake.mbt`
- `job/e2e_planner.mbt`

These modules currently cover:

- structured intake types
- output format extraction
- normalized proposal intake JSON
- planner prompt/system guidance for starter files and output format

Still to extract:

- richer `e2e_policy.mbt` defaults
- adaptive runtime judgment into dedicated `adaptive_*` modules
- attachment content ingestion instead of metadata-only propagation

## Near-Term Plan

1. Keep the current behavior working while moving E2E logic into `job/e2e_*`.
2. Extract adaptive step judgment from `job/analysis.mbt` into `job/adaptive_*`.
3. Add attachment download/text extraction so starter files become real working inputs instead of URL metadata only.
4. Let output formats compile into stronger final-step contracts.
