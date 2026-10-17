# Continue blocked work

The Work screen now provides **Continue blocked work** for its exact linked run.
It brings retained completed steps, the waiting question, and exact artifact
versions into one input-recovery workflow, rather than asking an owner to
reconstruct the interruption from a transcript.

1. Open the existing Work thread and expand Continue blocked work.
2. Refresh retained checkpoint. Read the observed time, completed steps, waiting
   step summary/error, and available artifact versions. Use the existing Runs
   and Artifacts views for full journal and content inspection.
3. Enter missing input within the original approved scope. The answer is saved
   in this browser tab for the gateway, work thread, folder and run. Reload or
   leave/return to the same thread to reopen it.
4. Continue this blocked step re-reads the checkpoint and sends the answer with
   its exact checkpoint precondition through the existing resume endpoint. No
   replacement run or new job is created by this workflow.
5. Refresh to inspect actual progress. If a newer waiting checkpoint appears,
   the older answer stays visible, but cannot be sent until the owner reviews
   the new evidence and explicitly chooses Use retained answer for reviewed
   checkpoint. Edit the answer as appropriate before continuing.

## Connected contract

GET `/v1/cowork/sessions/{session}/runs/{run}/recovery` requires the session's
current linked run, uses the normal gateway authentication path, and returns
`moonclaw.blocked-recovery.v1` with `Cache-Control: no-store`. It contains only
step IDs/status/summary/error, artifact IDs/logical keys/versions and an observed
time. Raw step outputs, logs, metrics and artifact bytes are excluded.

The checkpoint SHA-256 binds gateway session key, effective work folder, message
count, full run and step state, artifact records and journal event count. An
observation timestamp does not change that token. A changed wait, updated
artifact, new journal event, or saved resume message invalidates it.

POST on the existing `/resume` path accepts optional `expected_checkpoint`.
New controls always supply it. The handler checks exact session/run ownership,
serializes resume requests for the run in-process, refuses a pending active
launch, compares the current input checkpoint, and requires an active runtime.
After saving input it rechecks the exact checkpoint again before launch, so a
concurrent stop, folder/link change or newer wait is not undone. It retains the resume message before
launch and preserves the existing run identity. Existing legacy callers may omit
the precondition, but now also receive exact linked-run and active-runtime guards.

Resume is available only for WaitingForInput with exactly one waiting step and
all other retained steps Pending or Succeeded. Mixed running, failed or cancelled
steps fail closed. This is a missing-input continuation, not a generic failed-job
retry or an adapter-effect reconciliation implementation. A waiting status alone
cannot prove that an external adapter has no unresolved effects. Such effects
still require their established reconciliation and authority checks.

## Interruption semantics

The answer is marked uncertain in tab storage before sending. A disconnect,
Stop waiting for response, navigation, or token change does not imply execution
stopped. Refresh requests the original checkpoint through the bounded
`X-Moonclaw-Recovery-Checkpoint` header, even after later resumptions, and compares
the returned receipt’s exact UTF-8 content digest with the saved answer. A
matching marker and digest mean the gateway recorded that input; it does not prove that
launch or execution completed. A crash between retaining input and launching
therefore remains inspectable without claiming success.

If the original checkpoint is still current, the owner can explicitly retry the
same conditional answer. The server's run-scoped lock and checkpoint comparison
refuse concurrent or already-recorded repeats. No automatic mutation retry is
performed. A receipt for another answer marks this draft superseded, keeps it intact, and
requires explicit review before reuse. A definite first-submit rejection returns
the answer to editable draft state. If the checkpoint changed without any
receipt or definite refusal, the submission remains uncertain and further continuation is disabled; investigate
through the retained run/journal. The panel never creates a replacement run.

Corrupt saved state is retained untouched and blocked. Full/unavailable browser
storage is disclosed; the in-memory answer remains visible, but reload retention
is not guaranteed. Storage contains the user's answer and checkpoint, never the
gateway token. Server checkpoints are freshness preconditions, not authorization
or proof that result quality improved. Original runtime authority and human
acceptance boundaries continue to apply.

## Source grounding and qualification

This implements a narrow connected slice of actual MoonClaw PRD MC-W07 and
MOONCLAW-R02 (owner-oriented recovery projection) and MC-W01/B01 (same durable
identity). It builds on `current_job_routine.md` in-place WaitingForInput resume.
It does not claim full R02, B09/N01 effect reconciliation, usability results,
provider execution, restart-soak qualification, RSI or emergence.

Run `bash scripts/test-blocked-recovery.sh` from any working directory. Native
projection/HTTP tests are in `gateway/server/cowork_recovery_wbtest.mbt`; Rabbita
render coverage is in `main/blocked_recovery_surface_wbtest.mbt`. The round's
FEATURE.json records exact commands and observed outcomes. Rebuild the operator
UI for deployment; the committed historical dist is not silently regenerated.
