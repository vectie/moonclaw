# External Proposal Packets

MoonClaw can ingest externally generated proposal packets without teaching the external system how MoonClaw stores proposals, workflows, or runs.

The boundary is intentionally thin:

- the external producer writes a packet JSON file
- MoonClaw validates it
- MoonClaw converts it into a normal draft proposal
- the usual confirm and run lifecycle takes over

## CLI

Import a packet as a draft proposal:

```bash
moon run cmd/main -- proposal import keeper/jobs/ingest-001.json --home ~/.moonclaw
```

Gateway-path alias:

```bash
moon run cmd/main -- gateway proposal import keeper/jobs/ingest-001.json --home ~/.moonclaw
```

Import, confirm, and execute immediately:

```bash
moon run cmd/main -- proposal import keeper/jobs/ingest-001.json --home ~/.moonclaw --confirm
```

Use `--json` when another tool needs structured output.

## Packet Contract

Required fields:

- `profile`
- `context_pages` as a non-empty string array
- `skill_paths` as a non-empty string array
- `output_contract` as a non-blank string, non-empty string array, or non-empty object
- one of:
  - `request_text`
  - `request`
  - `goal`
  - `objective`
  - `title`

Optional fields:

- `packet_id`
- `title`
- `summary`
- `output_contract`
- `context_pages`
- `skill_paths`
- `notes`
- `tags`
- `metadata`

Example:

```json
{
  "packet_id": "keeper-20260413-001",
  "title": "Ingest source into wiki",
  "summary": "Review the new source, update the relevant wiki pages, then summarize the revision.",
  "request_text": "Ingest the new source into the wiki and revise the relevant pages.",
  "profile": "wiki_ingest_controller",
  "output_contract": {
    "artifact": "wiki/report.md"
  },
  "context_pages": [
    "wiki/index.md",
    "wiki/log.md"
  ],
  "skill_paths": [
    "skills/wiki-maintainer/SKILL.md"
  ],
  "notes": [
    "Prefer concise citations."
  ],
  "metadata": {
    "producer": "keeper"
  }
}
```

## Runtime Behavior

On import, MoonClaw:

- requires the packet `profile` to exist in `moonclaw.jobs.json`
- creates a normal draft proposal with a human-readable proposal id
- stamps packet data into `proposal.profile_metadata.external_packet`
- stores packet data into `proposal.profile_metadata.job_intake`
- applies the named MoonClaw job profile
- merges packet context into each proposal step's metadata
- stores the proposal in the same proposal store used by chat-originated `/plan-job`

If `--confirm` is passed, MoonClaw then:

- compiles the imported proposal
- creates a real run
- executes it through the standard workflow engine

During execution, the imported packet becomes visible through the normal proposal path:

- `initial_input` contains the packet-derived intake
- analysis prompts include that `initial_input`
- step metadata includes `context_pages`, `skill_paths`, derived `preferred_skills`, notes, and output contract details

This keeps the contract stable:

- external systems own packet generation
- MoonClaw owns proposal persistence, confirmation, and execution
