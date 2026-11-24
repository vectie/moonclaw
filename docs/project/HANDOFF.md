# Runtime handoff

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
