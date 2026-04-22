# Bootstrap Packet: README.mbt lane 1

## Short summary

MoonClaw appears to be a MoonBit-native agent runtime and job execution system oriented around durable run workspaces, gateway-driven operation, controller-style JSON job profiles, ACP remote-agent control, and wiki-shaped workspace support. The inspected materials also show a strong architectural boundary: MoonBit runtime code should stay generic, while controller policy and domain behavior should live in JSON profiles and AI outputs.

## Evidence

- `README.mbt.md`: `/Users/kq/Workspace/moonclaw/README.mbt.md` describes MoonClaw as a "MoonBit-native agent runtime + gateway + memory + job system + ACP remote-agent control" and says the system is shaped around a full job runtime rather than a thin chat wrapper.
- `README.mbt.md`: `/Users/kq/Workspace/moonclaw/README.mbt.md` lists core user-facing capabilities including local execution, async orchestration, durable outputs, operator control, ACP targets, Rabbita UI, memory capture, artifact storage, and per-run workspaces.
- `README.mbt.md`: `/Users/kq/Workspace/moonclaw/README.mbt.md` names major subsystems as `agent`, `gateway`, `job`, `workspace`, `security`, `acp`, and `ui/rabbita-job`, which is useful source material for durable subsystem pages.
- `README.mbt.md`: `/Users/kq/Workspace/moonclaw/README.mbt.md` documents wiki-maintainer support, including automatic detection of wiki-shaped workspaces when `raw/`, `wiki/`, `wiki/index.md`, and `wiki/log.md` are present.
- `README.mbt.md`: `/Users/kq/Workspace/moonclaw/README.mbt.md` records recent changes showing provider-backed adaptive phases such as `bootstrap_gather` and `source_materialize`, plus external proposal packet import and reusable provider/extension execution boundaries.
- `docs/research_controller_architecture.md`: `/Users/kq/Workspace/moonclaw/docs/research_controller_architecture.md` states the runtime should load JSON job profiles, compile proposals into workflows, persist controller state/lineage/artifacts, and execute child jobs, while avoiding hardcoded research-specific controller semantics.
- `docs/research_controller_architecture.md`: `/Users/kq/Workspace/moonclaw/docs/research_controller_architecture.md` defines the architectural split as code owning generic execution and persistence, JSON owning profile shape and controller policy, and AI owning contentful reasoning within allowed policy.
- `moon.mod.json`: `/Users/kq/Workspace/moonclaw/moon.mod.json` identifies the module as `vectie/moonclaw`, version `0.1.2`, repository `https://github.com/vectie/moonclaw`, and preferred target `native`.
- `Agents.md`: `/Users/kq/Workspace/moonclaw/Agents.md` confirms this is a MoonBit project and describes package-level structure, block-style MoonBit organization, and standard tooling such as `moon info`, `moon fmt`, `moon test`, and `moon check`.

## Candidate durable source pages

- `wiki/sources/moonclaw-readme-overview.md` - source page for the product overview, subsystem list, operator UX, onboarding, and wiki-maintainer notes drawn from `/Users/kq/Workspace/moonclaw/README.mbt.md`.
- `wiki/sources/controller-profile-architecture.md` - source page for the controller/profile architecture boundary and declarative policy model drawn from `/Users/kq/Workspace/moonclaw/docs/research_controller_architecture.md`.
- `wiki/sources/moonclaw-module-metadata.md` - source page for module identity, version, repository, and dependency metadata from `/Users/kq/Workspace/moonclaw/moon.mod.json`.
- `wiki/sources/moonbit-project-conventions.md` - source page for repository-specific MoonBit structure and tooling guidance from `/Users/kq/Workspace/moonclaw/Agents.md`.

## Additional candidate durable pages

- `wiki/entities/moonclaw.md` - entity page for the project as a whole, covering runtime, gateway, jobs, ACP, memory, artifacts, and operator UI.
- `wiki/entities/rabbita-operator-ui.md` - entity page for the Rabbita UI surface and its role in local plus remote execution visibility.
- `wiki/concepts/controller-profile-architecture.md` - concept page for the split between generic runtime mechanics, JSON-defined policy, and AI reasoning.
- `wiki/concepts/wiki-shaped-workspace.md` - concept page for the required workspace markers (`raw/`, `wiki/`, `wiki/index.md`, `wiki/log.md`) and how MoonClaw uses them.
- `wiki/synthesis/moonclaw-product-boundary.md` - synthesis page connecting README claims with the controller architecture note to explain what MoonClaw core should own versus what extension packs should own.

## Blockers and open gaps

- The slice is limited to four files, so evidence is high-signal but incomplete for implementation details, current directory layout, and whether named subsystems map directly to current source packages.
- The workspace currently has `raw/bootstrap/`, but no `wiki/` directory was present during inspection, so candidate durable page paths are proposals only and not claims about existing wiki coverage.
- `README.mbt.md` points to additional example profiles and guides under `docs/examples/`, but those files were intentionally not inspected in this bounded slice.
- `moon.mod.json` points `readme` to `README.md`, while the inspected high-signal overview is `README.mbt.md`; that mismatch may matter for future durable sourcing and should be reconciled later.
