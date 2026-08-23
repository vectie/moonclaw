# MoonCode typed resume stream

`mooncode-stream-resume.v1` is an opt-in, bounded replay contract for MoonDesk
and other user-facing clients. It projects the durable MoonCode journal into
planner, assistant, and tool-output events without exposing the raw journal.

## Compatibility seam

The existing endpoint remains the integration point:

```text
GET /v1/code/sessions/<id>/stream
```

- Requests without `resume_cursor` use the existing `mooncode-stream.v2`
  `since` behavior unchanged.
- `resume_cursor=start` explicitly starts the typed contract.
- A cursor returned on a typed event or `done` record resumes that same
  session and book stream. Cursors are opaque to clients.
- `format=jsonl|sse`, `wait_ms`, and `poll_ms` keep their existing meanings.
- `replay_limit` defaults to 128 visible events, is clamped to 512, and values
  at or below zero select the default.

Do not combine `since` with the typed mode. Presence of `resume_cursor` selects
the typed contract; the legacy path does not parse or reinterpret it.

## Cursor and replay rules

The cursor carries an arbitrary-precision decimal journal sequence, a stream
binding, an epoch, and an integrity checksum. It is bound to the session and
book root, so a cursor from another stream is rejected with HTTP 400. Invalid,
oversized, non-canonical, or modified cursors are also rejected.

Replay is monotonic and idempotent:

- each visible event carries the cursor after that durable event;
- the initial `meta` cursor remains at the requested boundary, so disconnecting
  before receiving an event cannot skip it;
- `done` carries the latest fully scanned durable boundary;
- reconnecting from the same event cursor returns the same remaining bytes for
  a stable journal;
- reasoning-only records may advance the `done` cursor but are never emitted.

MoonClaw scans the canonical committed journal while holding its journal lock
and spools no more than the allowed number of projected events. It does not
materialize an unbounded event array. A second validation after spooling makes
journal replacement or replay growth fail before a 200 response is sent.

## Gap and expiry recovery

MoonClaw returns HTTP 409 without a partial replay when:

- `gap`: visible events after the cursor exceed `replay_limit`;
- `expired`: the journal epoch no longer matches the cursor;
- `future`: the cursor is ahead of the durable journal.

The JSON error metadata contains `resume_status`, `recovery=reload_snapshot`,
and an opaque `latest_cursor`. Clients must reload the bounded conversation
snapshot, render it, and then reconnect from the snapshot's corresponding
cursor. They must not silently jump to `latest_cursor` without reloading,
because doing so would hide the detected gap.

## User-facing projection and privacy

Only these `content_kind` values are serialized:

- `planner`: phase and status only;
- `assistant`: answer delta or final answer text;
- `tool_output`: tool name, status, bounded output, and truncation state.

Reasoning messages and reasoning deltas are counted as filtered but never
serialized. Planner details, raw tool arguments, raw events, book roots,
journal paths, spool paths, working directories, and sandbox artifact paths are
not copied. Path-looking output is replaced by a generic notice that directs
the client to the validated workspace artifact contract. Text uses the named
MoonCode output policy and a UTF-8-safe boundary.

MoonDesk should consume planner events only for a quiet working indicator. It
should render assistant content normally and interrupt the user only for an
actionable warning surfaced through the separate warning contract.

## Metrics

Every `meta`, `done`, and 409 recovery record embeds
`mooncode-stream-resume-metrics.v1` with bounded, low-cardinality values:

- requested replay limit and resume status;
- scanned, durable, visible, filtered, eligible, and replayed event counts;
- filtered reasoning count and resume lag in visible events;
- gap, expiry, and future booleans;
- wait duration and poll-attempt count.

These response-local metrics contain no prompts, model reasoning, tool
arguments, paths, event IDs, session IDs, or arbitrary labels. They can be
aggregated by status and contract without exporting stream content.
