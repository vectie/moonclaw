# Artifact checkpoint recovery

This implements the bounded append-only artifact-revision portion of MOONCLAW-B04: reopening a run retains its confirmed revisions even when the shared artifact index checkpoint was lost. It does not qualify the whole requirement or external effect reconciliation.

## Persistence and recovery

- `artifacts/<id>/record.json` is the authoritative metadata checkpoint. Existing content paths and metadata shapes remain readable. `index/artifacts.json` remains the same JSON format and is a rebuildable cache
- Record and index updates write a sibling `.pending` file before atomic rename. Uncommitted `.pending` files are never read as confirmed records
- Artifact writes acquire the existing per-store semaphore and filesystem lock before refreshing records and assigning a revision. Independently loaded stores therefore cannot allocate the same next revision for the same logical output
- Recovery begins with readable legacy index entries, then overlays valid per-artifact records. A malformed sibling record cannot prevent valid outputs opening. A readable cached entry remains available when its record is malformed or absent
- `SystemStore::list_artifact_recovery_issues()` exposes incomplete/unreadable records, missing content, a corrupt index, and a pending index repair. Recovery does not invent metadata for orphan content or hide a known artifact solely because its bytes are missing
- A cache repair failure does not prevent readable results loading. A write-side checkpoint failure still raises to the caller; committed records can subsequently be recovered without executing the job again
- Repeating persistence with the same append-only identity and exactly matching content and request metadata returns its original version and timestamp. Conflicting output under that identity raises before replacing any confirmed bytes. Execution is never dispatched by recovery or persistence retry
- Deletion first commits a marker under `index/deleted-artifacts/`. A stale index or independently loaded writer cannot resurrect that artifact. Deleted identities are not reused

## Existing semantics and limits

Explicit `append_only=false` outputs remain mutable with the same identity/version and last-write-wins semantics. This milestone does not convert mutable outputs into immutable history or qualify a crash between their content replacement and metadata replacement. Callers needing inspectable revisions must retain the default append-only mode.

Atomic rename protects process-interruption checkpoints on the existing POSIX filesystem. Power-loss/fsync guarantees, missing-volume recovery, external modifications to confirmed content, remote stores, and arbitrary complete-store corruption are not qualified here. Uncommitted content and temporary files are retained for investigation; no new automatic cleanup is introduced.

The direct MoonClaw → MoonGate model route, provider selection, execution authorization, external effect behavior, and other products' contracts are unchanged. ArtifactStore reads and the existing job UI snapshot use recovered records without requiring a new UI schema.

## Focused verification

`moon test job/artifact_recovery_wbtest.mbt --target native --strip -j1`

The controlled fixtures cover stale/missing/corrupt indexes, exact read and UI projection of multiple revisions, legacy index-only entries, malformed sibling records, stale/concurrent writers, interrupted record and cache checkpoints, identical/conflicting persistence replay, deletion resurrection, and missing content. They use temporary local directories and do not call providers, start listeners, or rerun external effects.
