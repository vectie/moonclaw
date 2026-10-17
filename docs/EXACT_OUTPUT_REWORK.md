# Revise an exact output

The Work screen now connects a retained output to a new bounded revision task.
This is the agent's next-task drafting journey, not artifact acceptance, automatic
retry, blocked-step continuation, or a second execution system.

1. Open an existing Work thread with a linked terminal run and configured gateway
   access. Expand **Revise an exact output** beside **Use what worked**.
2. **Load linked outputs**, select a retained textual artifact, then **Inspect
   selected revision**. Read its complete original text, exact ID, revision and
   SHA-256. Failed and cancelled runs are usable sources but stay explicitly
   labelled; their artifacts are not represented as successful or accepted work.
3. Describe specific changes, constraints to preserve, and how to verify the new
   result. Write the new task in the ordinary work composer as well.
4. **Put revision task in draft** rereads the linked run and exact artifact. If the
   artifact changed, access changed, selection changed, or the draft was edited
   while loading, it leaves the draft untouched. Inspect changed sources anew.
5. Use the ordinary **Plan → Preview → Promote → Confirm** path. The task contains
   the exact retained text and digest, requested changes, preserved constraints
   and checks. Inspect the proposed operations before confirming any new work.
   Result inspection stays in the existing run and Artifacts controls.

## Connected implementation and authority

The shipped bootstrap mounts an ordinary DOM panel alongside the existing
Rabbita Work procedure surface, after that surface renders. It reads that
surface's selected session, saved work-folder and linked-run context and writes
through the existing composer input event (`SetCoworkComposer`). No generated
MoonBit UI or native executable changed. Switching thread, linked proposal,
folder or gateway access discards unsent selections and panel fields.

The panel uses the host's existing authenticated fetch transport and only GETs
`/v1/jobs/runs/{run_id}` and `/v1/artifacts/{artifact_id}`. It requires the native
artifact route's `revision_source` envelope, matching run/job/ID/version/type,
and a host-provided digest matching the exact UTF-8 text. Binary and synthetic
artifacts are excluded. Each source is limited to 32 KiB, each instruction to
4,000 UTF-8 bytes, and the JSON packet to 64 KiB. Nothing is truncated.

The packet `moonclaw.artifact-rework.v1` is framed as untrusted historical task
input and carries `authority_granted: false` and `accepted_output: false`.
Artifact contents do not become user instructions or additional permissions.
The panel sends no POST and starts no job. It asks for a new output while leaving
the original unchanged. Choosing a source does not grant access to its folder,
external sources, tools, publication, or spending. Normal runtime approval still
owns execution. A locally computed hash and gateway response are source integrity
checks, not a signature or certification of output quality.

Reapplying replaces only the panel's marked JSON block, preserving all text and
restrictions before and after it byte-for-byte. Ambiguous/incomplete blocks fail
closed. Sent packets persist in the ordinary plan request; no separate browser
history store is introduced. Reload loses unsent panel form fields. A source
change after insertion does not rewrite the captured request; the draft retains
its exact historical snapshot for review.

## Verification and limits

`node --test ui/rabbita-job/artifact-rework.test.mjs`

Functional tests run the actual mount, installer and controller with a minimal
DOM and synthetic gateway responses. They exercise load/inspect/fresh-read/draft
input, durable-request serialization, preserved suffix restrictions, hashes,
identity/type/size failures, failed/cancelled versus unknown/running states,
changed source, duplicate clicks, cancellation, draft edits, A→B→A context races,
access loss, folder mismatch and explicit gateway denial. Adjacent procedure,
blocked-recovery and Book handoff tests are run by the round's `run-focused.sh`.

This is source-only local verification. Browser layout/accessibility observation,
live gateway/provider execution, real model-quality improvement, installed dist
build and release qualification remain unrun. The production dist was not rebuilt.
The native-server fixture in the adjacent regression suite remains skipped
without its explicit server environment. No native compilation or new dependency
installation was needed for this JavaScript-only change.
