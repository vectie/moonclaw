# OPC Job Test Guide

This is a concrete way to test a one-person-company controller workflow on top
of MoonClaw's generic runtime.

## 1. Install the example pack into a workspace

Copy the example job profile into the workspace you want to run:

```bash
mkdir -p ~/.moonsuite/products/moonclaw/opc-workspace/skills
cp /Users/kq/Workspace/moonclaw/docs/examples/opc_moonclaw.jobs.json ~/.moonsuite/products/moonclaw/opc-workspace/moonclaw.jobs.json
cp -R /Users/kq/Workspace/moonclaw/docs/examples/opc_skills ~/.moonsuite/products/moonclaw/opc-workspace/skills
```

This keeps OPC behavior workspace-local. It does not change global runtime
config in `~/.moonsuite/products/moonclaw/moonclaw.json`.

## 2. Start the gateway against that workspace

```bash
moon run cmd/main -- gateway start --home ~ --cwd ~/.moonsuite/products/moonclaw/opc-workspace
```

## 3. Trigger an OPC-style sprint

Use Feishu, UI chat, or the gateway chat surface and send:

```text
/plan-job Build and ship a small but polished feature sprint for a weekly founder update dashboard.
```

Then confirm it:

```text
/confirm <proposal_id>
```

## 4. What success looks like

You should see:

- the proposal family become `opc_feature_sprint`
- controller-shaped steps:
  - `ceo_review`
  - `eng_plan`
  - `implement`
  - `review`
  - `qa`
  - `ship_decision`
- analysis steps use role skills from `skills/`
- delegate steps compile as real `job.delegate` workers, not mislabeled analysis steps
- each delegate step targets a named child worker profile:
  - `opc_impl_worker`
  - `opc_review_worker`
  - `opc_qa_worker`
- each delegate step can also carry routing intent such as:
  - `execution_mode: acp`
  - `execution_target: codex-impl` / `codex-review` / `codex-qa`
- those child worker profiles apply their own role-specific skills and prompts
- controller state and lineage persist for the run
- the run workspace appears under `.moonsuite/products/moonclaw/jobs/<run-id>`

## 5. What this proves

This demonstrates the intended extension boundary:

- MoonClaw core stays generic
- OPC behavior comes from `moonclaw.jobs.json`
- child worker roles also come from `moonclaw.jobs.json`
- role behavior comes from `skills/`
- controller bookkeeping, delegation, artifacts, and notifications are reused

## 6. What this does not prove yet

The gateway now honors `execution_mode: "acp"` plus `execution_target` for the
common worker case where the delegated child job compiles to a single
`job.analysis` step.

More complex child workflows still fall back to the local workflow engine.
