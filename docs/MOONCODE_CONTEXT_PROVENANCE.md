# MoonCode context provenance

MoonCode attaches internal provenance metadata to every model message that it
constructs or recovers. The metadata is deliberately out of band: it is
removed when the typed provider request is serialized, so enabling provenance
does not change the text, images, roles, tool calls, or tool results visible to
the model.

## Contract

The private message field `_moonclaw_context` uses contract
`moonclaw.context-fragment.v1` and contains:

- `kind`: `system`, `skill`, `environment`, `warning`, `tool_result`, `user`,
  or `assistant`;
- `source`: a stable, low-cardinality producer name such as
  `skill.loaded_receipt` or `environment.horizon_progress`;
- `contract`: the contract identifier above.

The kind namespace is open. A well-formed future kind is retained as an
unknown kind rather than rejected or rewritten. Extra metadata fields are also
retained. Kind values are limited to 64 ASCII identifier characters and source
values to 160; letters, digits, `_`, `-`, `.`, and `:` are accepted.

Malformed, missing, or unsupported metadata fails soft. MoonCode preserves the
complete visible message, infers a conservative kind from its role and known
runtime anchors, and records `legacy.inferred` as the source. Provenance must
never make a recoverable transcript unreadable.

## Alignment and durability

Typed OpenAI request construction intentionally strips private fields. After a
provider request has been shaped, MoonCode reattaches metadata by matching its
visible messages to the original source sequence. Exact message equality is
the normal path. Tool messages additionally use `tool_call_id`, which preserves
their origin when overload recovery truncates tool output. Inserted,
compacted, reordered, or otherwise unmatched messages receive conservative
inferred metadata; a length mismatch never rejects content.

Durable journal and continuation payloads retain the metadata. Image payload
projection and tool-output compaction preserve the originating metadata while
changing only the already-existing durable or bounded visible representation.
Recovery accepts both typed and legacy untyped checkpoints.

Planner metrics and semantic-compaction pressure are calculated from the
provider-visible projection. Internal metadata therefore cannot inflate token
pressure, change cache measurements, or trigger compaction.
