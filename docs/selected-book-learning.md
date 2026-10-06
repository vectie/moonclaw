# Selected Book learning in native supervisor input

The native supervisor captures accepted procedure and belief records from its
already authorized selected Book. Selection is the existing symbolic
`workspace_id`/`book_id` task metadata (including `workspaceId`/`bookId` aliases),
with the governed `task.cwd` as source. It does not discover a Book executable,
initialize a Book, invoke a provider, install a capability, or alter authority.
The private worker execution directory and model-resolution directory remain
separate from the source binding.

## Source contract and capture

`internal/book_learning` consumes `moonbook.accepted-memory.v1`, the existing
Book JSON/Markdown admission rules. Top-level accepted/promoted status wins;
legacy accepted=true applies only without status. Nested fields, prose, code
examples, candidate/rejected/invalid decisions do not admit a record. Complete
valid UTF-8 bytes are retained, including Unicode, BOM, CRLF, provenance,
applicability, counterexamples, verification and invalidation clauses. Nothing
is summarized or truncated. A capability lesson is an idea, not tool authority.

Capture includes all admitted records or none. Operational v1 limits are 256
scanned entries (directories included), 32 admitted records, 32 KiB per regular
file, 64 KiB aggregate admitted content and 512 KiB serialized snapshot. An
oversize file is omitted as part of the whole optional set even when its
admission cannot be established without reading beyond the bound. Directory
enumeration is bounded before materializing its entries. Failure diagnostics
retain counts observed so far and explicitly mark inventory completeness.
Record order uses MoonBit's deterministic shortlex relative-path order, matching
MoonBook's portable collector.

The reader resolves an authorized root alias once and checks regular-file and
directory kinds without following known links. It reads bounded bytes, then
rechecks inventory and file digests. Known unsafe entries and observed changes
discard the optional capture. These checks are **not adversarial-race-safe
filesystem confinement**: the filesystem open API has no anchored nofollow
operation, so a hostile concurrent parent/link swap may cause an out-of-root
read before detection. No atomic whole-Book revision is claimed. Source files
are never written. Cancellation propagates instead of becoming an optional
unavailable status.

## Durable host-owned input

`moonclaw.book-learning-input.v1` is stored in the worker definition's private
`config.book_learning_input` alongside the original intent, with a separate
contract marker. It contains source binding, optional installation lineage,
complete canonical records, counts/reasons/limits, capture time, a content
digest and a request/root binding digest. Record digests hash exact UTF-8
bytes. Content identity excludes capture time and host root. Installation
agent/version/bundle digest is ancestry only, not proof of current file equality
or a fabricated Book revision.

Capture runs inside the existing authorized delegation command, after its
preflight and before first model dispatch. The first durable definition wins.
Duplicate calls, definition-before-journal crash recovery, retry and restart
read and verify it; they never reread today's mutable Book. A genuinely new
durable task/intent payload digest gets a new capture. Changing only command_id
for an identical payload still addresses the same existing intent and reuses
its first snapshot; it is not a context-refresh operation. A claimed
missing/corrupt snapshot fails that run before message
dispatch rather than being silently replaced.

Statuses are `ready`, `empty`, `not_applicable`, `unavailable`, `over_budget` and
`legacy_not_captured`. Non-Book and legacy prompts retain their prior text.
Empty/unavailable/over-budget optional learning does not gate ordinary work.
Old definitions remain legacy even in the definition-before-journal window.

The supervisor lock is acquired before the store lock. Per-canonical-root
async semaphores serialize same-process coroutines; existing file locks remain
for cross-process exclusion. Independent roots are not serialized globally.
Definition/workflow writes merge the latest index under its existing lock, so
stale runtime caches cannot erase a newly captured worker.

## Model delivery and public projection

The host adds historical-context framing and all complete records before the
output contract. A typed optional descriptor follows the exact originating
user-message event through the production message ingress. The real Agent
compiler counts system instructions, skills, rules, tools and messages first.
If the optional input cannot fit intact, the entire block is replaced with an
explicit over-budget notice and the unchanged ordinary input is recompiled.
Generic pruning behavior is unchanged. Immutable descriptors and projection
status survive conversation JSON restart; durable user text remains intact.

Snapshot `ready` means captured, not proof of delivery. Receipt/public summaries
explicitly say `status_scope: capture_only` and `model_delivery: not_attested`.
Actual per-message projection statuses are exposed by the worker status API.
Public job views contain only snapshot status, hashes, bounded counts/reasons
and safe agent/version/bundle lineage, never the new private body/source path
or receipt path. Existing ordinary job configuration fields keep their prior
projection.

Public job updates atomically merge the immutable private snapshot back into
redacted GET/PUT payloads. Ordinary top-level, kind, enable and object-config
edits stay supported; explicit capture replacement/injection is rejected.
Replacing the object config of a newly captured worker with a scalar is the
one narrow compatibility restriction because it cannot preserve that private
input. Legacy/no-capture jobs retain their prior behavior.

## Verification boundary

Book owns shared machine-readable admission vectors and frozen exact
Desk-produced/imported record bytes. Its actual parser emits parity results;
Claw executes the same vectors and compares digests. The integrated native
fixture exercises authorized durable delegation, saved input, production
supervisor prompt and JSON ingress, the actual Agent tokenizer/compiler and
the final serialized `/chat/completions` request with full tail sentinels.

The final transport is explicitly injected at the real serialized request
boundary. This proves model input construction and replay, **not** a network
socket, native child launch, live provider, model quality, advertised Town
listing identity or requester installation. Town publication/bundle/actor
binding remains separate work.
