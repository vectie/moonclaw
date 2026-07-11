# Evidence quality and workspace containment

MoonClaw validates two distinct properties of a research dossier:

1. semantic quality — declared policy thresholds, source authority, claims,
   citations, output artifacts, and open questions;
2. material evidence — every source's `artifact_ref` exists and is contained
   by the selected MoonBook.

Run both checks with:

```sh
moon run cmd/main -- evidence validate \
  /absolute/path/to/book \
  /absolute/path/to/book/raw/moonclaw/evidence-dossier.json \
  /absolute/path/to/book/outputs/moonclaw/evidence-quality-receipt.json
```

An `artifact_ref` must be relative to the book root, contain no `..` segment,
exist at validation time, and resolve inside the canonical book root after
following symbolic links. This prevents both accidental dependency on a source
checkout and deliberate symlink escape.

A remote `locator` is still useful provenance. It identifies the authority and
retrieval origin. It does not replace a local retrieval artifact: a concise
retrieval note, downloaded source, data fixture, or captured contract must be
stored in the MoonBook and cited by `artifact_ref`.

Keep product code generic. Minimum source counts and authority requirements
belong to each dossier's versioned policy. Workspace containment and the
existence of declared evidence are universal integrity rules and therefore
belong in MoonClaw.
