# Session source and workspace trust

MoonClaw persists two closed provenance fields instead of inferring authority
from UI route names or free-form metadata:

- `source_kind`: `user`, `moondesk.general`, `mooncode`, `worker`,
  `validation`, `memory_consolidation`, or `safety_review`;
- `workspace_trust`: `unknown`, `untrusted`, or `trusted`.

General MoonDesk chat submits `source_kind=moondesk.general` and
`workspace_trust=unknown`. MoonCode's selected-MoonBook sessions persist
`source_kind=mooncode` and `workspace_trust=trusted` in snapshots and listing
records; legacy MoonCode snapshots receive those same conservative product
defaults when read. Worker and validation callers must identify themselves
explicitly rather than borrowing the user source.

Project rules and workspace skills are loaded only for trusted general-agent
conversations. Source is routing/provenance evidence, not authorization:
neither `source_kind` nor `workspace_trust` can mint a sandbox grant, approve a
tool, bypass Guardian qualification, or weaken MoonFort enforcement.
