# Choose ordered fields across JSON records

The Work-thread JSON-input panel projects ordered exact relative JSON Pointers
across array items or JSON Lines documents. Preview groups the chosen cells by
record; explicit Add appends values in record order, then chosen field order.
This prepares only the fields a task needs, without including unrelated record
contents. It does not evaluate expressions or start work. The task packet remains
the existing ordered flat `moonclaw.selected-json.v1` list, not a new structured
record or table packet. Each included value keeps its document and exact pointer.

For multiple fields, enter a JSON array of pointer strings, for example
`["/id","/details/amount"]`. Field array order is significant. A single raw pointer
like `/details/amount` is still supported. Empty input or `[""]` means each whole
record. JSON string escaping permits quotes and newline characters in member
names; JSON Pointer escaping `~0` and `~1` still applies to literal `~` and `/`.
Do not trim spaces that are part of a key. Choose one to 32 nonoverlapping fields;
duplicate pointers and parent/child combinations are rejected before lookup,
even if the fields or records are absent. Fields are exact paths, not expressions.

Try `docs/examples/json-projection/record-fields.json`: inspect `/items`, enter
`["/id","/a~1b~0"]`, choose cohort type **boolean**, pointer `/ready`, value `true`,
then **Preview record fields**. The first three records appear with two ordered
cells each. One cell is missing; explicit null remains an included value. Adding
appends exact tokens `9007199254740993123`, `null`, `-0`, `1.2300e+400`, and
`"\u0061"`. The missing cell adds no placeholder. Record/document pointers retain
the association; consumers must not assume that every record has equal width.
The readiness predicate, excluded record and private field do not enter the packet.

1. In a normal Work thread, write the objective in the ordinary task draft.
2. Open **Choose nested JSON values for a task**, select JSON format and import
   `docs/examples/json-projection/work-items.json`.
3. Inspect `/items` in the existing value selector. Choose **Immediate items of
   the inspected array** and set relative pointer to `/details/amount`.
4. Choose **Preview record fields**. All four records are listed: three
   exact values (`1.2300e+02`, `9007199254740993123`, `null`) and one missing field.
   Present null is included; a missing field is explicitly reported and omitted.
5. Choose **Add previewed values: record order, then field order**. Existing
   selections retain their positions; new values append in record-major order.
   Already-selected exact values are skipped, so the full combined selection may
   retain a manually established order. Inspect/remove/reorder it normally.
6. Enter why these inputs matter, **Preview selected JSON in task**, inspect the
   complete task, then **Put previewed JSON in draft**. Only selected field values
   enter the packet. The `private-owner` fields remain omitted.
7. Use the ordinary Plan/Preview/Promote/Confirm controls for any eventual work.

For JSON Lines, choose that format before opening the file, then choose **All
imported JSON Lines documents**. Each document is one record, including scalar
documents. An empty relative pointer selects whole records and their subtrees;
the preview makes those exact contents visible. A nonempty pointer uses standard
JSON Pointer escaping (`~0`, `~1`), and array indices are zero-based. Missing or
inapplicable paths are listed; nothing is silently fabricated or coerced.

Projection does not use the free-text search as a record filter. Array mode starts
from the inspected array's immediate items; JSONL mode starts from all documents
in the frozen imported file. Leave the cohort type at **All records** to preserve
that behavior, or choose a scalar type, an exact relative field pointer and one
JSON scalar equality value. Strings require JSON quotes. Preview reports total,
included and excluded record counts, missing predicate fields, and every included
record's ordered cells, exact present value or explicitly missing path. A present
null has state `null`, type `null` and exact token `null`; a missing cell has state
`missing` and no value token. An empty cohort adds
nothing. The predicate field does not itself enter the task packet.

For a small guided cohort, import `docs/examples/json-projection/cohorts.json`,
inspect `/items`, choose cohort type **string**, field `/status` and equality
value `"ready"`. Project `/details/amount`. The first two records form the cohort,
with exact amount tokens `1.2300e+02` and `9007199254740993123`. The escaped status
spelling in the second record compares equal to decoded `"ready"`. Other records
and private-owner fields remain omitted. Preview, add, and use the ordinary task
preview/apply controls as above. Change the predicate to type **null**, field
`/status`, value `null`: only the explicit null status matches, not the missing
status. Its missing amount is reported, so no value can be added.

Equality compares decoded strings (case-sensitive, without Unicode normalization),
exact decimal numeric values, or boolean/null values, always with matching types.
Thus `1`, `1.0`, and `1e0` compare equal; `-0` equals `0`; string `"1"` never equals
number `1`. Large integers and exponents never round through JavaScript Number.
Coefficient/exponent strings are normalized without constructing large powers.
Original selected number and string tokens remain unchanged in the task packet.
Missing and container fields never match a scalar. No expressions, wildcards,
coercion, sorting, aggregation, multiple predicates or code evaluation are offered.
The predicate value and each pointer have a 4096 UTF-8-byte bound. Ordered field
input and its serialized pointer array are each bounded to 16384 UTF-8 bytes.
Preview permits at most 4096 record-field cells; narrow the cohort or fields when
that bound is exceeded. Nothing is truncated. The imported snapshot retains its
existing 256 KiB, 4096-node, 32-depth limits.

Bulk addition is atomic: more than 32 total values, overlap with a selected
parent/child, an invalid byte budget, or total selected JSON tokens exceeding the
current 1,024–16,384 UTF-8-byte budget rejects the entire addition. Existing
selection and draft remain untouched. Narrow the typed cohort or chosen fields;
no silent truncation occurs. Already-selected exact values stay in their original
positions. The packet stage revalidates its existing schema, 64 KiB packet limit,
selected-byte budget and 128 KiB combined-draft bound. Changing the
snapshot, source selector, projection or cohort fields, Work context, gateway access or task draft,
selection, purpose or budget, or closing/cancelling preparation, invalidates the
projection preview. Direct silent changes to these fields or composer text are
also checked before addition and packet application. No selection is automatic;
Add, full task Preview and Put in draft are separate actions.

Imported data is literal untrusted source material. Hashes identify the frozen
snapshot, not authenticity, disk freshness, permission or accepted knowledge.
No upload, provider execution, persistent selection or new authority is involved.
PRD trace: MC-W01 and MOONCLAW-B02 (comprehensible objective and bounded inputs).

Production-module and mounted-controller tests cover both formats, exact number
and escape spelling, missing/null differences, failed atomic additions, stale
previews and normal task-packet readback. Real-browser, configured provider,
native lifecycle and broad release gates are unrun.
