# Runtime handoff

## ACP live text / session reuse — 2026-11-25

Cluster runtime is now **0.1.7-acp.5**, not the historical acp.4 below. MoonGate
resumes the same waiting ACP/MCP tool chain using actual caller tool results.
MoonClaw still owns Book scope, execution and approvals. Its ACP/text-chat
model branch now forwards live text into the canonical assistant_delta journal
lane, coalesced over 75 ms. The final planner progress event skips duplicate
full text after live delivery. No second projection or UI state machine added.

Clean daemon tests 500/500, focused streaming-before-completion test and existing
planner duplicate-text regression pass. Release minOS 15.0 and strict installed
signatures verified. MoonGate's handoff has rollback paths and detailed timing.
User declined native remote-desktop access; installed resources/backend were
tested UI-to-UI over SSH, not by controlling the remote WKWebView.

Actual Argon session mooncode-1ac4196059a8aff7 wrote/ran latency_hello.py with
exit 0/Hello, World!, one ACP process across write/run/final reply. A separate
long reply first appeared in UI at 9,866 ms while Running and incomplete, then
finished at 19,889 ms backend time without reload. No promise that all models
or longer tasks complete in 20 seconds. Google authentication and sandbox
permissions were unchanged. Unrelated Book/MoonFish/OpenAI changes excluded.

## ACP coding deployed on cluster Mac — 2026-11-24

The user approved MoonFort LocalOs / AllowDegraded for ACP Coding Demo only,
then requested practical defaults. Installed MoonDesk now bundles and runs
**0.1.7-acp.4**, built from a clean export excluding unrelated Book-runtime and
OpenAI changes. MoonGate's HANDOFF contains private deployment/rollback paths.

Actual MoonDesk UI session mooncode-533681c58dd271fe (Argon) saved
acp_smoke.mbtx and verified 42 / exit 0 for ordinary and native runs.
Final command 9d8e519d9a835ce6 used plain moon_cmd run --target native, with
no environment overrides. Its UI receipt shows Degraded / cleanup verified.
No Enforced or VM-grade claim; degraded artifact promotion remains disabled.

acp_tools retains real tool schemas/history while omitting unsupported
generation controls/cache hints. The bridge's MCP relay captures OpenAI tool
calls, never executes or fabricates results. Normal caller validation/approvals
remain. There is fresh ACP process startup per tool round; do not promise low
latency. Model JSON defaults acp_tools=false.

Operator config loading accepts an optional workspace root. MoonCode always
passes its canonical Book root; it must match the executor-owned workspace
registry before grant publication. A global workspace_id must not redirect
another Book's commands into the demo. Existing fixture overrides stay test-only.

The public receipt projection needs flat approved network/limits fields,
string/null retention_id (not a bare Option array), and no file-content hash for
the executor's directory sentinel. Full execution evidence remains private and
validation remains intact. Before these corrections, successful commands showed
an invalid-receipt warning in MoonDesk.

Clean validation: 499 daemon tests, 44 strict model/adapter tests, 3 strict
operator-config tests. Info/fmt and whitespace checks completed. Existing
daemon warning debt prevents --deny-warn for the broad daemon package.
@mock.run requires executables physically below the source root in a single
build-directory component; external --target-dir and symlinks fail its path
guard. Current clean build: /tmp/moonclaw-acp-compat.p0QWSY/_build.
Source changes for this deployment are uncommitted; earlier text-only changes
were already pushed. Preserve the user's unrelated MoonFish/Book-runtime work.

## Explicit MoonGate ACP text-chat transport — 2026-11-24

`MoonGateModel.text_only()` reads the explicit `moongate.text_only` catalog
flag and carries it into `Model.text_only` (default false, JSON round-trips).
Only this mode sends minimal text Chat Completions without tools, generation
controls or cache hints, and uses a text-chat system prompt instead of the
coding planner prompt. Tool histories fail rather than losing tool results.
The existing assistant-content -> finish completion path is reused. This does
not implement coding tools or token-budget enforcement, and no API request is
retried with fields stripped. Normal providers keep their previous behavior.

Cluster Mac macOS 15.7.3 qualification used a clean HEAD export plus only these
changes, minOS 15.0, in MoonDesk's disposable app-data runtime (not the installed
bundle). Two Neon turns in the same MoonDesk UI conversation succeeded through
MoonGate and official Google Antigravity ACP 1.5.16. Google AI Pro remaining
quota decreased during the first turn + provider-check batch, credits OFF,
API-key/ADC env unset. MoonGate's handoff has the request IDs and percentages.
Quota in an already-open CLI was stale; a fresh official CLI showed the debit.
Do not claim native remote-window automation, all-model qualification, or zero
token usage from missing ACP usage metadata.

Daemon/model/MoonGate adapter tests: 541 pass serially. An existing pending
approval timing test failed under concurrent build/test load but passed alone
and in the serial rerun. Model JSON snapshots add `text_only: false` by default.
Generated interfaces add the explicit capability; unrelated dirty runtime and
MCP changes were excluded from the tested clean build. Existing repository
warnings still prevent broad deny-warn checks.
The two unused MoonGate adapter test imports were removed; adapter and Model
checks now pass deny-warn, and all 13 adapter tests pass strictly. Only existing
daemon/test warnings remain in the broader focused deny-warn invocation.

## MoonBook MCP research — 2026-11-11

Changes in `internal/book_runtime` were implemented for the live MoonFish
NAS-only research workflow, not a synthetic task. No automated tests were run;
native builds, interface generation/formatting and deployment readiness are
separate from MoonFish native desktop business acceptance.

- A request for two saved query rows with full metadata returned about15MB
  because the upstream metadata included the entire snapshot's input rows.
  The owning MoonFish query projection now keeps raw rows behind its explicit
  source-record flag; do not treat a row limit as a complete response-size bound.
- Agent `mcp_list_tools` without a server now returns an integration index.
  Select one server to fetch actual schemas. This avoids injecting every enabled
  integration's full schema catalog into each research context. The lower-level
  `call_mcp` result contract used by MoonCode remains unchanged.
- Per-server MCP initialization/call now shares a 60 second deadline, returning an
  explicit failure rather than indefinitely occupying a research task. This is
  not a successful tool result and must not be converted into fabricated data.
- Preserve source tokens internally and redact them from returned failures.
  The integration index exposes names/IDs only, never tokens.

Installed deployment receipt in the MoonFish workspace:
`outputs/real-sources/moonclaw-mcp-bounded-20261111.json`.
The first readiness observation after restart was too early; deployment now uses
a short bounded retry. Existing conversations and failures remain intact.
