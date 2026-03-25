# Current Job Routine

This document describes the job routine that MoonClaw actually runs today.

It is intended as a current-state reference for operators and developers. Some
older architecture documents still describe earlier template-heavy or
research-specific behavior; this file reflects the current code path in
`job/` and `gateway/server/`.

## 1. Entry Points

Jobs normally begin from chat commands such as:

- `/plan-job <request>`
- `/revise <proposal_id> <guidance>`
- `/confirm <proposal_id>`
- `/job-status <job_id|run_id>`
- `/jobs`
- `/job-stop <job_id|run_id>`
- `/job-force-stop <job_id|run_id>`

The gateway parses the inbound message, routes recognized job commands into the
job subsystem, and sends the rendered reply back through the channel adapter.

The important boundary is:

- `gateway/server` handles transport, background launching, and channel delivery
- `job` handles planning, compilation, execution, storage, and notification policy

## 2. Planning Routine

Planning starts in `GatewayJobApp::plan_proposal(...)` in
[/Users/kq/Workspace/moonclaw/job/application.mbt](/Users/kq/Workspace/moonclaw/job/application.mbt).

Current planning routine:

1. Build planning context from:
   - request text
   - workspace prompt context
   - relevant structured memory hits
2. Generate a draft proposal id using a human-readable, time-prefixed format.
3. Call `plan_job_proposal(...)` in
   [/Users/kq/Workspace/moonclaw/job/proposal.mbt](/Users/kq/Workspace/moonclaw/job/proposal.mbt).
4. Ask the planner model for strict JSON when available.
5. Normalize the result into a `JobProposal`.
6. If no usable model result exists, fall back to one minimal generic step:
   - `execute`

The default fallback is intentionally minimal. AI planning or workspace profiles
are expected to provide richer step structure when needed.

## 3. Workspace Job Profiles

MoonClaw can reshape the draft proposal using workspace-local job profiles.

Current source of truth:

- `<cwd>/moonclaw.jobs.json`

Current behavior in
[/Users/kq/Workspace/moonclaw/job/profile.mbt](/Users/kq/Workspace/moonclaw/job/profile.mbt):

- profiles are loaded only from `moonclaw.jobs.json`
- global `~/.moonclaw/moonclaw.json` is not used for job-profile behavior
- matching is keyword-based with:
  - `match.any`
  - `match.all`
  - `priority`

If a profile matches:

- proposal `family` becomes the profile family
- proposal `profile_id`, `profile_role`, and `profile_metadata` are filled
- proposal steps are replaced by the profile’s configured steps

This is currently the main declarative customization mechanism for job behavior.

## 4. Compilation Routine

Compilation happens in
[/Users/kq/Workspace/moonclaw/job/compiler.mbt](/Users/kq/Workspace/moonclaw/job/compiler.mbt).

The compiler is now mechanical rather than template-driven.

Current compiler behavior:

1. Choose the family from `proposal.suggested_family`, else `generic`.
2. Turn each proposal step into a `WorkflowStepDefinition`.
3. Default blank step kinds to `job.analysis`.
4. Build a `JobDefinition` and `WorkflowDefinition`.
5. Persist notify metadata, title, workspace root, profile metadata, and role.
6. If `profile_role == "controller"`, compile the definition/workflow kind as:
   - `job.controller`
   otherwise:
   - `job.proposal`

Important current rule:

- the compiler does not silently collapse or expand confirmed steps
- confirmed proposal structure is the execution structure

## 5. Confirmation Routine

Confirmation happens through `GatewayJobApp::confirm_proposal(...)` and the
gateway runtime launch path.

Current confirmation routine:

1. Ensure the proposal is still `Draft`.
2. Compile the proposal.
3. Register the durable `JobDefinition`.
4. Register the durable `WorkflowDefinition`.
5. Save chat bindings if any exist.
6. Trigger a new run with a human-readable run id.
7. Mark the proposal `Confirmed`.
8. Launch the run in the gateway’s long-lived root task group.

This means the proposal is only a draft until explicit confirmation.

## 6. Run Workspace Routine

Current run workspace behavior is implemented in
[/Users/kq/Workspace/moonclaw/job/run_workspace.mbt](/Users/kq/Workspace/moonclaw/job/run_workspace.mbt).

Top-level runs:

- workspace path: `<workspace>/moonclaw-jobs/<run-id>`

Child runs:

- workspace path: `<parent_run_workspace>/moonclaw-subjobs/<run-id>`

Inside each run workspace:

- a dedicated git repository is initialized
- run metadata is written to `.moonclaw/run.json`
- run checkpoints are stored as git commits

Important current rule:

- the run workspace is run-owned
- MoonClaw does not automatically copy workspace markdown into it
- no automatic copies of:
  - `AGENTS.md`
  - `USER.md`
  - `MEMORY.md`
  - `IDENTITY.md`
  - `ROUTINES.md`

The only memory bridge that remains is:

- if a run explicitly creates `MEMORY.md`, its manual content can be synced back
  into structured memory on checkpoint

## 7. Execution Routine

Execution happens in
[/Users/kq/Workspace/moonclaw/job/workflow_engine.mbt](/Users/kq/Workspace/moonclaw/job/workflow_engine.mbt)
through `WorkflowEngine::execute_run(...)`.

Current execution routine:

1. Load the run.
2. Load the job definition.
3. Load the workflow definition.
4. Mark the run `Running`.
5. Append `job.started`.
6. Execute workflow steps in order.
7. For each step:
   - check cancel / force-stop state
   - resolve the registered handler for the step kind
   - persist a running `JobStepRun`
   - append `step.started`
   - execute the handler
   - persist step output / metrics / logs
   - checkpoint the run workspace git repo
   - append `step.succeeded` or `step.failed`
8. On final success:
   - mark the run `Succeeded`
   - append `job.completed`
9. On unrecoverable failure:
   - mark the run `Failed`
   - append `job.failed`
10. On blocked input:
   - mark the step `WaitingForInput`
   - mark the run `WaitingForInput`
   - stop downstream execution until more input arrives

Current execution is step-handler driven. The engine does not contain a
research-specific routine anymore.

## 8. Current Step Kinds

The main step kinds currently used by the generic job path are:

- `job.analysis`
- `job.delegate`

`job.analysis` is implemented in
[/Users/kq/Workspace/moonclaw/job/analysis.mbt](/Users/kq/Workspace/moonclaw/job/analysis.mbt).

Current analysis routine:

1. Decode `AnalysisStepConfig`.
2. Resolve the effective working directory.
3. Build the prompt from:
   - step prompt
   - preferred skills
   - loaded skill contents
   - memory context
   - job/run metadata
4. Construct an agent.
5. Register analysis tools, currently including:
   - `execute_command`
   - `list_files`
   - `read_file`
   - `todo`
   - `search_files`
   - `apply_patch` or `write_to_file`
6. If the step config carries:
   - `execution_mode`
   - `execution_target`
   the gateway can route the analysis step through ACP instead of the local
   direct model path
7. If the step result is not clearly final, MoonClaw can run an adaptive
   follow-up judgment:
   - `completed`
   - `needs_input`
   - `needs_subplan`
8. `needs_input` pauses the run with `WaitingForInput`
9. `needs_subplan` can expand into a child workflow/subplan

## 9. Waiting For Input And Resume

When a run reaches `WaitingForInput`:

1. The status text and Feishu notification say the run is waiting.
2. The status message tells the operator to reply in the same Feishu thread
   with the missing text, files, or both.
3. A plain reply to that waiting message is treated as resume input.
4. MoonClaw starts a resumed continuation run for the same job definition.
5. The new reply content and attachment metadata are passed as `initial_input`
   into the new run.

Important current rule:

- this is a resumed continuation run, not an in-place mutation of the original
  waiting run
- ordinary non-reply chat should still fall through to the normal conversation
  path
7. Run the agent and collect result text.
8. Persist report/result artifacts.
9. Return a structured `WorkflowStepResult`.

`job.delegate` is implemented in
[/Users/kq/Workspace/moonclaw/job/subjob.mbt](/Users/kq/Workspace/moonclaw/job/subjob.mbt).

Current delegate routine:

1. Decode `SubjobStepConfig`.
2. Build a child request, optionally including parent outputs.
3. Optionally apply a named child profile.
4. Optionally carry execution routing intent:
   - `execution_mode`
   - `execution_target`
5. Plan a child proposal.
6. Compile the child proposal.
7. Register the child definition and workflow.
8. Trigger a child run with lineage metadata.
9. Execute that child run through a fresh workflow engine, or through ACP when
   the current runtime supports the requested routing.
10. Return child outputs to the parent step.

## 9. Controller Routine

Controller behavior is generic and JSON-driven rather than research-specific.

Current controller trigger:

- if a matched profile sets `role: "controller"`, compilation emits:
  - `job.controller`

Current controller bookkeeping lives in
[/Users/kq/Workspace/moonclaw/job/controller.mbt](/Users/kq/Workspace/moonclaw/job/controller.mbt).

Current controller routine:

1. On controller run creation, create:
   - controller state
   - root iteration
2. When a step starts:
   - ensure a step iteration exists
   - create root-to-step lineage if missing
3. If a delegate step spawns a child run:
   - attach child job id and child run id to the step iteration
4. If a step succeeds and emits a decision-like payload:
   - record a `JobControllerDecision`
   - optionally create a next iteration
   - optionally create lineage to that next iteration
5. When a step completes:
   - update the step iteration status
6. When the run completes:
   - update controller state and root iteration status

Important current boundary:

- code handles persistence and validation
- controller policy is meant to come from JSON metadata
- decision payload shape is deliberately soft, not one strict schema

## 10. Notification Routine

Notification policy lives in
[/Users/kq/Workspace/moonclaw/job/chat_service.mbt](/Users/kq/Workspace/moonclaw/job/chat_service.mbt).

Current notification behavior:

- preferences are persisted per chat scope
- `normal` sends:
  - run start
  - `step.started`
  - `step.failed`
  - completion
- `verbose` additionally sends more detailed step progress such as
  `step.succeeded`

Gateway delivery is handled by
[/Users/kq/Workspace/moonclaw/gateway/server/job_chat.mbt](/Users/kq/Workspace/moonclaw/gateway/server/job_chat.mbt)
and
[/Users/kq/Workspace/moonclaw/gateway/server/job_runtime.mbt](/Users/kq/Workspace/moonclaw/gateway/server/job_runtime.mbt).

## 11. Persistence Routine

Durable state lives under the job system store in `~/.moonclaw/jobs/...`.

Current durable records include:

- job proposals
- job definitions
- workflow definitions
- runs
- step runs
- chat bindings
- notification preferences
- run events
- artifacts
- controller state
- controller iterations
- controller lineage edges
- controller decisions

The run workspace and the durable store are separate on purpose:

- visible execution workspace under `<workspace>/moonclaw-jobs/...`
- durable runtime state under `~/.moonclaw/jobs/...`

## 12. Controller UI Routine

The current Rabbita jobs surface can render controller runs as a company-style
board in addition to the normal execution tree.

Current board behavior:

- `Split` and `Merge` nodes are synthesized for controller runs
- controller steps can be grouped into horizontal lanes
- company health, lane sequencing, and handoff cards are shown above the normal tree
- lane grouping prefers explicit step metadata:
  - `board_lane`
  - `board_order`
- if those are absent, the UI falls back to heuristics such as OPC skills or worker roles

## 13. Operator-Facing Routine

From the operator’s point of view, the current job routine is:

1. Ask for a draft with `/plan-job`.
2. Review the compact proposed steps.
3. Confirm with `/confirm`.
4. Watch readable job/run ids and local-time timestamps in `/job-status`.
5. Inspect the visible run workspace under `<workspace>/moonclaw-jobs/<run-id>`.
6. Use `/jobs`, `/job-status`, `/job-stop`, or `/job-force-stop` as needed.
7. Read final artifacts from the run workspace and the durable artifact store.

## 14. What The Routine Is Not

The current routine is no longer:

- a hardcoded research workflow
- a template-driven step-count override system
- a hidden `.moonclaw/job-workspaces/...` layout
- a run workspace that mirrors all workspace markdown

The current routine is:

- generic proposal planning
- optional JSON-driven profile shaping
- mechanical compilation
- step-handler execution
- visible run workspaces
- durable state and controller bookkeeping
