# Use what worked in the operator Work screen

This is a narrow operator workflow over the existing Cowork plan and job path.
It does not add an agent runtime or change supervisor selected-Book hydration.

## Actual operator steps

1. Open **Work**, select an existing thread, and save its existing work-folder
   setting to the Book root containing `memory/procedures`. The procedure panel
   reads only that session's saved folder. It does not search the machine or
   initialize a Book. Configure the gateway's existing authentication and enter
   its token through the ordinary access controls before opening private records.
2. Open **Use what worked** and **Load accepted procedures**. Search all words
   from the intended task. Select an approach, inspect the full original source,
   applicability and invalidation clauses, and any recorded outcome and effort.
   Text search discovers candidates; it never establishes applicability.
3. Explain why the method applies and what delivered result you expect, including
   how to check it. Write the actual work request in the ordinary composer.
   **Use selected approach in draft** rereads the existing capture and requires
   the same selected path and digest still to be admitted. A changed/rejected
   record leaves the draft unchanged. The exact method, source digest and
   operator interpretation become a clearly framed historical-context block in
   the ordinary draft. Repeated application replaces only that one block, preserving
   all surrounding draft text and whitespace, including restrictions added afterward.
4. Use the existing **Plan**, **Preview**, **Promote**, and **Confirm** controls.
   Inspect the resulting scope before confirming. Procedure selection performs
   no POST, starts no run, and grants no authority. The ordinary planner and
   runtime continue to own their existing bounded execution, including any
   planned `job.delegate` steps. This feature does not force child delegation.
5. Return to this thread and choose **Compare with linked result**. The comparison
   reads the procedure choice retained in the linked proposal's original request,
   then fetches its exact linked run. It shows expected versus delivered summary,
   original recorded outcome/effort, retained artifact identities/versions, and
   recorded elapsed runtime when both native timestamps exist. Open **Artifacts**
   to inspect the actual deliverables. Running, failed and cancelled results stay
   distinct. Tokens and cost are explicitly unmeasured by this comparison.

## Data and ownership

`GET /v1/cowork/sessions/{session_key}/procedures` is an authenticated read. It
requires a configured nonblank gateway token in addition to the gateway's normal
request authentication. The caller provides a session identity, never a path.
The session's existing saved folder is resolved by the host. The endpoint calls
`internal/book_learning.capture`, then projects admitted procedure records only.
It reuses that reader's exact bytes, review-status rules, bounds, cancellation,
filesystem-race limitations and all-or-none failure behavior. It creates no
session, job, Book, new acceptance rule, persistent snapshot, or journal event.
Its internal `workspace_id`/`book_id` labels bind this local session/folder read;
they are explicitly not an assertion about a portable Book's canonical ID.

The response is `moonclaw.cowork-procedures.v1`. Full private procedure text is
returned only by this explicit authenticated operator route. Existing public job
redaction and durable supervisor worker snapshots are unchanged. The source
projection is neither a signature nor proof of current applicability. Selection
checks exact source bytes again; a later Book change does not rewrite already
reviewed work or silently refresh its retained historical source.

The draft block is `moonclaw.procedure-choice.v1`. It retains the complete source,
its exact digest, the operator's applicability reason and expected result, and
`authority_granted: false`. The ordinary plan request/proposal already provides
persistence, so no second browser history database is added. A new linked proposal
without the block cannot inherit an old comparison. Changing the session, saved
folder, access epoch or linked proposal invalidates inventory and comparison;
interruptions and late replies cannot overwrite a newer draft.

Structured JSON fields `title`, `applicability`, `outcome_summary` (or `outcome` /
`outcomes`), `effort`, and `verification` are displayed verbatim when present.
They are optional source-authored evidence, not a new Book schema. Markdown and
legacy records remain fully readable. Missing structured measurements are
labelled unknown rather than estimated, ranked or inferred. No claim of improved
quality, lower cost, customer acceptance or Book promotion is generated.

## Verification and limits

Run the source-only functional tests without downloading dependencies:

```sh
node --test ui/rabbita-job/procedures.test.mjs
```

The tests execute the shipped browser controller with a small DOM fixture, use
actual frozen Book-produced/imported procedure bytes, and exercise source changes,
missing measurements, authority rejection, repeated selection, cancellation,
late replies, context changes, durable-request round-trip and result correlation.
The fixture delivered run and structured outcome/effort record are explicitly
synthetic. They are not evidence of model quality or a running Claw/Book service.
The tests do not substitute for native admission or compiler tests.

Native capture/projection tests live in
`gateway/server/cowork_procedures_wbtest.mbt`; the actual rendered Work surface test
is `ui/rabbita-job/main/procedure_surface_wbtest.mbt`. Current qualification is
blocked because this workspace lacks the declared native and Rabbita dependency
graphs. Frozen check/info were attempted; no dependency restoration was attempted.
Moon formatting passed. The existing production `dist` was not rebuilt. Browser
and live provider/runtime validation remain blocked and are not claimed.

Reload loses unsent selection/reason/expected-result form fields, as the UI says.
The already sent plan's complete source remains in its ordinary durable proposal.
Runtime timing is an execution observation, not a comparable labor or quality
score; missing or nonmonotonic timestamps remain unknown. Final acceptance and
subsequent learning still belong to their existing owner/reviewer workflows.
