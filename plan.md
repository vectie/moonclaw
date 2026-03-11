# Gateway Integration Plan

This plan tracks the foundation work needed to bring MoonClaw closer to the reference design in `../cla`.

## Goals

- make the gateway durable across restarts
- make session routing explicit and reusable
- make channel runtime state recoverable instead of process-local only
- expose the stronger gateway surface through the existing client/runtime paths

## Tasks

- [x] Add persisted gateway session store with load/save hooks and tests
- [x] Extract a shared session route/key resolver for direct runs, channels, and orchestration
- [x] Persist channel configuration/runtime intent and restore enabled channels on gateway startup
- [x] Extend gateway client/API coverage for runs and channels
- [x] Add integration-oriented gateway tests for persisted sessions and channel lifecycle
- [x] Update docs to describe the new persistence and routing flow

## Notes

- Keep package-level `README` files untouched unless the implementation changes their behavior.
- Mark a task complete only after code, tests, and validation for that slice are done.
