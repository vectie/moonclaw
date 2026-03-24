# Operator Canvas Guide

This guide explains how to read the Rabbita jobs canvas for controller-style
runs such as OPC workflows.

## What the Canvas Is

The canvas is not a freeform whiteboard. It is a structured operator surface
built from run state.

The design goal is:

- keep execution auditable like a workflow tree
- make parallel role work visible like a company board

## Current Canvas Layers

For controller runs, the UI now combines several layers:

- `Split Work`
- company health strip
- lane sequence
- handoff cards
- horizontal role lanes
- `Merge Results`
- audit tree and timeline below

## Split and Merge

The canvas synthesizes two structural anchors:

- `Split Work`
  where the controller fans work out into steps and delegated workers
- `Merge Results`
  where run-level artifacts and memories collect back together

These are visual organization nodes. They make controller runs easier to scan.

## Role Lanes

Steps are grouped into horizontal lanes such as:

- `CEO`
- `Engineering`
- `Implementation`
- `Review`
- `QA`
- `Shipping`

The board prefers explicit step metadata:

- `board_lane`
- `board_order`

If that metadata is missing, the UI falls back to heuristics.

## Handoffs

The lane sequence and handoff cards are there to make the company process legible.

Examples:

- `CEO -> Engineering`
- `Engineering -> Implementation`
- `Implementation -> Review`
- `Review -> QA`
- `QA -> Shipping`

These are operator-facing summaries of the workflow shape, not a separate runtime.

## Health Strip

The company health strip summarizes each department or lane with:

- active count
- blocked count
- waiting count
- done count
- worker count

This gives a fast view of where a run is stuck or progressing.

## Child Runs

Delegated worker runs remain visible under the owning step.

So the canvas shows both:

- the company-level lane view
- the actual child execution lineage

This is why it still works as an operator tool instead of becoming a purely decorative board.

## How To Control the Board

The recommended way to shape the board is in `moonclaw.jobs.json`.

Example:

```json
{
  "id": "qa",
  "title": "QA pass",
  "kind": "job.delegate",
  "metadata": {
    "board_lane": "QA",
    "board_order": 4
  }
}
```

That keeps board layout profile-driven instead of hardcoded in core.

## What the Canvas Is Not

Today it is not:

- a free pan/zoom infinite canvas
- a generic graph editor
- a manual drag-and-drop workflow builder

It is a runtime-derived operational board.

## Where To Learn More

- [docs/current_job_routine.md](/Users/kq/Workspace/moonclaw/docs/current_job_routine.md)
- [docs/extension_packs.md](/Users/kq/Workspace/moonclaw/docs/extension_packs.md)
- [docs/examples/opc_job_test_guide.md](/Users/kq/Workspace/moonclaw/docs/examples/opc_job_test_guide.md)
