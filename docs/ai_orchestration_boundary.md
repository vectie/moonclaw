# AI Orchestration Boundary

This document defines the intended boundary between deterministic runtime code and AI-driven reasoning in MoonClaw.

## Goal

MoonClaw should hardcode workflow mechanics, not domain thinking.

The runtime should be stable and predictable about:
- when a job starts
- how a workflow advances
- how a run pauses
- how a run resumes
- how child runs are created
- how outputs are stored

The model should decide:
- how to plan a job
- how to decompose a step
- whether a result is complete
- whether a step needs more input
- whether a step should expand into a subplan
- what assumptions are reasonable
- what missing data actually matters

## Rule Of Thumb

If the logic is about orchestration, state, persistence, routing, or safety, it belongs in code.

If the logic is about interpreting user intent, judging incomplete work, decomposing a task, or making a best-effort estimate, it should be delegated to AI through prompts and skills.

## Layer Model

MoonClaw should be understood as three layers.

### 1. Core Runtime Layer

Main files:
- [/Users/kq/Workspace/moonclaw/job/application.mbt](/Users/kq/Workspace/moonclaw/job/application.mbt)
- [/Users/kq/Workspace/moonclaw/job/compiler.mbt](/Users/kq/Workspace/moonclaw/job/compiler.mbt)
- [/Users/kq/Workspace/moonclaw/job/workflow_engine.mbt](/Users/kq/Workspace/moonclaw/job/workflow_engine.mbt)
- [/Users/kq/Workspace/moonclaw/job/runtime.mbt](/Users/kq/Workspace/moonclaw/job/runtime.mbt)
- [/Users/kq/Workspace/moonclaw/job/executor.mbt](/Users/kq/Workspace/moonclaw/job/executor.mbt)

Responsibilities:
- proposal execution
- workflow progression
- job/run state transitions
- cancellation and force-stop
- waiting/resume mechanics
- artifact and workspace output persistence

This layer should remain generic.

### 2. E2E Planning Layer

Main files:
- [/Users/kq/Workspace/moonclaw/job/e2e_intake.mbt](/Users/kq/Workspace/moonclaw/job/e2e_intake.mbt)
- [/Users/kq/Workspace/moonclaw/job/e2e_planner.mbt](/Users/kq/Workspace/moonclaw/job/e2e_planner.mbt)
- [/Users/kq/Workspace/moonclaw/job/e2e_preprocess.mbt](/Users/kq/Workspace/moonclaw/job/e2e_preprocess.mbt)
- [/Users/kq/Workspace/moonclaw/job/e2e_postprocess.mbt](/Users/kq/Workspace/moonclaw/job/e2e_postprocess.mbt)
- [/Users/kq/Workspace/moonclaw/job/proposal.mbt](/Users/kq/Workspace/moonclaw/job/proposal.mbt)

Responsibilities:
- normalize user intake
- preserve starter files and output format
- ask AI to generate the initial workflow
- insert job-level preprocess and postprocess stages

This layer should encode product policy, not domain-specific reasoning.

### 3. Adaptive Execution Layer

Main files:
- [/Users/kq/Workspace/moonclaw/job/analysis.mbt](/Users/kq/Workspace/moonclaw/job/analysis.mbt)
- [/Users/kq/Workspace/moonclaw/job/analysis_request_composer.mbt](/Users/kq/Workspace/moonclaw/job/analysis_request_composer.mbt)
- [/Users/kq/Workspace/moonclaw/job/analysis_runner.mbt](/Users/kq/Workspace/moonclaw/job/analysis_runner.mbt)
- [/Users/kq/Workspace/moonclaw/job/analysis_execution.mbt](/Users/kq/Workspace/moonclaw/job/analysis_execution.mbt)
- [/Users/kq/Workspace/moonclaw/job/analysis_prompt_support.mbt](/Users/kq/Workspace/moonclaw/job/analysis_prompt_support.mbt)
- [/Users/kq/Workspace/moonclaw/job/adaptive_prompts.mbt](/Users/kq/Workspace/moonclaw/job/adaptive_prompts.mbt)
- [/Users/kq/Workspace/moonclaw/job/adaptive_policy.mbt](/Users/kq/Workspace/moonclaw/job/adaptive_policy.mbt)
- [/Users/kq/Workspace/moonclaw/job/adaptive_types.mbt](/Users/kq/Workspace/moonclaw/job/adaptive_types.mbt)

Responsibilities:
- evaluate step output
- decide `completed`, `needs_input`, or `needs_subplan`
- synthesize child subplans
- extract explicit missing inputs
- interpret `/resume` guidance

This layer should rely on AI judgment, not keyword-triggered behavior.

Within this layer:
- `job/analysis.mbt` should stay as the orchestration entrypoint
- `job/analysis_request_composer.mbt` should build request payloads
- `job/analysis_runner.mbt` should run the step agent
- `job/analysis_execution.mbt` should persist execution results
- `job/adaptive_*` modules should own adaptive reasoning policy

## What Must Be Hardcoded

The following belongs in code:
- workflow state machine
- run statuses such as `Pending`, `Running`, `WaitingForInput`, `Succeeded`, `Failed`, `Cancelled`
- step ordering
- preprocess runs first
- postprocess runs last
- in-place resume uses the same run id
- child runs inherit the correct lineage
- force-stop actually cancels the active task
- outputs are written into the run workspace

These are runtime invariants, not model decisions.

## What Must Not Be Hardcoded

The following should not be embedded as domain logic in code:
- exact fields needed for a land estimate
- exact substeps for a business memo
- exact assumptions for a feasibility study
- literal user phrases like `guess missing data` mapped to fixed actions
- domain-specific lists of missing inputs

These should come from the model through:
- planner prompts
- adaptive prompts
- skills
- proposal step metadata

## Resume Guidance

`/resume` is operator guidance, not a special-case command language.

The runtime should pass the resume content into the blocked step as authoritative user instruction.

The AI should decide what that means in context:
- continue with labeled assumptions
- perform a best-effort estimate
- treat it as permission to proceed without more user input
- still stop if core facts cannot be responsibly inferred

The code should not implement a table of phrase-specific behaviors.

## Missing Input Policy

When a step is blocked, the model should try to produce a concrete `missing_inputs` list.

The runtime should:
- pause the run
- surface the missing inputs clearly
- allow in-place `/resume`

The runtime should not invent the missing input list itself unless it is performing generic formatting.

## Subplan Policy

When a step needs decomposition:
- AI should decide whether a subplan is worthwhile
- AI should generate the child substeps

The runtime should:
- create the child workflow
- track lineage
- execute and merge outputs

The user should not be required to manually author substeps unless explicitly requested.

## Preprocess Policy

`context_preprocess` is a job-level preflight stage.

It should:
- run once at the beginning
- gather related context from workspace and public sources
- make labeled assumptions where needed

It should not:
- ask the user for extra data
- request a subplan
- repeatedly pause the run

## Skills Policy

Skills should define contracts and behavior expectations for the model.

Examples:
- `.moonsuite/products/moonclaw/skills/job-planning/SKILL.md`
- `.moonsuite/products/moonclaw/skills/analysis-adaptation/SKILL.md`

Skills are the right place to define:
- expected JSON schemas
- decomposition quality
- how to judge `needs_input` vs `needs_subplan`
- how to prefer best-effort estimation over unnecessary user interruption

Code should remain tolerant, but skills should carry the primary contract.

## Design Principle

Prefer:
- stable runtime primitives in code
- flexible reasoning in AI

Avoid:
- burying product behavior in ad hoc code branches
- making the user compensate for missing AI decomposition
- adding domain-specific heuristics into the core runtime

## Practical Checklist

When adding a feature, ask:

1. Is this a workflow/state/persistence rule?
If yes, put it in code.

2. Is this a reasoning/decomposition/judgment rule?
If yes, put it in AI prompts or skills.

3. Is this a reusable product policy?
If yes, put it in the E2E or adaptive layer, not in the generic runtime core.

4. Is this a domain-specific assumption?
If yes, do not hardcode it into the runtime.
