# Daemon And Gateway

These are service entry points into the existing runtime, not two layers of
agents or a required Router/Worker topology.

## Choose An Entry Point

| Need | Entry point |
| --- | --- |
| Native MoonCode sessions, canonical conversation, tool controls, and runtime-service execution | Daemon `/v1/code/*` |
| Existing local task/process supervision and task API | Daemon `/v1/task*` |
| Gateway HTTP/JSON-RPC, agent events, channels, extensions, mailboxes, coordination, and pipelines | Gateway |
| Product-owned automation or domain actions | The installed pack/capability boundary, using the appropriate host |

The daemon is not merely an older supervisor. It owns the native coding
session path used by desktop clients. Gateway channel/orchestration facilities
remain optional and do not become mandatory stages of MoonCode execution.

## Ownership

Both entry points compose runtime capabilities. Neither owns accepted book
truth or another product's domain policy. A client cannot substitute generic
task chat for the native MoonCode conversation protocol.

Native session journal, lease, approval, and restart semantics are documented
in [Executable book runtime boundary](executable_book_runtime_boundary.md).
Detailed endpoints remain in the [daemon reference](../cmd/daemon/README.md)
and [gateway reference](../cmd/gateway/README.md).

## Operational Notes

Gateway's default port is `18123`. Its CLI does not provide a built-in
`status` subcommand or detach/background flag. Channel setup and long-lived
connections belong to the configured gateway service lifecycle.

Do not infer persistence or replay guarantees for gateway mailboxes from the
durable native MoonCode journal. Check each API's implementation and contract.
