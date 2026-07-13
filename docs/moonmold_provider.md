# MoonMold provider

MoonClaw controls MoonMold through an MCP/JSON-RPC stdio process, never through
a sibling-source import. The provider command comes from the trusted MoonClaw
provider registry. It is executed as argv without a shell.

The handshake must expose exactly two closed-schema tools:

- `moonmold_semantic_operation`
- `moonmold_live_building`

MoonClaw records provider, tool, request and idempotency identity, outcome,
duration, structured MoonMold receipt, evidence class, and the fixed
`physicalEffects:false` boundary. Capability discovery exposes the actual
Blender runtime and initial scene digest.

Requests have per-call deadlines and cancellation signals. Timeout or
cancellation sends an MCP cancellation notification; the MoonMold worker
terminates its bounded Blender child. Closing the provider rejects pending
work and terminates the process.

Unknown/open schemas, extra tools, script/eval/shell/code fields, physical
authority, and malformed receipts fail closed. The agent never supplies Python:
MoonMold alone selects its audited fixed bridge.

## Qualification ledger

Input: configured MCP command, semantic capability request, and an explicit
workspace-local image-referenced building plan.

Output: exact tool catalog, semantic receipt, and real Blender evidence receipt
containing `.blend`, GLB, STL, render, and bridge-manifest hashes.

Quality: actual process boundary, no shell, no runtime source import, timeout,
cooperative cancellation, script rejection, attributable receipt, and no
physical effects.

