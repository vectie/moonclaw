# Carry prior notes into a new revision's inspection

When a job produces revised outputs, a reviewer can carry selected prior notes
into a fresh inspection worksheet without retyping them. Choose exact old/new
artifact IDs, inspect the resulting correspondence, and continue with the usual
`annotate`, `report` and `collect` commands. Every target artifact starts
`unreviewed`, even if its bytes are identical or the prior reviewer marked it
`inspected`. No inspection, acceptance or approval transfers.

This extends the existing local artifact-review CLI and the exact-revision
inspection portions of original PRD MC-W02 and MOONCLAW-B04/B10. Same-packet
feedback comparison and reviewer coverage remain unchanged. This feature does
not run a job, produce revisions, prove common ancestry, or qualify the full
native/host evidence-export and redaction workflow.

## End-to-end local use

Use Python 3.9+ and its standard library. Start with two existing portable export
folders, and a worksheet bound to the exact previous packet. The operator must
inspect the outputs and decide their correspondence; logical keys, filenames,
versions and equal content do not make that choice automatically.

Create `mapping.json` using actual exact artifact IDs from each packet:

```json
{"mappings":[
  {"from_artifact":"draft-old","to_artifact":"draft-new"},
  {"from_artifact":"chart-old","to_artifact":"chart-new"}
]}
```

The target packet is always the first packet argument:

```sh
python3 tools/artifact_review.py carry-notes new-packet old-packet old-review.json mapping.json > carry-forward.json
python3 tools/artifact_review.py carried-report new-packet old-packet carry-forward.json --markdown > carry-review.md
python3 tools/artifact_review.py carried-report new-packet old-packet carry-forward.json > carry-review.json
python3 tools/artifact_review.py carried-worksheet new-packet old-packet carry-forward.json > new-review.json
python3 tools/artifact_review.py report new-packet new-review.json --markdown > new-packet/reviewer-notes.md
```

Inspect `carry-review.md`: each mapping shows both exact artifact/run/job/revision
identities, digests, byte equality, prior state and complete prior note. It lists
old artifacts not carried and target artifacts starting blank. Byte equality
means matching supplied content hashes, not semantic equality, identity,
quality, provenance authenticity or current inspection. One-to-one mappings can
cross logical keys, because the operator explicitly chooses them; that alone
does not prove lineage.

Open and inspect the new copied content. Record your new observation using the
ordinary existing worksheet edit contract:

```json
{"annotations":[
  {"artifact_id":"draft-new","state":"inspected","note":"Checked the revised total against the supplied annex."}
]}
```

```sh
python3 tools/artifact_review.py annotate new-packet new-review.json --changes new-observations.json > new-review-updated.json
python3 tools/artifact_review.py collect new-packet new-review-updated.json > new-feedback.json
```

`annotate` replaces the whole note only when explicitly chosen. Keep the saved
carry-forward and both packets to retain original context after writing a new
observation. Carrying does not update an existing current worksheet: export a
fresh worksheet, then record new observations. No existing notes are overwritten.

## What survives

`carry-forward.json` is a `moonclaw.artifact-review-transfer.v1` handoff. It embeds
the exact previous worksheet UTF-8 text and hash, including uncarried notes, the
complete target packet identity and explicit mapping pairs. Every reopening
reverifies both supplied packets and the embedded worksheet. The original
worksheet file/path is not required: relocate both packets and the handoff and
use the new paths. No absolute runtime path is followed or included in the
handoff's projected identities.

The exported worksheet uses unchanged `moonclaw.artifact-review-notes.v1`, with
the prior self-entered reviewer label. A carried note is prefixed with a clear
reinspection warning, previous manifest digest, exact previous artifact ID and
prior checklist state; the original note then follows without shortening.
Unmapped targets have blank notes. Every annotation is `unreviewed`. This keeps
carried context visible even in an ordinary worksheet report or feedback
collection, instead of making an old inspection look current.

The source review is an unsigned local statement. Hashes and labels do not
authenticate a person, prove authority, establish newest version or prevent a
person from editing JSON and recomputing digests. There is no automatic secret
scrubbing. Review any proposed external sharing separately; these commands do
not send or upload anything.

## Bounds and errors

- Explicit 1–32 one-to-one mappings; exact known IDs only. No empty selection,
  repeated source/target, unsupported field or automatic name matching.
- Both packets must be different exact verified exports. For one packet, use
  ordinary `annotate`; this is not a feedback editing shortcut.
- Prior worksheet and mapping input: at most 4 MiB each. Saved carry-forward and
  rendered report: at most 16 MiB. Exported worksheet: at most 4 MiB.
- A note plus its provenance prefix must fit the existing 16,384-character note
  limit. Otherwise creation refuses without truncation; explicitly shorten a
  separate prior worksheet if appropriate and retain the original.
- Existing packet bounds and verification apply to every copied file in both
  packets. Wrong packet, drifted manifest/content/record or altered embedded
  worksheet refuses, even for artifacts outside the chosen mapping.

Inputs and runtime state are never written. Redirect to new filenames: the shell
can truncate an input before Python runs. Check exit status before using output;
I/O errors can leave a partial redirected file. Success exits 0, validation/read
failure 1 with no successful stdout, argument errors 2. Work from stable saved
files; sequential verification is not a concurrent-edit atomic snapshot. The
existing verifier does not check README.txt or SHA256SUMS; use the export's
separate checksum workflow when needed. Markdown includes identity text rather
than ambiguous relative links across the two packet directories.

## Focused verification

```sh
PYTHONDONTWRITEBYTECODE=1 python3 scripts/test-artifact-review.py
PYTHONDONTWRITEBYTECODE=1 python3 scripts/test-artifact-review-collection.py
PYTHONDONTWRITEBYTECODE=1 python3 scripts/test-artifact-review-progress.py
PYTHONDONTWRITEBYTECODE=1 python3 scripts/test-artifact-review-coverage.py
PYTHONDONTWRITEBYTECODE=1 python3 scripts/test-artifact-review-transfer.py
```

Eight new real-file CLI journeys cover selected carry, unchanged/changed bytes,
blank targets, complete source retention, relocated reopening, ordinary
annotate/collect continuation, explicit correspondence, incorrect source and
length refusal. Each CLI invocation verifies input bytes unchanged. Fixtures,
stdout and stderr are retained in the printed directory; set
`MOONCLAW_TRANSFER_EVIDENCE` to a fresh directory to choose it. The 33 existing
review/collection/progress/coverage tests are regressed.

Synthetic export-format packets exercise Python stdlib behavior. Native export,
MoonBit/runtime, browser/viewer, actual user identity, provider and full product
were not run. No dependency installation, network or Moon invocation is needed.
R50 remains the last fully verified cumulative checkpoint; R51–55 are separate.
