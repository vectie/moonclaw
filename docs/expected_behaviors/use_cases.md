# Use Cases

This document describes the main use cases the current MoonClaw implementation is designed to support well.

## 1. Feishu As An Operator Surface

Use case:

- run MoonClaw as a gateway service
- control jobs from Feishu chat
- receive job lifecycle notifications in the same chat

Expected fit:

- good fit today
- especially strong for draft -> confirm -> run workflows

## 2. Long-Running Async Jobs

Use case:

- run work that should continue in the background
- inspect status later
- stop or force-stop if necessary

Examples:

- repository analysis
- recurring checks
- multi-step analysis tasks
- delegated workflows with subjobs

Expected fit:

- strong fit today

## 3. Research Jobs

Use case:

- fetch and parse papers
- analyze papers
- ask questions over resulting artifacts

Expected fit:

- strong as the first built-in job family
- good for research topic sync, paper fetch/parse/analyze, and artifact-grounded follow-up chat

## 4. Workspace-Centric Execution

Use case:

- give each job or subjob its own isolated workspace
- inspect the run’s file changes and git checkpoints
- keep memory close to the run workspace

Expected fit:

- strong fit today

## 5. Memory-Augmented Planning And Execution

Use case:

- remember facts, routines, and notes
- reuse them in planning, execution, and artifact Q&A

Expected fit:

- good fit today
- especially for operator notes and recurring job context

## 6. What Is Not The Main Fit Yet

These are possible directions, but they are not the strongest current use cases:

- full multi-agent routing based on config `bindings`
- mature plugin installation/runtime lifecycle
- polished onboarding/wizard flows
- strict OpenClaw feature parity for every config surface

The current system is strongest as:

- a long-running gateway
- with channel-driven job planning
- async execution
- dedicated run workspaces
- memory and artifact retrieval
