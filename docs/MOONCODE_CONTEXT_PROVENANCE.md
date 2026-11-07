# MoonCode Context Provenance

MoonCode keeps internal provenance beside model messages. Provider serialization
removes the private metadata; it is not an authorization token or an instruction
channel for retrieved content.

## Current Contract

New messages use `_moonclaw_context` with
`moonclaw.context-fragment.v2`:

- `kind`: the closed set `system`, `skill`, `environment`, `warning`,
  `tool_result`, `user`, or `assistant`.
- `source`: a producer identifier such as `skill.loaded_resource`.
- `content_items`: one provenance entry per visible content item, with a
  recognized kind and valid source.
- `requires_separate_message`: a Boolean preserving required message boundaries.

Kind/source tokens use ASCII letters, digits, `_`, `-`, `.`, and `:`;
kind length is at most 64 characters and source length at most 160. V2 validates
the content-item count against the message.

The v1 metadata reader was removed; new records use v2. Missing or malformed
metadata follows conservative inference below.

## Projection And Recovery

Malformed or absent metadata normalizes conservatively without dropping the
visible message. Provider shaping reattaches origin by visible-message matching
and, for tool messages, `tool_call_id`. Unmatched material receives inferred
metadata rather than invented provenance.

Journal and continuation records retain the internal metadata. Output
truncation, image projection, and compaction must preserve the associated
origin while retaining valid tool-call/result relationships. Provenance
structure does not prove that a summary is semantically lossless.

Metrics and context pressure use the provider-visible projection, excluding
internal metadata. A provenance label cannot grant tool authority or upgrade an
external result into trusted verification.

The implementation is `cmd/daemon/mooncode_context_provenance.mbt`; focused
coverage is in `mooncode_context_provenance_wbtest.mbt`. Compaction behavior is
documented in [Long-context compaction](LONG_CONTEXT_COMPACTION.md).
