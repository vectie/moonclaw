# Browse a saved run as a standalone HTML report

Use the native `cmd/run_report` executable to inspect or hand over one saved run without reading raw JSONL. The report contains a step index, recorded statuses, original source positions, and expandable chronological observations. It is one HTML file with inline styling and no server, scripts, fonts, or network resources.

```sh
run_report saved/events.jsonl saved/archive.jsonl --job job-1 --run run-7 > new-run-7.html
```

Open the new HTML file in your browser. Choose a step or status-source link to jump to its observation, then click that observation's summary to expand its message and complete parsed JSON record. Links highlight their target; they do not automatically expand it. Return links go back to the index.

Choose a new output filename. Shell redirection can truncate an existing file before the program starts; never redirect onto an input. The command reads explicit files and writes stdout/stderr. It does not open a destination or modify original journals.

## Reading the report

- Both `--job` and `--run` are required, exact case-sensitive string matches. A reused run ID in another job is excluded. IDs are not trimmed.
- Every supplied observation for the pair is included, without paging. Events sort by recorded timestamp; ties keep input-file and physical-line order. Duplicates remain visible.
- The index starts with a run-level row if present. Step rows follow first-observation order. Empty step IDs remain a distinct step (`""`). Missing or null step IDs belong to the run-level row, matching the existing parser.
- Each row's latest recorded status comes from the last observation in that scope containing a status field. Explicit `null` is shown as `null`; absent status is `not recorded`. Unknown structured statuses remain JSON. Step statuses never become run statuses. Messages/event names do not imply status.
- Status-source links identify the exact observation behind the summary. Each observation retains its original input filename and physical line number.
- Timestamps use recorded integer units without guessing a date, time zone, or unit. Observed spans are not execution durations.

This is historical supplied evidence, not current runtime state, execution proof, retry permission, or owner acceptance. It cannot establish that all files from a live run were supplied. It does not refresh or provide runtime controls.

## Content and sharing

All selected messages, data, unknown fields, and source filenames are included. Text is escaped as text. No redaction is performed; inspect before sharing.

The complete JSON view preserves parsed values, not original byte formatting. Numbers follow the existing MoonBit JSON reader's precision limits. HTML rendering can normalize text such as carriage returns; use the complete JSON view for its escaped recorded value. Keep original journals for archival provenance. HTML is an inspection format, not a runtime import format; use `extract_run` for reusable JSONL.

## Bounds and errors

At most 32 literal input paths and 10,000 combined observations are accepted. Each input has the existing 4 Mi UTF-16-code-unit parser bound. Escaped HTML including styling and repeated display text is bounded to 8 Mi UTF-16 code units. HTML is prepared before stdout is written. File reads and fragment construction precede their size checks; this is not constant-memory streaming.

Every input is validated, including unselected records. Missing files, malformed unrelated records, missing IDs, unknown/repeated options, duplicate literal paths, absent exact pairs, or exceeded bounds exit 1 with stderr and no successful stdout. Aliased paths are not detected. Use `./--name.jsonl` for filenames beginning with `--`. OS write failures may leave partial output. `--help` alone prints usage and exits 0.

## Host API and qualification

`@job_journal.journal_run_html(entries, job_id="job-1", run_id="run-7")` returns bounded standalone HTML and raises on invalid input or absent selection.

This addresses offline inspection in PRD MOONCLAW-B10 and advanced journal detail in MC-W07. It does not qualify secret-redacted export, live owner recovery controls, browser compatibility/usability, or whole-product acceptance. Focused tests verify HTML structure, local links, decoded records, CLI behavior and data preservation. Browser rendering was not exercised.
