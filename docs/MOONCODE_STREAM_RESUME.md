# Canonical MoonCode watch

MoonClaw owns the conversation projection. MoonDesk adapts session metadata and
renders that projection; it does not replay raw events to reconstruct chat.

```text
GET /v1/code/sessions/<id>/watch?book_root=<path>&since_revision=<decimal>&wait_ms=<ms>&poll_ms=<ms>
MoonClaw journal -> canonical watch -> MoonDesk metadata adapter -> existing UI
```

The endpoint uses the existing `moonsuite-conversation-watch.v2` contract.
Revision and `next_sequence` are canonical nonnegative decimal strings carrying
the committed journal position. Neither an event count nor a bounded integer
is a resume cursor. Existing authentication and session/Book binding apply.

When the journal revision differs, watch returns one snapshot with the native
session record and canonical conversation. Otherwise it waits up to 15 seconds
by default (maximum 30 seconds, or zero for an immediate response). Poll interval
defaults to 100 ms and uses the existing 25–2000 ms bounds.

Waiting checks filesystem modification metadata rather than decoding the journal
on each poll. Only a heartbeat is retained while waiting. A final locked read of
the committed journal supplies the authoritative snapshot even if the filesystem
signal did not change. A changed response carries a snapshot; an unchanged
response carries `snapshot=null`. Cancellation uses the existing async request
scope. There is no per-client execution state or durable watch store.

MoonDesk resolves the selected session's Book, forwards its accepted revision,
and adapts the snapshot with the existing session/conversation helpers. It
preserves the runtime's cursor and terminal hint. Browser generation checks,
abort-on-navigation and the existing typed watch decoder continue to reject
cross-session, stale and malformed replies. Disconnects retain the last accepted
conversation and retry with its cursor. A revision rollback is surfaced through
the existing rollback result, not silently accepted.

## Work graph

Each work item projects `graph.nodes` and `graph.edges` from the same work steps.
Batches select operations; operations reference files and retained results;
check-input edges carry only recorded paths/versions. Temporal order is not
inferred data dependency. The graph is rebuilt with the canonical snapshot,
not persisted or used for scheduling/finish. Construction is linear in the
steps and explicit references; payload size and DOM cost grow with history.
The desktop reuses evidence cards and file navigation, with completed work
folded. Existing raw diagnostic endpoints remain available.

## Removed paths

The unused opt-in `mooncode-stream-resume.v1` projection, opaque cursor codec,
replay spooling, per-response resume metrics and dedicated trial tests were
removed. The desktop no longer fetches a snapshot, downloads raw JSONL only to
advance a cursor, then fetches another snapshot. It no longer constructs watch
responses from event counts or converts canonical revisions to `Int32`.

`/stream?format=jsonl|sse&since=<decimal>` remains the diagnostic event stream.
It is not the desktop conversation source. There is no `resume_cursor` mode.
The runtime and desktop advertise the canonical watch endpoint together in
their capability surface; no fallback to an older daemon is provided.

## Cost and limits

Unchanged waits transmit no transcript, event spool or artifact body. Each
canonical rebuild indexes command identities once, preserving turn order while
avoiding a full turn-array search for every event and receipt. Watch still reads
the full committed journal to build snapshots, and changed responses contain
the full canonical conversation. This is not an incremental projection cache or
a guarantee of constant rebuild cost. Each long poll performs an initial and,
when waiting, final snapshot read; metadata polling itself is constant size.

Existing work steps and evidence links supply the minimal graph described above.
Complete data dependencies and automatic invalidation remain unfinished.
No graph database, UI wiring workflow, extra model call or completion gate was
introduced.

Native tests cover HTTP admission, append wake-up and cursor reconnect. The
desktop regression passes a large exact cursor through metadata adaptation and
the actual UI codec. Existing UI tests cover stale generations, rollback,
disconnects and canonical usage. These are local fixtures, not installed-app or
live-provider qualification.
