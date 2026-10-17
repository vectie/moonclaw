# Choose nested JSON values for a task

Work → **Choose nested JSON values for a task** prepares focused agent input from
a local JSON or JSON Lines export. Select complete objects, arrays or individual
typed values without copying unrelated records or losing large numeric IDs.
Only a previewed packet enters the ordinary task draft; the existing plan and
authority controls remain the execution path.

## Try the complete journey

1. Open an existing Work thread and describe the intended task in its composer.
   For example: “Explain the selected observations. Preserve the exact identifier
   and do not infer an outcome from the reported status.”
2. Expand **Choose nested JSON values for a task**, choose **JSON**, and open
   [work-items.json](examples/json-input/work-items.json). Check its filename,
   byte count, source fingerprint and format. Nothing is selected automatically.
3. Search for `uncertain`, choose document 1 `/items/1/status`, and read the exact
   JSON value. Choose **Add inspected JSON value**. Search for `9007199254740993`,
   choose document 1 `/items/0/id`, inspect it, then add it. Parent objects also
   match when they contain that text; inspect the path before choosing.
4. In the selected list, choose `/items/0/id` and move it up. Add a relevance
   note explaining why the identifier and status matter. Set the selected-text
   byte budget if needed. The owner fields and all other values are omitted.
5. Choose **Preview selected JSON in task**. The complete resulting draft shows
   the original source fingerprint and these values in the chosen order:
   - `/items/0/id`, number, exact JSON text `9007199254740993`
   - `/items/1/status`, string, exact JSON text `"uncertain"`
6. Choose **Put previewed JSON in draft**. The ordinary composer receives its
   usual input event. Use Plan, Preview, Promote and Confirm to review the task,
   scope and permissions. Import and selection do not start or approve work.
7. To revise, select an existing value, inspect it, reorder or remove it, or add
   a different path. Preview again and apply. Reapplication replaces only the
   JSON block. Other task text and existing source/CSV packets remain intact.
8. **Remove JSON block from draft** removes only this block, retaining unsent
   selections and surrounding text. **Clear unsent JSON** clears the loaded
   snapshot and selections without changing an already-applied task draft.

For line-oriented runtime exports, choose **JSON Lines** before opening
[observations.jsonl](examples/json-input/observations.jsonl). Select document 2
at `(root)` to include its entire second observation, or `/observed/count` to
include just its exact large integer. Each document has its own path namespace.
Changing the format control affects the next import; it never silently
reinterprets the current snapshot.

## Exact values and paths

- JSON accepts one complete value: object, array, string, number, boolean or
  null. JSON Lines accepts one complete JSON value on each nonblank physical
  line, up to 1000 lines/documents. LF and CRLF and one terminal newline are
  supported. A leading UTF-8 BOM is allowed. Interior/extra blank lines and
  pretty-printed multiline JSON in JSON Lines mode are errors.
- Values retain their exact source JSON syntax in `json_text`, including
  whitespace inside selected containers, escaped strings and original numeric
  spellings. Numbers never pass through JavaScript floating-point conversion:
  `9007199254740993`, `-0` and `1.2300e+400` stay exact. The latter is JSON number
  syntax, not a claim that a consumer can represent it as a finite float.
  Consumers should treat `json_text` as literal evidence and use a suitable
  lossless parser if they need arithmetic.
- Paths are JSON Pointers: empty string is the root, array indices are
  zero-based, `~0` represents a tilde and `~1` represents a slash in a key. A key
  with an empty string is distinct from the root. A source with duplicate
  decoded keys is rejected because its pointers would be ambiguous. Escaped
  equivalents, such as `a` and `\u0061`, count as the same key.
- Selecting an object or array includes its entire subtree, including fields
  not currently matched by the search. The full inspector and preview show
  those values. Parent/child and duplicate selections are refused; remove the
  existing selection first. Search does not change selection or order.
- Each selected value carries its original document number, pointer, type,
  physical start/end lines and exact JSON text. Source SHA-256 covers the full
  original UTF-8 bytes, including BOM and final newline. A separate hash covers
  the ordered selected entries. Neither fingerprint proves authenticity,
  correctness, permission, freshness or factual acceptance.
- The task packet omits unselected values and the complete source file. A
  container selection includes its selected subtree, while a scalar selection
  omits siblings. Paths and filenames can themselves reveal private context.
  Keep the original file if later independent source verification matters.

## Bounds and recovery

One local file: 256 KiB. Up to 4096 selectable nodes across the file, 32 nesting
levels, 4096 UTF-8 bytes per pointer and 1000 JSON Lines documents. Select up to
32 nonoverlapping nodes. Exact selected JSON text uses an explicit 1024–16384
UTF-8 byte budget, default 8192. Metadata adds overhead; complete packet and
combined task limits are 64 KiB and 128 KiB. Oversized inputs are rejected,
never truncated. These are byte bounds, not token, cost or relevance estimates.

Strict JSON syntax is required. Trailing commas, comments, unquoted keys,
unsupported escapes, invalid UTF-8, unpaired Unicode surrogates, non-JSON numeric
forms and data after a complete value reject the whole import. Valid syntax
does not imply truthful data. No schema inference, formula evaluation, URL
fetching, model execution or automatic learning is performed.

A failed import keeps the old snapshot, selections and draft. Successful import
replaces only unsent JSON preparation after parsing completes. Authoring edits,
composer edits, format changes, cancellation and panel closure invalidate pending
previews. Late reads cannot overwrite a newer import. Changing Work thread,
folder or gateway access clears this unsent preparation. Detached controls are
disposed. Unsent preparation is tab-local and is lost on reload; source-project
files currently save text-source curation only, not JSON selections.

## Product and verification boundary

This addresses the input-reference preparation slice of **MC-W01 step 1** and
**MOONCLAW-B02**: making nested exported observations usable as focused task input.
It does not qualify durable execution, plan authority, provider operation,
whole-host recovery or any full PRD acceptance criterion. Existing approvals and
requirement statuses remain unchanged.

Focused tests execute the production parser, selection engine, mounted DOM
controls and ordinary composer events with local synthetic files. The complete
Node surface aggregate also runs. Pinned-toolchain MoonBit UI checking, main JS
build, 73 existing compiled UI tests and interface generation pass; no public
MoonBit interface changed. The formatter ran; unrelated legacy trailing-comma
edits were reverted to avoid expanding the source change. No live graphical
browser/OS picker, assembled Vite deployment, native runtime/provider execution,
customer efficacy or release qualification is claimed. The inherited optional
native Book-receipt Node integration remains skipped without its fixture.

Run the new production-JS tests from the repository root:

```sh
node --test ui/rabbita-job/json-input.test.mjs
node --test ui/rabbita-job/*.test.mjs
```
