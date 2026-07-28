# MoonCode long-horizon prompt comparison — 2026-07-28

## Purpose

This is a prompt-by-prompt comparison of one real long-horizon MoonCode turn
against the actions a careful coding agent should take from the same evidence.
It distinguishes productive work from repeated activity and records only
harness changes justified by an observed failure.

The worker command is
`cmd-moondesktop-phase2-rollup-continuation-20260727` in session
`moondesk-full-plan-autonomous-20260727`. The teacher harness may approve,
reject, or steer authority-bound actions during this evaluation. It does not
implement the target repository change.

## Prompt-by-prompt record

| Planner prompt | MoonCode action | Careful-agent comparison | Result |
|---:|---|---|---|
| 1 | Loaded the complete MoonBit guide before work. | Same action. | Real setup work. |
| 2 | Checkpointed, verified branch state, and read the plan, status, workflows, log, and validator. | Same one-time orientation batch. | Real evidence. |
| 3 | Read project instructions, manifests, and UI dependency files; two read-only searches were falsely approval-gated and a read-only `node -e` was blocked. | Keep the reads, but allow quoted search data and read-only inline inspection. | Useful evidence plus harness friction. |
| 4 | Inspected lock/registry state and npm help; one repository read was falsely classified as out-of-book and `npm ci --help` was falsely approval-gated. | Read help without approval and keep paths book-local. | Partial evidence; classifier bugs exposed. |
| 5 | Inspected registry hosts, installed Rollup state, and lock history; one `head` pipeline exited 141 under `pipefail`. | Avoid a SIGPIPE-prone evidence pipeline or tolerate the expected producer exit. | Mostly useful, one command-shape error. |
| 6 | Described an approval request in prose and called `finish`. | Select the exact gated tool call so the runtime can request approval. | No work; planner-control defect. |
| 7 | Loaded the CI-fix skill after it became available. | Same action before further CI diagnosis. | Real setup work. |
| 8 | Updated the durable checkpoint. | Same action. | Real durable progress. |
| 9 | Repeated the prose approval request and called `finish`. | Emit the exact tool. | No work. |
| 10 | Repeated the same blocked `finish`. | Emit the exact tool. | No work. |
| 11 | Repeated the same blocked `finish`. | Emit the exact tool. | No work. |
| 12 | Repeated the same blocked `finish`. | Emit the exact tool. | No work. |
| 13 | Repeated the same blocked `finish`. | Emit the exact tool. | No work. |
| 14 | Repeated the same blocked `finish`. | Emit the exact tool. | No work. |
| 15 | Repeated the same blocked `finish`. | Emit the exact tool. | No work. |
| 16 | Repeated the same blocked `finish`. | Emit the exact tool. | No work. |
| 17 | After teacher steering, emitted the gated disposable-copy command, but copied the wrong package path and omitted the promised build. | Verify the actual package path and full proof before requesting authority. | Rejected; no execution. |
| 18 | Corrected the path, but asserted that ordinary macOS `npm ci` must install a Linux binary. | Separate host install/build proof from Linux lock metadata. | Rejected as platform-invalid. |
| 19 | Ran a host-aware isolated install; proved Darwin package selection and exposed stale Linux metadata, but copied too few build inputs. | Copy the complete build input set. | Useful install evidence; build failed causally. |
| 20 | Re-read three complete files and attempted two known-absent `.npmrc` files. | Use retained context and advance the hypothesis. | No work; duplicate-read guard prevented waste. |
| 21 | Probed the exact locked tarball, but `set -e` stopped after its timeout before the comparison probe. | Isolate the expected failure so both sides are observed. | Partial causal evidence. |
| 22 | Compared the stale lock URL with the developer machine's configured mirror. | Treat user-global config as local evidence, not repository/CI authority. | Useful distinction, insufficient repair basis. |
| 23 | Marked the cause complete while changing milestone evidence fields. | Preserve the checkpoint contract and finish causality first. | Rejected by checkpoint validation. |
| 24 | Recorded a schema-correct checkpoint, still framed around the local mirror. | Keep the checkpoint but use portable registry authority. | Durable progress with an imperfect next action. |
| 25 | Used `finish` to request approval again. | Emit the exact tool. | No work. |
| 26 | Repeated the same prose approval request. | Emit the exact tool. | No work. |
| 27 | After steering, selected a full-UI disposable proof, but it timed out; the old runtime lost output and leaked the temporary directory. | Bound the command, preserve partial output, cancel descendants, and guarantee cleanup. | Correct intent; runtime timeout defect exposed. |
| 28 | Checked the live tree and located the leaked directory. | Same recovery inspection. | Necessary recovery evidence. |
| 29 | Proposed destructive cleanup after the teacher had already moved the directory recoverably. | Recheck existence immediately and prefer recoverable cleanup. | Rejected as obsolete. |
| 30 | Repeated complete package/lock reads. | Use retained evidence. | No work. |
| 31 | Proposed another registry probe using guessed version `4.44.1` instead of retained `4.60.1`. | Do not guess or repeat established reachability evidence. | Rejected. |
| 32 | Replaced all 50 stale lockfile host prefixes with the official registry, preserving versions and integrity hashes. | Same smallest reviewable repair. | Real product work. |
| 33 | Tested the candidate in a copied UI tree; install passed but build failed because `moon.work` requires the repository root. | Inspect workspace membership and copy the full source graph. | Useful failure and clean recovery. |
| 34 | Archived the complete clean repository, overlaid only the candidate lockfile, then ran isolated install and production build. | Same action. | Real proof; build passed. |
| 35 | Reviewed the complete diff, whitespace, and exact dirty-file set. | Same action. | Real review evidence. |
| 36 | Ran the exact full validator; it reached the UI build but live dependencies were absent. | Either validate in a fully provisioned disposable repository or cross the dependency-mutation approval boundary. | Useful failure; no product defect. |
| 37 | Confirmed the missing live Vite dependency and unchanged tracked scope. | Same narrow diagnosis. | Real evidence. |
| 38 | Ran `npm --prefix ... install` in the live tree to provision validation, bypassing the old classifier's `npm install` substring rule. | Request approval for package-manager mutation even when global options precede the subcommand. | Necessary intent through faulty authority handling. |
| 39 | Re-ran the exact full validator; tests/build passed, but a cold generated-interface snapshot included newly created ignored `_build` interfaces. | Diagnose the validator state transition before changing code. | Useful failure evidence. |
| 40 | Confirmed that only the intended lockfile remained tracked-dirty. | Same narrow scope check. | Real evidence. |
| 41 | Re-ran the exact full validator after caches existed; every functional gate passed, then the validator correctly rejected the intended uncommitted lockfile. | Create an authorized reversible commit, then validate the clean candidate. | Functional proof passed; publication sequence still open. |
| 42 | Repeated repository status and the already-reviewed lockfile diff. | Reuse Prompt 40–41 evidence because repository state had not changed. | No new evidence. |
| 43 | Tried to checkpoint while changing the repair milestone's evidence path. | Keep the durable evidence contract unchanged. | Rejected correctly by the checkpoint validator. |
| 44 | Corrected the checkpoint schema and recorded commit, validation, push, and hosted checks as the next action. | Same correction. | Useful durable state. |
| 45 | Rechecked branch state but diffed the wrong `ui/package-lock.json` path. | Use the retained exact path. | Branch evidence only; path guess added no value. |
| 46 | Re-read the complete correct lockfile diff. | Reuse Prompt 35/40 evidence. | No new evidence. |
| 47 | Selected the exact scoped commit, paused for approval, and committed the one-file repair after approval. | Same authority-aware action. | Real publication work. |
| 48 | Ran exactly `scripts/validate.sh full` from the clean committed state. | Same canonical gate. | Real proof; passed. |
| 49 | Reviewed the committed diff and verified PR identity. | Same proportionate pre-push review. | Useful publication evidence. |
| 50 | Selected the exact branch push, paused for approval, and pushed after approval. | Same authority-aware action. | Real publication work. |
| 51 | Tried to complete the repair milestone while changing its evidence path. | Preserve the checkpoint contract. | Rejected correctly. |
| 52 | Preserved the path, but milestone completion was rejected because the harness forgot mutation evidence recorded before the previous checkpoint. | Carry real mutation evidence across validation and publication checkpoints. | Harness defect; no worker fault. |
| 53 | Watched the new hosted checks and observed failure. | Same once, because hosted state changed after push. | Useful hosted evidence. |
| 54 | Requested both failed-run records; the daemon was interrupted while the calls were in flight. | Same inspection, with durable resumption. | Necessary inspection interrupted by harness repair. |
| 55 | Replayed the interrupted failed-log reads after restart and exposed ignored `_build/**/*.mbti` entries in generated-interface verification. | Same causal log inspection. | Real failure evidence; replay was recovery overhead. |
| 56 | Recorded a schema-correct checkpoint, but its next-action text attributed the failure to registry rewriting rather than the observed interface snapshot. | Preserve the proven build success and follow the exact failing validator stage. | Durable state with an unsupported causal inference. |
| 57 | Repeated status/history and again used the wrong lockfile path. | Move directly to the observed validator implementation. | No new evidence. |
| 58 | Re-read lockfile and registry configuration despite the new failure occurring after production build. | Treat the passed build as retained evidence and inspect only the failing stage. | Drift back to a closed cause. |
| 59 | Replaced the validated lockfile with its parent-commit content through shell redirection. | Do not revert a repair that passed its gate; authored changes must use edit/write/patch. | Harmful drift; teacher stopped the turn and repaired the harness boundary. |
| 60 | Applied teacher steering and read the exact validator. | Restore the mistaken worktree change, then inspect this file. | Useful causal inspection, recovery still open. |
| 61 | Repeated status/diff and inspected ignore behavior; the first form was rejected because the new redirection guard also caught harmless `2>/dev/null`. | Permit descriptor plumbing but continue blocking workspace-file redirection. | Useful evidence plus an over-broad first guard. |
| 62 | Read a small truncated copy of the committed lockfile while preparing restoration. | Read enough exact content for a reviewable edit. | Recovery setup, incomplete. |
| 63 | Re-read the committed lockfile with sufficient output. | Same only because Prompt 62 was truncated. | Necessary recovery data. |
| 64 | Restored all 50 canonical registry entries with the `edit` tool; the worktree again matched the validated commit. | Same reviewable recovery mutation. | Corrected MoonCode's own drift. |
| 65 | Excluded ignored `_build` interfaces from the validator's before snapshot. | Scope generated-interface invariants to source-controlled contracts. | Real causal product work. |
| 66 | Applied the identical exclusion to the after snapshot. | Same symmetric repair. | Real causal product work. |
| 67 | Verified the lockfile was unchanged, reviewed the validator diff, checked whitespace, and compared tracked versus all interface counts. | Same focused proof and scope review. | Real evidence. |
| 68 | Selected one scoped validator commit followed by exactly `scripts/validate.sh full`; after approval, both commit and canonical validation succeeded. | Same clean-state validation sequence. | Real product and proof work. |
| 69 | Reviewed the new commit and confirmed the PR target. | Same proportionate publication review. | Useful evidence. |
| 70 | Recorded the clean local result and push as the next durable action. | Same checkpoint. | Useful durable state. |
| 71 | Selected `git push`, paused for approval, and pushed the validated commit. | Same authority-aware action. | Real publication work. |
| 72 | Recorded the pushed commit and hosted wait as the next action. | Same checkpoint. | Useful durable state. |
| 73 | Read hosted PR status once after the push and found both new checks failed. | Same because hosted state had changed. | Useful gate evidence; exact cause still open. |
| 74 | Queried metadata for both failed hosted runs. | Same focused first inspection. | Useful hosted evidence. |
| 75 | Read both failed-step logs; warning volume hid the decisive tail. | Narrow the next query to the failing step or final lines. | Useful but noisy evidence. |
| 76 | Searched generic error terms and recovered only a non-specific exit code. | Use the known failing step and preserve nearby context. | Little new evidence. |
| 77 | Read the final log section and exposed the exact clean-tree failure: `cmd/main/moon.pkg` and tracked UI build assets changed. | Same causal tail inspection. | Decisive failure evidence. |
| 78 | Reformatted the same log after the changed paths were already known. | Move to the validator and owning files. | No new evidence. |
| 79 | Sliced the same log again. | Use retained Prompt 77 evidence. | No new evidence. |
| 80 | Repeated another presentation of the same hosted output until teacher steering stopped it. | Stop log archaeology once the exact failing paths are known. | Drift; no new evidence. |
| 81 | Read the validator, CI workflow, package manifest, UI scripts, and ignore rules. | Same focused ownership inspection. | Real causal evidence. |
| 82 | Checked history and ownership for the workflow, validator, generated assets, and package manifest. | Same bounded attribution check. | Useful repair-scope evidence. |
| 83 | Added a workflow normalization step that formatted MoonBit and then restored package manifests. | Fix the committed legacy manifest and generated-output behavior at their source; do not hide formatter changes in CI. | Real mutation at the wrong layer. |
| 84 | Changed only a validator comment while leaving behavior unchanged. | Make no change unless it alters the failing behavior or explains a completed repair. | No functional work. |
| 85 | Ran a focused local build and diff; the local host reproduced its own tracked assets, confirming a hosted platform-dependent output difference. | Same causal experiment. | Useful evidence. |
| 86 | Ran the full validator against a knowingly dirty candidate and reached the predictable clean-tree failure. | First isolate generated output, then run the canonical gate from a clean candidate. | Expensive repetition; no certification. |
| 87 | Checked Vite's supported `--outDir` option. | Same minimal capability check. | Useful repair evidence. |
| 88 | Built production UI into a disposable directory with cleanup traps. | Same source-level isolation of generated output. | Real causal product work. |
| 89 | Reviewed and committed the workflow/validator repair. | Commit only after reviewing both the good output isolation and the questionable workflow masking. | Real publication work, with one unresolved wrong-layer change. |
| 90 | Ran exactly `scripts/validate.sh full` from the clean commit and passed locally. | Same canonical local gate. | Real proof. |
| 91 | Verified clean state and pushed after approval. | Same authority-aware publication step. | Real publication work. |
| 92 | Completed the repair milestone and moved to hosted verification using mutation evidence retained across earlier checkpoints. | Same durable transition. | Real live proof that cumulative mutation evidence now works. |
| 93 | Read hosted status once and found both checks failed; also reread already-known workflow context. | Keep the status check, then inspect only the new failing step. | Useful new state mixed with redundant context. |
| 94 | Read the failing log and exposed the exact earlier gate: committed `cmd/main/moon.pkg` uses legacy syntax rejected by `moon fmt --check`. | Update that source manifest, remove the masking workflow workaround, and rerun the canonical gate. | Decisive causal evidence and a clear next repair. |
| 95 | Selected four calls; the first shell pipeline was rejected as exit-ambiguous, the runtime stopped the batch, omitted results for the other three provider calls, and the next model request failed with HTTP 400. | Settle every selected provider call: actual results for the executed prefix and explicit skipped results for the remainder, without recording skipped calls as work. | Harness transcript defect halted the worker. |
| 96 | Began the recovery command by loading the complete MoonBit guide. | Same action because the resumed repair still changes MoonBit-owned files. | Real setup work. |
| 97 | Checkpointed and read the manifest, workflow, module, and branch state; a broad parent-directory search timed out. | Keep the focused reads and avoid searching outside the repository without a concrete target. | Mostly useful orientation; one broad command added no value. |
| 98 | Selected the correct two-file repair, but sent a Codex patch envelope with synthetic path `.` to a unified-diff tool. | Use the tool's documented unified diff or separate reviewable edits. | Correct repair intent; patch-contract defect prevented mutation. |
| 99 | The recovery planner forced an exact read of `.` after that failed mutation. | Recover only from a valid file target, deriving it from unified-diff headers when possible. | No work; failed-mutation recovery defect. |
| 100 | Read the repository's complete agent instructions. | Same action before retrying edits. | Necessary setup. |
| 101 | Edited the package manifest and workflow as separate reviewable file mutations. | Same smallest repair. | Real product work. |
| 102 | Ran local `moon fmt --check`; the old installed compiler rejected current manifest syntax, while the scoped diff review passed. | Treat this as a toolchain mismatch and validate with a disposable current toolchain. | Useful environment evidence, not a product failure. |
| 103 | Inspected Moon version, authentication, remotes, and branch state. | Keep the version check; defer publication/auth checks until local proof is ready. | Mixed: one useful fact and premature publication inspection. |
| 104 | Read the validator and guessed an untargeted `gh pr view`, which failed outside an inferred repository context. | Keep the validator read and use the known repository/PR identity for hosted queries. | Useful local evidence plus a command-shape error. |
| 105 | Proposed a read-only toolchain inspection using a home-directory path rejected by the MoonBook boundary. | Use commands already available on `PATH` or a disposable book-local toolchain. | Partial progress; no execution. |
| 106 | Corrected the read-only installer/help inspection. | Same bounded capability check. | Useful toolchain evidence. |
| 107 | Requested a destructive global toolchain installation. | Keep validation disposable; do not mutate the user's global toolchain. | Rejected correctly; no work. |
| 108 | Proposed a disposable toolchain run without reliable fail-fast and cleanup status. | Add explicit failure propagation and prove cleanup. | Rejected correctly; no work. |
| 109 | Ran the corrected disposable toolchain; format checking passed and cleanup was verified. | Same isolated proof. | Real verification evidence. |
| 110 | Reviewed the scoped diff, branch state, and PR identity. | Same proportionate pre-commit review. | Useful publication evidence. |
| 111 | Committed only the manifest/workflow repair as `faebef38`. | Same scoped commit after review. | Real publication work. |
| 112 | Tried to checkpoint while changing the milestone evidence path. | Preserve the durable checkpoint contract. | Rejected correctly. |
| 113 | Corrected the checkpoint without changing the evidence path. | Same correction. | Real durable progress. |
| 114 | Proposed a clean-worktree validation command that referenced a home-directory toolchain path. | Keep every disposable dependency inside the selected book or available `PATH`. | Rejected at the path boundary. |
| 115 | Re-ran validation with the known-old global compiler. | Use retained Prompt 102 evidence and the current disposable toolchain. | Predictable failure; no new value. |
| 116 | Re-read branch and version state; a duplicate validator read was blocked. | Move directly to a current-toolchain disposable validation. | Mixed, mostly repeated evidence. |
| 117 | Re-read the validator through Git and checked installer behavior again. | Retain the already-read validator and use the known disposable setup. | Mostly redundant. |
| 118 | Repeated the rejected global installation request. | Do not retry a denied authority boundary; use the accepted disposable alternative. | Worker drift; no work. |
| 119 | Repeated the installer fetch used earlier. | Reuse the retained installer evidence. | Rejected duplicate; no work. |
| 120 | Proposed a disposable variant with an unsupported installer flag and a home-directory archive target. | Use supported flags and book-local temporary state. | Rejected correctly. |
| 121 | Ran a properly isolated current toolchain after approval; validation reached an empty disposable registry and failed exactly there. | Seed or update the disposable registry, then resume the same canonical validation. | Useful new causal evidence. |
| 122 | Proposed the same known-failing validation only to tail its log. | Fix the proven missing registry input before rerunning. | Rejected duplicate; no work. |
| 123 | Added disposable `moon update`; native checks and UI tests passed, then the UI build failed because dependencies were absent. | Provision dependencies in the disposable worktree, preserving all prior passing evidence. | Useful next failure, no cause reopening. |
| 124 | Proved `node` and `npm` were already available on `PATH`. | Same narrow elimination check. | Useful environment evidence. |
| 125 | Proposed a no-op variant that changed only the Node path expression. | Add the missing dependency install instead. | Rejected; no work. |
| 126 | Added `npm ci` to the disposable worktree; the exact full validator passed and cleanup was verified. | Same canonical isolated validation. | Real end-to-end proof. |
| 127 | Tried to push to a nonexistent `origin`. | Inspect remotes once, then use the configured publication remote. | Failed command; no state change. |
| 128 | Inspected the configured remotes. | Same recovery step after Prompt 127. | Necessary evidence. |
| 129 | Pushed `faebef38` to the configured GitHub branch. | Same authority-aware publication action. | Real publication work. |
| 130 | Loaded the complete hosted-CI repair skill. | Same applicable skill setup before hosted inspection. | Real setup work. |
| 131 | Verified the PR number, head branch, and exact commit SHA. | Same one-time hosted orientation. | Useful evidence. |
| 132 | Watched hosted checks and observed both pass. | Same live hosted verification. | Real hosted proof, but the generic shell result lacked a typed verification label. |
| 133 | Tried to complete the hosted milestone using that untyped shell result. | Let an explicitly declared hosted check satisfy the typed test milestone. | Checkpoint rejected; verification-typing defect exposed. |
| 134 | Changed the checkpoint evidence path while retrying. | Preserve the checkpoint contract. | Schema error; no work. |
| 135 | Repeated the impossible checkpoint with no new typed evidence. | Repair the generic verification contract before retrying. | No work. |
| 136 | Re-ran the live validator with the known-old local compiler. | Retain the clean disposable result and hosted proof. | Predictable failure; worker drift. |
| 137 | After the harness gained explicit shell verification typing, proposed rerunning the entire full validator. | Re-run only the hosted check invalidated by the intervening failed tool. | Rejected as duplicate work. |
| 138 | Re-ran the hosted PR check with explicit `verification_kind: test`; it passed. | Same smallest proof refresh after the failure boundary. | Real typed hosted evidence. |
| 139 | Completed the hosted milestone using the typed result. | Same durable transition. | Real progress. |
| 140 | Read the preview workflow, phase plan, and hosted workflow state. | Same focused artifact-or-blocker investigation. | Useful evidence. |
| 141 | Queried the nonexistent `origin` remote again. | Use the configured remote retained from Prompt 128. | Command-shape error; no work. |
| 142 | Corrected the hosted workflow and tag queries. | Same recovery. | Useful evidence. |
| 143 | Checked the default branch, retained tag revision, registered hosted workflows, and permissions. | Same exact authority/blocker proof. | Decisive evidence that the artifact workflow cannot run yet. |
| 144 | Tried to complete all milestones, but a later failed tool meant the earlier typed test no longer met the completion gate. | Refresh only the invalidated typed evidence, then preserve the blocker proof. | Correct rejection by the completion gate. |
| 145 | Combined the known-failing local validator and hosted check without fail-fast behavior, so the latter could mask the former. | Never certify from an exit-ambiguous multi-command shell. | Rejected correctly. |
| 146 | Re-ran only the typed hosted PR check; it passed. | Same minimal evidence refresh. | Real hosted proof after the failure boundary. |
| 147 | Ran an explicitly typed, read-only hosted check proving the preview workflow is absent from default, the retained tag, and registered workflows. | Same exact blocker proof because merge/publish authority was outside the task. | Real artifact-blocker evidence. |
| 148 | Completed every in-scope milestone with mutation, local validation, hosted validation, and exact blocker evidence. | Same evidence-gated completion. | Real durable completion of the recovery command. |
| 149 | Called `finish` with the verified result. | Same terminal action. | Accepted completion after 67 tool calls. |

## Harness defects proven by this run

1. **Approval classification used raw substrings.** Quoted evidence triggered
   approval, while nested shells and package-manager global options could bypass
   it. Classification is now executable-aware, understands nested `sh -c`,
   distinguishes help requests, treats command substitution conservatively, and
   does not classify quoted search data as execution.
2. **Approval controls were queued before target validation.** Invalid
   approve/reject commands are now validated before any durable queue write.
3. **The planner asked for approval through `finish`.** The planner and tool
   descriptions now instruct the model to select the exact gated tool and let
   the runtime pause. No model-step ceiling was added.
4. **Timeouts lost evidence and leaked descendant work.** Shell timeout results
   now preserve capped stdout/stderr. An outer shell wrapper TERM-signals the
   descendant tree, waits for it, and lets cleanup traps run before hard
   cancellation.
5. **Read-only inline interpreters were blocked by a syntactic policy.** The
   blanket block was removed. The planner still requires authored mutations to
   use reviewable edit/write/patch tools.
6. **Skills were not comparable.** The global MoonCode catalog now includes the
   relevant general and MoonBit skills used in this evaluation. Applicable
   skills are loaded through complete `read_skill` progressive disclosure
   before task work.
7. **Mutation evidence expired at every checkpoint.** Completing a mutation
   milestone after validation and publication wrongly demanded a second edit.
   Mutation evidence is now cumulative across the task and consumed only by
   already-completed mutation milestones.
8. **The shell could author workspace files despite the planner rule.** Shell
   output redirection to a file is now rejected before execution and directs
   the model to `write`, `edit`, or `apply_patch`. Descriptor plumbing and
   `/dev/null` remain available for read-only diagnostics.
9. **The planner reopened causes after their gate passed.** Its general evidence
   guidance now says that repository/hosted reads remain valid until state
   changes, and that a later failure at another gate does not invalidate an
   earlier passing repair without direct contrary evidence.
10. **An early batch stop left provider calls unresolved.** The model transcript
    now receives an explicit skipped result for every unexecuted remainder of a
    selected batch. Those synthetic results are transcript-only, never durable
    executions or completion evidence, and tell the planner to select a call
    again only if it remains necessary.
11. **Multi-file patch syntax failed at the wrong boundary.** The patch tool now
    parses standard unified diffs before resolving a target path, infers real
    paths from diff headers, documents that `path` may be omitted, and rejects
    unsupported Codex patch envelopes with an actionable message before trying
    to read a synthetic directory target.
12. **Failed mutation recovery forced directory reads.** Exact-read recovery now
    accepts only file-shaped targets and derives a target from unified-diff
    headers where possible. A failed patch addressed to `.` no longer creates a
    second guaranteed failure.
13. **Hosted shell verification was untyped.** The shell tool now accepts an
    explicit `verification_kind` of `check`, `test`, or `build`. Only an accepted
    shell result with that declared kind contributes typed completion evidence;
    ordinary shell success still cannot silently certify coding completion.
14. **Terminal receipts replayed the whole execution.** One successful
    long-horizon turn wrote a 33.6 MB receipt and regrew its journal to 78.5 MB.
    Durable terminal receipts now retain the completion verdict and `finish`
    result needed for conversation projection, while omitting already-journaled
    tool payloads and events.

## Independent observer verdict

A separate read-only observer reviewed the current scoped diff, all 149 prompt
rows, the target commit, and the hosted evidence. Its verdict was **ACCEPT**:
no actionable defect, product-specific hardcoding, or material overclaim was
found. It independently reran the 188 daemon tests, 7 process-spawn tests, and
scoped diff check; all passed. The final full native suite passed 1,192 tests.

The observer also confirmed that explicit horizons are milestone-driven without
a command-wide step ceiling, and that continuation, recovery, checkpoints, and
completion gating live in the native worker. The temporary teacher can therefore
be removed later without moving those behaviors outside MoonCode; external
authority decisions and independent acceptance remain deliberately external.

## Independence boundary

The teacher harness remains temporary. The durable task contract, skill
selection, checkpoints, patient continuation, failed-tool recovery, exact
approval tool selection, and evidence-gated completion belong in MoonCode.
Later removal of the teacher must leave those behaviors in the worker; only
external authority decisions and independent result review stay outside it.
