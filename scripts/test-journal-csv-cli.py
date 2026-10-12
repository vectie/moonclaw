#!/usr/bin/env python3
"""Exercise a compiled native journal_csv against retained local fixtures.
Usage: test-journal-csv-cli.py ABSOLUTE_BINARY NEW_OUTPUT_DIRECTORY
"""
import csv
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys

binary = Path(sys.argv[1]).resolve(strict=True)
out = Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=False)
receipts = []


def event(run, timestamp, message, **extra):
    return dict(run_id=run, job_id="job-01", timestamp=timestamp,
                event_type="step.progress", step_id="inspect", status="Unknown",
                message=message, data={"receipt": "fixture", "unicode": "雪"},
                future_field={"kept": [1, None, True]}, **extra)


def write(name, records, blank=False):
    path = out / name
    body = "\r\n".join(json.dumps(x, ensure_ascii=False) for x in records)
    path.write_bytes((("\r\n" if blank else "") + body + "\r\n").encode())
    return name


def run(name, args, ok=True):
    process = subprocess.run([str(binary), *args], cwd=out, capture_output=True)
    (out / (name + ".stdout")).write_bytes(process.stdout)
    (out / (name + ".stderr")).write_bytes(process.stderr)
    receipts.append(dict(case=name, args=args, exit=process.returncode))
    assert process.returncode == (0 if ok else 1), receipts[-1]
    if not ok:
        assert process.stdout == b"", name
        assert process.stderr.startswith(b"journal_csv:"), name
        return None
    assert process.stderr == b"", (name, process.stderr)
    return process.stdout


def rows(raw):
    assert raw.endswith(b"\r\n")
    reader = csv.DictReader(io.StringIO(raw.decode(), newline=""), strict=True)
    expected = ["source", "source_line", "timestamp", "run_id", "job_id", "step_id",
                "event_type", "status_json", "message", "data_json", "record_json",
                "text_prefixed_columns"]
    assert reader.fieldnames == expected, reader.fieldnames
    result = list(reader)
    for row in result:
        assert None not in row and None not in row.values()
        prefixes = row["text_prefixed_columns"].split(";") if row["text_prefixed_columns"] else []
        for field in prefixes:
            assert row[field].startswith("'"), (field, row)
            row[field] = row[field][1:]
        record = json.loads(row["record_json"])
        for field in ["run_id", "job_id", "event_type", "message"]:
            assert row[field] == record[field]
        assert row["step_id"] == (record.get("step_id") or "")
        assert int(row["timestamp"]) == record["timestamp"]
        assert json.loads(row["data_json"]) == record["data"]
        if row["status_json"]:
            assert json.loads(row["status_json"]) == record.get("status")
        else:
            assert record.get("status") is None
    return result


late = event("00123", 30, 'Receipt, says "yes"\n雪')
other = event("else", 20, "Receipt elsewhere")
early = event("00123", 10, "RECEIPT early\r\nsecond line")
first = write("=saved,one.jsonl", [late, other, early, late], blank=True)
formula = event("=run", -3, "  =SUM(1,2)")
formula.update(job_id="+job", step_id="@step", event_type="-type", status=-7, data=-8)
future = event("00123", 40, "Later unknown result")
future.update(status={"future": "unconfirmed"})
absent = event("00123", 50, "No optional fields")
absent.pop("status"); absent.pop("step_id")
nulls = event("00123", 60, "Explicit null status and empty step")
nulls.update(status=None, step_id="")
second = write("second.jsonl", [formula, future, absent, nulls])
many = write("many.jsonl", [event("many", n, str(n)) for n in range(1001)])
(out / "empty.jsonl").write_text("")
(out / "malformed.jsonl").write_text(json.dumps(other) + "\n{bad\n")
invalid_step = dict(nulls, step_id=None)
write("null-step.jsonl", [invalid_step])
inputs = [first, second, many, "empty.jsonl", "malformed.jsonl", "null-step.jsonl"]
before = {name: hashlib.sha256((out / name).read_bytes()).hexdigest() for name in inputs}

raw = run("all", [first, second])
(out / "observations.csv").write_bytes(raw)
all_rows = rows(raw)
expected = [formula, early, other, late, late, future, absent, nulls]
assert [json.loads(row["record_json"]) for row in all_rows] == expected
assert all_rows[1]["source"] == first and all_rows[1]["source_line"] == "4"
assert all_rows[3]["source_line"] == "2" and all_rows[4]["source_line"] == "5"
assert all_rows[0]["text_prefixed_columns"] == "run_id;job_id;step_id;event_type;status_json;message;data_json"
assert all_rows[1]["text_prefixed_columns"] == "source"
assert run("repeat", [first, second]) == raw

selected = rows(run("filtered", [first, second, "--run", "00123", "--step", "inspect",
    "--type", "step.progress", "--query", "receipt", "--since", "10", "--until", "30"]))
assert [json.loads(x["record_json"]) for x in selected] == [early, late, late]
assert len(rows(run("beyond-page", [many]))) == 1001
assert rows(run("empty", ["empty.jsonl"])) == []
assert rows(run("no-match", [first, "--run", "missing"])) == []

# Standard-library CSV/JSON reconstruction preserves event identities and unknown
# fields. New source filenames/line positions correctly describe the new file.
reimport = write("reconstructed.jsonl", [json.loads(x["record_json"]) for x in all_rows])
again = rows(run("reimport", [reimport]))
assert [json.loads(x["record_json"]) for x in again] == expected

for name, args in [
    ("bad-filtered-out", ["malformed.jsonl", "--run", "no-such-run"]),
    ("null-step", ["null-step.jsonl"]),
    ("bad-range", [first, "--since", "3", "--until", "2"]),
    ("bad-number", [first, "--since", "1.2"]),
    ("unknown-option", [first, "--limit", "1"]),
    ("repeated-input", [first, first]),
    ("repeated-option", [first, "--run", "a", "--run", "b"]),
    ("missing-value", [first, "--run"]),
    ("missing-file", ["not-present.jsonl"]),
]:
    run(name, args, ok=False)
help_text = run("help", ["--help"]).decode()
assert "current runtime status" in help_text and "--limit" not in help_text
assert before == {name: hashlib.sha256((out / name).read_bytes()).hexdigest() for name in inputs}
receipt = dict(binary=str(binary), binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
               inputs_sha256=before, cases=receipts, rows=len(all_rows), full_selection_rows=1001,
               csv_sha256=hashlib.sha256(raw).hexdigest(), inputs_unchanged=True,
               tested_reader="Python standard library csv.DictReader(strict=True)",
               spreadsheet_ui_tested=False)
(out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(f"PASS: {len(receipts)} native CLI cases; CSV parsed, semantic round-trip preserved, 1001 rows exported, inputs unchanged")
