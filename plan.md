# Job System Plan

This plan tracks the work to turn MoonClaw into a general job platform.

`research` should be the first built-in job family, not the root abstraction.
The platform should support durable scheduled/manual jobs, artifact management on disk, workflow execution, and chat over job outputs.

Mark a task complete only after implementation, validation, docs, and required tests for that slice are done.

## Product Goals

- make MoonClaw a durable job runtime under `gateway`
- support both manual and scheduled jobs
- persist job definitions, runs, checkpoints, and artifacts on disk
- support chat and AI analysis over job artifacts
- make `research` the first well-formed job family built on the generic platform

## Architecture Decisions

- the long-lived runtime remains `gateway`, not `daemon`
- job definitions, runs, artifacts, and checkpoints are disk-first
- workflows should be generic and reusable across job families
- chat should operate over job artifact scopes, not only over papers
- `research` should be implemented as job definitions and workflows on top of the platform

## Core Concepts

- `JobDefinition`
  durable job config, schedule, trigger policy, enabled state
- `JobRun`
  one execution of a job, with trigger source and status
- `JobStepRun`
  one workflow step execution within a run
- `ArtifactRecord`
  persistent output from a run, with type, path, metadata, and scope
- `WorkflowDefinition`
  reusable multi-step execution template
- `ChatBinding`
  binds chat queries to one or more artifact scopes

## Disk Layout

- `~/.moonclaw/jobs/definitions.json`
- `~/.moonclaw/jobs/runs/<run_id>/meta.json`
- `~/.moonclaw/jobs/runs/<run_id>/steps/<step_id>.json`
- `~/.moonclaw/jobs/runs/<run_id>/artifacts/<artifact_id>.json`
- `~/.moonclaw/jobs/artifacts/<artifact_key>/...`
- `~/.moonclaw/jobs/index/jobs.json`
- `~/.moonclaw/jobs/index/runs.json`
- `~/.moonclaw/jobs/index/artifacts.json`
- `~/.moonclaw/jobs/checkpoints/<job_id>.json`
- `~/.moonclaw/jobs/chat_bindings.json`

## Phase 1: Generic Job Data Model

- [x] Add `JobDefinition` types: id, kind, config, enabled, schedule, trigger policy
- [x] Add `JobRun` types: run id, job id, trigger, status, timestamps, summary
- [x] Add `JobStepRun` types: step id, status, timings, logs, metrics, retry state
- [x] Add `ArtifactRecord` types: artifact id, run id, type, path, metadata, scope
- [x] Add `WorkflowDefinition` types: step graph, retry policy, output bindings
- [x] Add job storage package for definitions, runs, step state, artifacts, and indexes
- [x] Add tests for persistence, reload, status transitions, and disk layout

Deliverable:
- a durable generic job model on disk

## Phase 2: Job Runtime and Scheduler

- [x] Add generic job runtime manager under `gateway`
- [x] Add manual trigger path for one job definition
- [x] Add periodic scheduler for due jobs
- [x] Add checkpoint persistence per job definition
- [x] Prevent duplicate concurrent runs for the same job when policy forbids it
- [x] Add retry and backoff policies at runtime level
- [x] Add status inspection for active and recent runs
- [x] Add tests for scheduling, checkpoint recovery, and duplicate-run suppression

Deliverable:
- gateway can run generic jobs continuously in the background

## Phase 3: Workflow Execution Engine

- [x] Add workflow execution engine for multi-step jobs
- [x] Add step input/output passing between workflow steps
- [x] Add step-level retry and failure semantics
- [x] Add workflow cancellation and force-stop semantics
- [x] Add structured logs and step summaries
- [x] Add tests for workflow progression, failure, retry, and cancellation

Deliverable:
- jobs can be composed from reusable workflow steps

## Phase 4: Artifact Storage and Management

- [x] Add artifact writer/reader package
- [x] Add artifact indexing by job, run, type, and logical scope
- [x] Add append-only artifact history where appropriate
- [x] Add retention, archive, and cleanup policies
- [x] Add artifact listing/get APIs in gateway
- [x] Add tests for artifact indexing, retrieval, and cleanup safety

Deliverable:
- job outputs are durable and queryable as first-class artifacts

## Phase 5: Chat Over Job Artifacts

- [x] Add chat binding model from job outputs to chat scopes
- [x] Add retrieval service over artifacts
- [x] Add context assembler for grounded chat answers from artifacts
- [x] Add cited answer format referencing artifact source and location
- [x] Add gateway/CLI chat API for job-bound questions
- [x] Add tests for scope resolution, retrieval, and citation behavior

Deliverable:
- users can ask questions about job outputs through chat

## Phase 6: AI Analysis Workflows

- [ ] Add generic AI analysis workflow support
- [ ] Allow workflow steps to invoke MoonClaw with chosen model, tools, and skills
- [ ] Persist structured analysis outputs and readable reports as artifacts
- [ ] Add workflow-level cost, timeout, and skip policies
- [ ] Add tests for analysis workflow execution and persistence

Deliverable:
- any job family can attach AI analysis steps to its workflows

## Phase 7: Gateway API and CLI Surface

- [ ] Add gateway RPC for job definitions, runs, artifacts, and chat
- [ ] Add HTTP surface for the same operations
- [ ] Add CLI commands for job list/create/update/run/inspect
- [ ] Add CLI commands for artifact list/get and job-bound ask
- [ ] Document the operator flow for running jobs under gateway

Suggested RPC surface:
- `jobs.list`
- `jobs.get`
- `jobs.create`
- `jobs.update`
- `jobs.run`
- `jobs.cancel`
- `jobs.force_cancel`
- `runs.list`
- `runs.get`
- `artifacts.list`
- `artifacts.get`
- `jobs.ask`

Deliverable:
- the generic job system is controllable through the existing MoonClaw surfaces

## Phase 8: Research as the First Built-in Job Family

- [ ] Add `research.topic.sync` job definition kind
- [ ] Add `research.paper.fetch` job definition kind
- [ ] Add `research.paper.parse` job definition kind
- [ ] Add `research.paper.analyze` job definition kind
- [ ] Add `research.paper.ask` chat binding conventions
- [ ] Add arXiv client and feed parsing
- [ ] Add PDF download and paper asset persistence
- [ ] Add paper text extraction and chunk artifacts
- [ ] Add research-specific analysis workflows such as summary, novelty, critique, and reproduction checklist
- [ ] Add tests for arXiv ingestion and paper artifact lifecycle

Deliverable:
- research works as a concrete job family built on the generic platform

## Phase 9: Research Management UX

- [ ] Add topic-oriented management APIs and CLI on top of generic jobs
- [ ] Add paper list/detail views from research artifacts
- [ ] Add paper-scoped and topic-scoped ask commands
- [ ] Add TUI views for research topics, papers, and analyses
- [ ] Ensure cited answers render well in TUI and Feishu

Deliverable:
- research is pleasant to use, not only technically possible

## Phase 10: Quality and Retrieval Improvements

- [ ] Add better ranking over artifacts and chunks
- [ ] Add metadata filtering by date, kind, topic, tag, and status
- [ ] Add section-aware retrieval for paper artifacts
- [ ] Evaluate optional embeddings only after baseline retrieval is stable

Deliverable:
- better chat quality without changing the core job abstraction

## Phase 11: Safety, Cost, and Operations

- [ ] Add per-job and per-workflow limits
- [ ] Add model/time/cost guardrails
- [ ] Add malformed-input quarantine states
- [ ] Add artifact retention and cleanup protections
- [ ] Add operator docs for background execution, restart recovery, and observability

Deliverable:
- the job platform is safe to run continuously

## Testing Plan

- [ ] job definition persistence tests
- [ ] run and step transition tests
- [ ] scheduler and checkpoint recovery tests
- [x] workflow retry/cancel/force-cancel tests
- [x] artifact indexing and retrieval tests
- [x] chat over artifacts tests
- [ ] AI analysis workflow persistence tests
- [ ] research/arXiv integration tests

## Initial Build Order

- [ ] Finish Phase 1 before any research-specific implementation
- [ ] Finish Phase 2 before adding scheduled research sync
- [x] Finish Phase 3 before adding analysis workflows
- [x] Finish Phase 4 before artifact chat
- [x] Finish Phase 5 before research ask UX
- [ ] Finish Phase 8 before TUI/channel research polish

## Non-Goals for v1

- [ ] Do not merge `daemon` into the job runtime
- [ ] Do not make embeddings mandatory
- [ ] Do not make research-specific storage bypass the generic artifact system

## Notes

- `research` is the first consumer of the job platform, not a separate architecture
- future job families should reuse the same scheduler, workflow engine, artifact store, and chat binding model
- append-only artifacts are preferred when auditability matters
