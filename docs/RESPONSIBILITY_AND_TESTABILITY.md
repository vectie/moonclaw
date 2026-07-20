# MoonClaw Responsibility and Testability

MoonClaw is MoonSuite's generic agent execution runtime. It owns bounded model
turns, tools, approvals, durable execution evidence, cancellation, recovery,
and generic job/session state. It does not own a product's business policy,
domain workflow, output schema, or acceptance meaning.

## Ownership rule

The runtime may execute a pack request only when the request identifies its
product and carries either:

- a `contract_policy` whose `owner_product` exactly matches `product_id`; or
- the temporary, explicit legacy compatibility declaration with a matching
  `contract_policy_owner`.

The pack-owned policy may declare guidance, required non-empty output fields,
and required governed-tool provenance. MoonClaw checks those generic
declarations and records execution evidence. It cannot invent or weaken them.
MoonClaw's own software-result contract is the only product contract it owns.

Legacy compatibility is quarantined in `cmd/main/flow_adapter`. It exists only
to replay older cross-product runs while their callers migrate to pack-owned
adapters. New integrations must not add another product branch there.

## Removed product lanes

MoonClaw no longer ships:

- a built-in robotics job profile, planner, CLI, gateway endpoint, or run
  ledger;
- implicit post-run memory calls to another product; or
- a MoonMold-specific client/provider package.

Robotics policy and route construction belong to the MoonRobo pack and are
scheduled by MoonFlow. MoonMold owns its MCP/provider implementation and pack
manifest. MoonClaw sees both only as declared capabilities with explicit
authority.

The former MoonWiki-specific native host label is now a generic `book.host`
boundary. MoonBook and MoonDesk names remain in the native MoonCode protocol
only where they describe legitimate artifact and UI ownership: MoonClaw
executes, MoonBook stores accepted executable artifacts, and MoonDesk
renders/reviews them. Those ownership labels do not grant either product's
domain policy to MoonClaw.

## Authority boundary

- `observe` may enable declared read-only network tools.
- Workspace mutation is limited to the selected run or MoonBook root.
- External publication, credentials, broker actions, and physical effects are
  never implied by an agent/job request.
- Product acceptance requires a separate review receipt; successful execution
  is not acceptance.
- A pack policy mismatch fails before model execution, preventing unowned work
  and avoidable provider cost.

## Focused verification

The proportional validation pass for this refactor is:

```sh
moon check --target native
moon test cmd/main/flow_adapter/flow_adapter_wbtest.mbt --target native
moon test mooncode/core/protocol_wbtest.mbt --target native
moon info
moon fmt
```

The repository still has pre-existing warning debt, mostly in the vendored
async dependency, so warning cleanup is tracked separately from this boundary
change.

Relevant tests prove that external work is rejected without a matching
pack-owned policy, declared tool provenance must succeed, configured job
profiles remain loadable, and removed built-in product routes are absent from
the gateway. Full provider/live-network exercises are integration tests owned
by the calling pack, not by MoonClaw core.

## Remaining migration

The consolidated Flow adapter still contains explicitly gated legacy validators
for older MoonSuite products. They are not the extension mechanism. Each owner
should finish moving its schema and detailed validator into its own adapter;
after all installed declarations carry `contract_policy`, the compatibility
branches and flag can be deleted without changing MoonClaw's generic runtime.
