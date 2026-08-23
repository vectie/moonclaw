# MoonFort executor integration prototype

This prototype removes the `execute_command` tool's direct
`sh -c <agent-input>` host process. The only process it can start is an
operator-configured, canonical absolute MoonFort executor path with fixed
operator-controlled arguments. Missing configuration, malformed protocol
output, refusal, insufficient enforcement, and receipt mismatch all fail
closed without a shell retry.

`SandboxExecutorConfig` is injected into `@execute_command.new`. It names the
executor, its trusted configuration registry, the pending-grant and receipt
roots, and opaque workspace/backend configuration IDs. Workspace roots, local
tool paths, AEN credentials, scratch roots, and maximum limits remain solely in
the executor-owned registry selected by `MOONFORT_EXECUTOR_CONFIG`. Legacy
command text is encoded as MoonFort's explicit `Shell` command and requires the
`shell-compat` capability.

For high-risk commands MoonClaw constructs the exact v2 execution grant before
requesting human approval. The security journal persists:

- the exact grant and its canonical SHA-256 approval digest;
- the exact shell command, including a confined relative working directory;
- opaque trusted-registry IDs and requested limits; and
- a digest binding the executor path, fixed arguments, registry path, and grant
  publication roots.

Approval consumption returns this immutable context atomically. A daemon
restart therefore cannot replace the approved grant, and an operator
configuration change invalidates the approval. Only after human approval is
consumed does MoonClaw send the typed grant to the fixed MoonFort publisher.
The publisher revalidates it against executor-owned registries and atomically
publishes the mode-0600 single-use record; MoonClaw has no approval-directory
write access. It then invokes the executor with only
`{ "protocol_version": 2, "approval_id": "..." }` on
standard input. MoonFort atomically moves that grant from `pending` to
`consumed`, resolves all trusted resources from its registry, and returns a
receipt binding both the approval digest and the command digest. MoonClaw
checks the approved run, backend, digest, enforcement level, and canonical
digests, then atomically persists the receipt outside the canonical workspace.

The prototype deliberately leaves `sandbox_config` optional at API call sites.
Omitting it disables execution rather than selecting a host fallback. Before
production deployment, MoonClaw's composition roots need a typed config source
for the registry and capability IDs. The operator must also define grant TTL
and crash recovery, consumed-grant/scratch/receipt retention, executor binary
authentication/update policy, and the UI flow for reviewing and promoting
MoonFort artifacts and diffs.

The publisher is a narrow trust boundary. Its path and arguments are fixed
operator configuration, its stdin is bounded, and MoonClaw requires the exact
approval ID and digest in its response before invoking the executor.

## Reviewed promotion outcomes

MoonDesk may request exactly one reviewed retained regular file per promotion
using MoonFort's promotion-only protocol v4 (the execution protocol remains
v3).
MoonFort requires that file's canonical destination parent directory to exist;
neither MoonClaw nor MoonDesk creates it as part of promotion. The fixed
promotion adapter returns a typed destination outcome which MoonClaw validates
as a closed state matrix before projecting it to MoonDesk:

- `applied-durable` names the exact reviewed destination in `promoted_paths`.
  `completed=false` with `promotion-cleanup-unverified` still means the
  canonical mutation occurred and must never be presented as a safe retry.
- `not-applied` has no promoted or uncertain paths. An accompanying
  `promotion-recovery-required` means the destination is proven unchanged but
  the durable retention claim remains locked for operator recovery.
- `recovery-required` has no promoted paths and names the exact single reviewed
  destination in `uncertain_paths`; its canonical mutation outcome is unknown.

MoonClaw returns every validated outcome as a trusted response body, including
the bounded error code and a `recovery_required` flag. Provider diagnostic
messages, native status values, executor paths, and host paths are never
forwarded. Malformed or contradictory adapter output still fails closed as a
generic service refusal.

## Full-output artifact capability

MoonClaw v3 receipts accept an optional signed `output_artifact` object. The
artifact ID is opaque and is never joined to a host or scratch path. MoonClaw
accepts the reference only when its run binding, SHA-256 digest, byte size,
UTF-8 media type, expiry, key ID, and HMAC signature shapes are valid and its
size stays within the approved output ceiling. A truncated terminal receipt
without the reference fails closed; small complete output remains inline and
may omit it.

MoonClaw exposes only bounded inline output and non-secret artifact metadata.
It does not expose the raw receipt or audit path and it does not implement a
second artifact reader. Retrieval remains a MoonFort authority: a fixed,
reviewed reader must revalidate the signed reference, run/approval/command
binding, manifest, expiry, path/type/size, digest, and symlink protections
before returning retained bytes.
