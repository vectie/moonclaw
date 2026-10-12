# Live Fort command output

Analysis jobs now retain a trusted run/step-to-Fort request and approval link after command approval validation and before invocation. The Artifacts panel discovers these commands while they run. Choose **Tail live output**, then **Pause tail**, **Resume tail**, **Reload from cursor**, or **Close live output**. Pausing/closing a viewer never cancels or reruns a command.

## Operator setup

Set `MOONCLAW_MOONFORT_CONFIG` to the canonical operator-owned sandbox JSON file. Configure its `live_output_reader_path` to the trusted native `moonfort/cmd/read-live-output` executable (and `live_output_reader_args` only when your trusted launcher needs them). The configured `executor_config_path`, reader arguments and `receipt_root` remain server-owned. The gateway and analysis executor must use the same operator configuration and receipt root. Changes to that configuration invalidate previous live bindings instead of silently routing them elsewhere. `command_output_reader_path` remains the independent complete-output reader.

No deployment configuration, provider credentials, approval IDs, signing references, filesystem paths, or signing keys are accepted from the browser. This feature does not weaken approval requirements or provide a host-shell fallback. Old runs without a pre-dispatch live binding are unavailable for live viewing; they are not reconstructed. Existing verified terminal downloads retain their original path and verification.

## Read-only gateway contract

The existing bearer-authenticated gateway exposes:

`GET /v1/jobs/runs/{run}/command-outputs/{output}/live/{cursor}`

The first cursor is `start`; subsequent requests use exactly `next_cursor` from the previous accepted response. Only run ID, bound output ID and cursor are supplied. Cursor replay is safe. The server resolves the immutable ownership record and trusted reader itself, pins the first validated stream ID durably, and refuses cross-run/step/approval or changed-stream mappings. A freshly restarted gateway can resume from the same persisted records and cursor.

Responses contain a bounded base64 chunk and numerical byte offsets, public run/output/step identity, stream state and the next cursor. Protocol version, identity, canonical base64, decoded byte length, exact offset, stream identity, output ceiling and terminal consistency are checked before returning bytes. The native reader timeout is two seconds and its transport output is capped at 96 KiB. Each read returns at most 64 KiB and live viewing supports retained streams up to 64 MiB; the configured approved output ceiling can be smaller. Claw stores only ownership and stream identity, never a second spool.

## Display and lifecycle

The UI displays escaped text with at most 65,536 UTF-16 code units retained, carries up to three incomplete UTF-8 bytes between reads, escapes control bytes and marks replacement-decoded binary content. Truncation is explicit. Cursor and partial UTF-8 carry are retained in this tab's session storage, scoped to gateway/run/output; reload resumes without copying earlier output text. No gateway token or full output is saved there.

Responses arriving after pause, close, navigation, gateway/token change, reload or a newer request generation cannot append text. A disconnect pauses the viewer at its last accepted cursor. Empty reads mean waiting. A Fort terminal stream flag only stops tailing; it never marks a job successful. Terminal refresh preserves Run, RunCanvas and Cowork context. The separate verified receipt/run snapshot controls job status and complete-output download availability. Exact binary output remains available only through the verified terminal download, subject to retention and the approved output ceiling.

## Focused verification

- `moon test internal/execution_sandbox/command_live_output_wbtest.mbt --target native --strip -j 1 --frozen`
- `moon test job/analysis_live_output_wbtest.mbt --target native --strip -j 1 --frozen`
- In `ui/rabbita-job`: `moon test main/command_live_output_wbtest.mbt main/command_output_wbtest.mbt --target js --frozen`
- Native integration tests are deliberately skipped by ordinary suites. Explicitly run `gateway/server/command_live_output_wbtest.mbt --index 0` with `MOONFORT_R27_LIVE_READER` pointing to the unchanged native reader, and the shipped UI freshly built with `npm run build`
- Explicitly run the pre-existing `gateway/server/command_output_wbtest.mbt --index 0` with its original `MOONFORT_R13_FIXTURE_ROOT` and `MOONFORT_R13_READER` fixture contract to recheck verified terminal binary download through the same shipped UI

The live integration uses synthetic signed spool records, an actual unchanged native Fort reader, real authenticated HTTP and shipped UI decoder/state/rendering. It appends bytes after the first preterminal read, including split UTF-8 and binary bytes, and tests cursor replay/reload, cancellation, independent terminal status, restart, missing spool, expiry and cross-run rejection. It does not execute an unsafe OS command, make a provider request or claim hardware/sandbox enforcement validation.
