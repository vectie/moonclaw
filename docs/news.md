# News

Recent feature additions are tracked here by day so operators can quickly see
what changed.

## 2026-03-24

- merged `opc`, `weixin`, and `canvas` into `main`
- added a Weixin Official Account channel:
  - `/webhook/weixin` handshake verification
  - plaintext text-message intake
  - outbound custom-service replies
- added generic delegated worker routing for OPC-style jobs
- added ACP routing for analysis steps, so controller/local analysis can use the
  same remote Codex path as delegated workers
- added workspace-local OPC example packs:
  - `docs/examples/opc_moonclaw.jobs.json`
  - `docs/examples/opc_skills/`
  - `docs/examples/opc_job_test_guide.md`
- upgraded the Rabbita controller canvas:
  - split / merge nodes
  - horizontal company lanes
  - company health strip
  - lane sequence and handoff cards
- made the company board more general:
  - `board_lane` metadata can name a lane explicitly
  - `board_order` metadata can order lanes explicitly
  - UI falls back to heuristics only when lane metadata is absent
- removed the hardcoded generic 3-step fallback plan
  - generic fallback is now a single minimal `execute` step

## 2026-03-23

- added generic delegated worker routing metadata:
  - `child_profile`
  - `execution_mode`
  - `execution_target`
- routed delegated worker analysis jobs through ACP when configured
- routed analysis steps through ACP as well, so local/controller analysis can
  avoid the direct failing Codex OAuth path

## 2026-03-20

- improved proposal ids and run ids to be human-readable and time-prefixed
- moved run workspaces under the visible workspace root:
  - `<workspace>/moonclaw-jobs/<run-id>`
  - `<parent>/moonclaw-subjobs/<run-id>`
- removed automatic copying of workspace markdown into run workspaces
- fixed job time display to use the correct local date/time
- improved Feishu progress UX for streaming / typing feedback
- added a current job routine reference document

## 2026-03-19

- added a research job example and test guide
- made controller policy more declarative and JSON-driven
- implemented a generic controller job foundation for iterative jobs

## 2026-03-17

- added `acp add codex`
- fixed MoonClaw home defaults to `~/.moonclaw`
- fixed ACP repeated-run argument accumulation
- documented ACP Codex path troubleshooting
