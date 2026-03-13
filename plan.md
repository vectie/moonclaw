# Research Tool Plan

This plan tracks the work to extend MoonClaw into a paper research system with two core capabilities:

- fetch and manage important arXiv papers for chosen topics, both manually and on a schedule
- answer questions about papers in chat, or automatically analyze them with MoonClaw using configured skills and workflows

Mark a task complete only after implementation, validation, and any required docs/tests for that slice are done.

## Product Goals

- make paper ingestion durable and disk-first
- make topic tracking explicit and manageable through gateway and CLI
- make paper Q&A grounded in stored paper content with citations
- make automatic analysis reusable through workflows instead of one-off prompts
- keep the runtime under `gateway`, not `daemon`

## Architecture Decisions

- research runtime lives under `gateway`
- papers and metadata are persisted under `~/.moonclaw/research`
- fetched source metadata, extracted text, chunks, and analyses are stored separately
- research chat answers should be cited by default
- embeddings are optional later work, not a v1 dependency

## Disk Layout

- `~/.moonclaw/research/topics.json`
- `~/.moonclaw/research/index/papers.json`
- `~/.moonclaw/research/index/topic/<topic_id>.json`
- `~/.moonclaw/research/papers/<paper_key>/meta.json`
- `~/.moonclaw/research/papers/<paper_key>/paper.pdf`
- `~/.moonclaw/research/papers/<paper_key>/paper.txt`
- `~/.moonclaw/research/papers/<paper_key>/chunks.json`
- `~/.moonclaw/research/papers/<paper_key>/analyses/<workflow>/<timestamp>.json`

`paper_key` should be a stable normalized arXiv id plus version.

## Phase 1: Research Data Model

- [ ] Add research topic types: topic id, query, categories, enabled flag, fetch policy, analysis policy
- [ ] Add paper metadata types: arXiv id, version, title, authors, abstract, categories, published/updated timestamps
- [ ] Add paper asset/state types: file paths, fetched/parsed/analyzed timestamps, status, tags, notes
- [ ] Add research storage package for loading and saving topics, papers, and indexes
- [ ] Add tests for storage persistence, reload, dedupe keys, and version handling

Deliverable:
- durable topic and paper registry on disk

## Phase 2: arXiv Fetching

- [ ] Add arXiv client package for search by query and fetch by arXiv id
- [ ] Add manual fetch for one paper id
- [ ] Add manual fetch for one configured topic
- [ ] Download and store PDF plus source metadata
- [ ] Dedupe by arXiv id and version
- [ ] Detect updated paper versions without corrupting old assets
- [ ] Add tests for search/feed parsing and version update behavior

Deliverable:
- manual paper/topic fetch into persistent storage

## Phase 3: Parsing and Normalization

- [ ] Add PDF-to-text extraction pipeline
- [ ] Normalize extracted text for whitespace, headers, and page breaks
- [ ] Detect major sections when possible
- [ ] Chunk paper text into stable retrieval units
- [ ] Persist `paper.txt` and `chunks.json`
- [ ] Add tests for extraction fallback, chunk generation, and stable chunk ids

Deliverable:
- stored papers are readable and chunked for retrieval

## Phase 4: Topic and Paper Management Surface

- [ ] Add topic CRUD operations in gateway service
- [ ] Add paper list/get operations in gateway service
- [ ] Add paper tagging, notes, and state markers such as starred/read/irrelevant
- [ ] Add CLI commands for topic and paper management
- [ ] Add RPC/HTTP surface for topic and paper management
- [ ] Document the research storage and management flow

Gateway RPC target surface:
- `research.topics.list`
- `research.topics.create`
- `research.topics.update`
- `research.topics.fetch`
- `research.papers.list`
- `research.papers.get`
- `research.papers.fetch`

Deliverable:
- topics and papers are manageable without touching raw files

## Phase 5: Research Chat and Q&A

- [ ] Add research retrieval service for paper-scoped, topic-scoped, and corpus-scoped lookup
- [ ] Add context assembler that builds grounded prompt context from retrieved chunks
- [ ] Add cited answer format with paper id, section, and page/chunk references when available
- [ ] Add gateway research chat API
- [ ] Add CLI command for paper/topic question answering
- [ ] Add tests for retrieval scope resolution and citation-bearing answers

Suggested user-facing commands:
- `/paper ask <paper_id> <question>`
- `/topic ask <topic_id> <question>`
- `moonclaw research ask --paper <paper_id> --question "..."`

Deliverable:
- users can ask questions about stored papers via chat/CLI and get grounded answers

## Phase 6: Automatic Analysis Workflows

- [ ] Add workflow definitions for paper analysis
- [ ] Add per-topic and per-paper workflow trigger configuration
- [ ] Add analysis runner that invokes MoonClaw with selected model, tools, and skills
- [ ] Persist structured analysis results and readable output artifacts
- [ ] Add built-in starter workflows:
- [ ] structured summary
- [ ] novelty extraction
- [ ] methodology critique
- [ ] reproduction checklist
- [ ] implementation ideas
- [ ] Add tests for workflow persistence and rerun/skip behavior

Deliverable:
- papers can be automatically analyzed by reusable AI workflows

## Phase 7: Scheduler and Background Runtime

- [ ] Add research scheduler inside `gateway`
- [ ] Persist per-topic fetch checkpoints
- [ ] Add periodic topic fetch execution
- [ ] Add parse job queue for newly fetched papers
- [ ] Add analysis job queue for configured workflows
- [ ] Prevent duplicate concurrent runs for the same topic or paper
- [ ] Add status inspection for scheduled fetch/parse/analyze jobs
- [ ] Add tests for checkpoint recovery and duplicate-run suppression

Deliverable:
- gateway can run paper tracking continuously in the background

## Phase 8: TUI and Channel UX

- [ ] Add TUI topic list and paper list views
- [ ] Add paper detail and analysis result views
- [ ] Add TUI paper question mode
- [ ] Add slash commands for research chat in channel/TUI flows
- [ ] Ensure cited answer formatting remains readable in Feishu/TUI

Deliverable:
- research features are accessible in the main UI and chat surfaces

## Phase 9: Retrieval Quality Improvements

- [ ] Add section-aware ranking
- [ ] Add metadata filters such as date/category/topic/tag
- [ ] Add optional corpus-wide ranking improvements
- [ ] Evaluate whether embeddings are necessary after baseline retrieval is working

Deliverable:
- better answer quality without changing the core storage model

## Phase 10: Safety, Cost, and Operations

- [ ] Add per-topic fetch limits
- [ ] Add per-workflow model/time/cost budgets
- [ ] Skip already analyzed same-version papers unless forced
- [ ] Add malformed-PDF and extraction failure quarantine states
- [ ] Add operator docs for running research tracking under gateway

Deliverable:
- research runtime is controllable and safe to operate continuously

## Testing Plan

- [ ] arXiv search/feed parsing tests
- [ ] storage and reload tests
- [ ] version dedupe/update tests
- [ ] PDF extraction and chunking tests
- [ ] gateway API tests for research topic/paper flows
- [ ] Q&A retrieval and citation tests
- [ ] workflow execution persistence tests
- [ ] scheduler checkpoint and recovery tests

## Initial Build Order

- [ ] Finish Phase 1 before any gateway research API work
- [ ] Finish Phase 2 before scheduler work
- [ ] Finish Phase 3 before paper Q&A
- [ ] Finish Phase 5 before automatic analysis workflows
- [ ] Finish Phase 7 before TUI/channel polish

## Notes

- `gateway` remains the long-lived runtime for this feature
- `daemon` should not be merged into this plan
- do not introduce embeddings until the disk model, retrieval flow, and cited answer path are stable
- keep analyses append-only so results remain auditable over time
