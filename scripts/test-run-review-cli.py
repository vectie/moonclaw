#!/usr/bin/env python3
"""Exercise the native saved-run review with local synthetic producer-shape inputs."""
import copy
import hashlib
import json
import pathlib
import re
import subprocess
import sys

binary = pathlib.Path(sys.argv[1]).resolve()
out = pathlib.Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=False)
inputs = out / "inputs"
inputs.mkdir()
packet = inputs / "portable-output"
(packet / "files").mkdir(parents=True)
(packet / "records").mkdir()
receipts = []


def digest(data):
    return "sha256:" + hashlib.sha256(data).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def entry(index, id, run, job, version, state, content):
    record = dict(id=id, run_id=run, job_id=job, artifact_type="analysis.report",
                  logical_key="release-notes", version=version, status=state,
                  path=f"/original-machine/artifacts/{id}/report.txt", content_type="text/plain",
                  metadata={"summary": "Synthetic review 🌙", "unreviewed": True}, created_at=version * 10,
                  scope=["local-fixture"], future_record={"preserved": True})
    if state == "Archived":
        record["archived_at"] = 30
    raw = (json.dumps(record, indent=2) + "\n").encode()
    record_path, content_path = f"records/{index}.json", f"files/{index}-report.txt"
    (packet / record_path).write_bytes(raw)
    (packet / content_path).write_bytes(content)
    return dict(record=record, record_path=record_path, content_path=content_path,
                record_sha256=digest(raw), content_sha256=digest(content), content_bytes=len(content),
                future_export_entry={"kept": True})


def event(run, time, message, job="job-report", **changes):
    result = dict(run_id=run, job_id=job, event_type="step.observed", timestamp=time,
                  message=message, data={"fixture": "local", "artifact_ids": ["old", "new"]},
                  future_event={"kept": True})
    result.update(changes)
    return result


artifacts = [entry(1, "old", "report-run", "job-report", 1, "Archived", b"first draft\n"),
             entry(2, "unrelated", "other-run", "other-job", 1, "Active", b"other\n"),
             entry(3, "new", "report-run", "job-report", 2, "Active", "revised 🌙\n".encode())]
manifest = dict(schema="moonclaw.artifact-export.v1", artifacts=artifacts,
                total_content_bytes=sum(e["content_bytes"] for e in artifacts))
manifest_path = packet / "manifest.json"
write_json(manifest_path, manifest)
checksums = []
for path in sorted(packet.rglob("*")):
    if path.is_file():
        checksums.append(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(packet)}\n")
(packet / "SHA256SUMS").write_text("".join(checksums))
first, second, empty = inputs / "first.jsonl", inputs / "second.jsonl", inputs / "empty.jsonl"
first_events = [event("report-run", 30, "later progress"),
                event("other-run", 0, "other", job="other-job"),
                event("report-run", 10, "first observation", step_id="write", status="Running")]
second_events = [event("report-run", 10, "same-time second file", step_id="write", status="Unknown"),
                 event("report-run", 40, "<script>bad</script> [x](https://bad.invalid)", status={"new_status": True})]
first.write_text("\n" + "\n".join(json.dumps(e) for e in first_events) + "\n")
second.write_text("\n".join(json.dumps(e) for e in second_events) + "\n")
empty.write_text("")


def snapshot():
    return {str(p.relative_to(inputs)): digest(p.read_bytes()) for p in inputs.rglob("*") if p.is_file()}


def invoke(label, args, expected=0):
    before = snapshot()
    process = subprocess.run([str(binary), *map(str, args)], capture_output=True)
    assert snapshot() == before, f"{label}: input changed"
    (out / f"{label}.stdout").write_bytes(process.stdout)
    (out / f"{label}.stderr").write_bytes(process.stderr)
    assert process.returncode == expected, (label, process.returncode, process.stderr.decode())
    if expected:
        assert process.stderr and not process.stdout, label
    receipts.append(dict(case=label, args=list(map(str, args)), exit=process.returncode,
                         stdout_sha256=digest(process.stdout), stderr_sha256=digest(process.stderr)))
    return process.stdout


args = [first, second, "--artifacts", manifest_path, "--run", "report-run"]
result = json.loads(invoke("joined", args))
assert result["schema"] == "moonclaw.run-review.v1" and result["job_id"] == "job-report"
assert [e["record"]["message"] for e in result["events"]] == ["first observation", "same-time second file", "later progress", second_events[1]["message"]]
assert [e["line"] for e in result["events"]] == [4, 1, 2, 2]
assert [e["entry"]["record"]["id"] for e in result["artifacts"]] == ["old", "new"]
assert [e["index"] for e in result["artifacts"]] == [1, 3]
assert result["events"][0]["record"] == first_events[2]
assert result["artifacts"][1]["entry"] == artifacts[2]
assert result["excluded_events"] == 1 and result["excluded_artifacts"] == 1
assert result["content_verification"] == "not_checked"
assert json.loads(invoke("repeat", args)) == result
md = invoke("markdown", [*args, "--markdown"]).decode()
assert "revision 1" in md and "revision 2" in md and "Archived" in md and "Unknown" in md
assert "<script>" not in md and "[x](https://bad.invalid)" not in md
links = re.findall(r"\[(?:Open exported content|Original record)\]\(([^)]+)\)", md)
assert links == ["files/1-report.txt", "records/1.json", "files/3-report.txt", "records/3.json"]
for link in links:
    assert (packet / link).is_file()
# Keep the practical Markdown beside its manifest so a reviewer can open links.
(packet / "run-review.md").write_text(md)
verified = subprocess.run(["sha256sum", "-c", "SHA256SUMS"], cwd=packet, capture_output=True)
assert verified.returncode == 0, verified.stderr
(out / "external-checksums.stdout").write_bytes(verified.stdout)
artifact_only = json.loads(invoke("artifact-only", [empty, "--artifacts", manifest_path, "--run", "report-run"]))
assert not artifact_only["events"] and len(artifact_only["artifacts"]) == 2
journal_only_file = inputs / "journal-only.jsonl"
journal_only_file.write_text(json.dumps(event("only-journal", 1, "no output supplied")) + "\n")
journal_only = json.loads(invoke("journal-only", [journal_only_file, "--artifacts", manifest_path, "--run", "only-journal"]))
assert not journal_only["artifacts"] and len(journal_only["events"]) == 1
for label, variant_args in [("missing-run", [*args[:-1], "absent"]), ("blank-run", [*args[:-1], " "]),
    ("duplicate-file", [first, *args]), ("duplicate-option", [*args, "--run", "report-run"]),
    ("unknown-option", [*args, "--unknown"]), ("missing-file", [inputs / "missing", *args[2:]]),
    ("missing-value", [first, "--run"]), ("no-journal", args[2:]), ("duplicate-markdown", [*args, "--markdown", "--markdown"])]:
    invoke(label, variant_args, 1)
conflict = inputs / "conflict.jsonl"
conflict.write_text(json.dumps(event("report-run", 1, "conflict", job="wrong-job")) + "\n")
invoke("job-conflict", [conflict, *args[2:]], 1)
malformed = inputs / "malformed.jsonl"
malformed.write_text(json.dumps(event("other-run", 1, "other")) + "\n{partial")
invoke("malformed-unselected", [malformed, *args[2:]], 1)
mutations = {
    "fractional-version": lambda m: m["artifacts"][1]["record"].update(version=1.5),
    "fractional-created": lambda m: m["artifacts"][1]["record"].update(created_at=1.5),
    "fractional-total": lambda m: m.update(total_content_bytes=m["total_content_bytes"] + .5),
    "wrong-schema": lambda m: m.update(schema="unsupported"),
    "unsafe-link": lambda m: m["artifacts"][1].update(content_path="https://bad.invalid"),
    "duplicate-id": lambda m: m["artifacts"][1]["record"].update(id="old"),
    "wrong-digest": lambda m: m["artifacts"][1].update(content_sha256="bad"),
    "wrong-total": lambda m: m.update(total_content_bytes=0),
}
for label, mutate in mutations.items():
    value = copy.deepcopy(manifest)
    mutate(value)
    path = inputs / f"{label}.json"
    write_json(path, value)
    invoke(label, [first, "--artifacts", path, "--run", "report-run"], 1)
# No content reads are implied: a detached manifest with no adjacent files
# remains a metadata-only report and states that its bytes were not checked.
detached = inputs / "detached-manifest.json"
write_json(detached, manifest)
unchecked = json.loads(invoke("metadata-only", [first, second, "--artifacts", detached, "--run", "report-run"]))
assert unchecked["content_verification"] == "not_checked"
assert [a["entry"] for a in unchecked["artifacts"]] == [a["entry"] for a in result["artifacts"]]
invoke("help", ["--help"])
invoke("usage", [], 1)
write_json(out / "cli-receipts.json", receipts)
write_json(out / "input-hashes.json", snapshot())
print(f"{len(receipts)} native CLI cases passed; relative links resolved, external checksums passed, and detached manifests stayed explicitly unverified")
