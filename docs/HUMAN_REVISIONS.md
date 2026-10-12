# Human-revised artifact copies

Open a retained UTF-8 text or JSON artifact from its run. Edit the draft, compare
the original source, then choose **Save human-revised copy**. A gateway token
must be configured using the existing Runtime & gateway access controls. The
new write route is disabled when the gateway itself has no configured token.

The saved copy has artifact type `human_revision`, its own exact artifact ID,
and a separate append-only logical lineage. Its host-authored metadata records
the parent artifact ID/version/SHA-256, new SHA-256, lineage root, save ID, and
human attribution. It is explicitly neither executor output nor accepted output.
The source artifact, run state, event log, execution authority and provider route
are unchanged. Saving does not execute commands, invoke providers, promote Fort
outputs, import into Book, or accept evidence.

The draft stays in this tab's memory across Close, navigation, and failed saves.
Reloading or closing the tab loses unsaved drafts; browser storage is not used.
After an uncertain response, choose **Retry same save**. Editing is suspended
until that exact request is resolved, so a lost acknowledgement cannot silently
become a conflicting write. The gateway returns the original record for an exact
replay, including its original version and timestamp. A different payload under
the same ID is rejected. A changed source is rejected without replacing the
draft. Reopen the source, compare it, and explicitly choose **Use reopened source
as parent** before saving a newly based copy.

After confirmation, **Open saved human-revised copy** opens the retained result.
Use Download there for its exact bytes; Download on the original still downloads
the original, not the current editor draft. The selected run's list includes the
confirmed copy. Success confirms durable retention, not browser file-save completion.

## API

`POST /v1/jobs/runs/{run_id}/artifacts/{parent_id}/human-revisions`

The JSON body has exactly three string fields: `save_id`,
`expected_parent_digest`, and `content`. Extra fields, caller paths, attribution,
metadata and role declarations are rejected. IDs are decoded once and validated.
The host resolves the parent run/job and bytes under the artifact store lock.
Text is bounded to 8 MiB and must be lossless UTF-8. Binary and synthetic previews
remain read-only. The source envelope returned when opening an eligible retained
artifact includes its current digest and parent version.

Persistence reuses record-first checkpoints, the rebuildable artifact index,
filesystem locking, tombstones and exact-ID replay. Missing or stale indexes
recover confirmed human copies. Partial record checkpoints remain unconfirmed;
retry after storage repair uses the same save ID. External file tampering,
power-loss/fsync guarantees and total store corruption remain outside this
bounded local POSIX checkpoint contract.

## Focused verification

Native tests target `job/human_revision_wbtest.mbt` and
`gateway/server/human_revision_wbtest.mbt`, alongside existing artifact storage,
recovery, download and auth tests. The native fixture runs the compiled editor
and shipped authenticated fetch path against a real loopback gateway, then
starts a fresh native process to reopen and download the exact saved bytes.
UI tests cover Close/navigation, A–B–A stale responses, failed-save draft
retention, stable retries and source/draft comparison. All fixture tokens and
records are synthetic; no real provider or external host is used.
