#!/usr/bin/env python3
"""Exercise the native offline search-to-export workflow on synthetic saved files.
All input/output fixtures and command results are retained; no cleanup is done.
"""
import hashlib
import json
import pathlib
import subprocess
import sys

binary = pathlib.Path(sys.argv[1]).resolve()
out = pathlib.Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=False)
store = out / "store"
store.mkdir()
receipts = []


def digest(data):
    return "sha256:" + hashlib.sha256(data).hexdigest()


def artifact(name, data, **changes):
    folder = store / "artifacts" / name
    folder.mkdir(parents=True)
    content = folder / "report.txt"
    content.write_bytes(data)
    record = dict(id=name, run_id="run-" + name, job_id="job-output", artifact_type="report",
                  logical_key="release", version=1, status="Active", path=str(content),
                  content_type="text/plain", metadata={"fixture": "synthetic local input"},
                  created_at=123, scope=["review"], future_field={"preserved": True})
    record.update(changes)
    raw = (json.dumps(record, ensure_ascii=False, indent=2) + "\n").encode()
    (folder / "record.json").write_bytes(raw)
    return record, raw, data


def snapshot():
    return {str(p.relative_to(store)): digest(p.read_bytes())
            for p in store.rglob("*") if p.is_file()}


def execute(label, args, expected=0):
    before = snapshot()
    result = subprocess.run([str(binary), *map(str, args)], capture_output=True)
    assert snapshot() == before, f"{label}: source store changed"
    (out / (label + ".stdout")).write_bytes(result.stdout)
    (out / (label + ".stderr")).write_bytes(result.stderr)
    assert result.returncode == expected, (label, result.returncode, result.stderr)
    if expected:
        assert not result.stdout and result.stderr, label
    receipts.append(dict(case=label, exit=result.returncode,
                         stdout_sha256=digest(result.stdout), stderr_sha256=digest(result.stderr)))
    return result.stdout


fixtures = {
    "a-old": artifact("a-old", "before\r\nrelease ready 🌙\r\n".encode(), status="Archived"),
    "b-new": artifact("b-new", "release ready 🌙\nrelease ready again\n".encode(), version=2),
    "c-other": artifact("c-other", b"release ready\n", job_id="other-job"),
    "d-binary": artifact("d-binary", b"\x00\xff", content_type="image/png"),
    "e-empty": artifact("e-empty", b""),
}
(store / "index").mkdir()
(store / "index" / "artifacts.json").write_text("{broken index")
query = [store, "--job", "job-output", "--text", "release ready"]
result = json.loads(execute("search", query))
s = result["search"]
assert s["schema"] == "moonclaw.artifact-search.v1"
assert [m["record"]["id"] for m in s["matches"]] == ["a-old", "b-new"]
assert s["matching_artifacts"] == 2 and not s["truncated"] and not s["issues"]
assert s["excluded_nontext"] == 1
assert s["matches"][0]["lines"][0]["line"] == 2
assert s["matches"][1]["matching_lines"] == 2
assert result["export"] is None
text = execute("text", query + ["--format", "text"]).decode()
assert "line 2:" in text and "revision 2" in text and "Runtime evidence only" in text
selection = out / "selected"
output = json.loads(execute("search-export", query + ["--export", selection]))
assert output["search"] == s
manifest = output["export"]
assert json.loads((selection / "manifest.json").read_bytes()) == manifest
for hit, entry in zip(s["matches"], manifest["artifacts"]):
    assert hit["record"]["id"] == entry["record"]["id"]
    assert hit["content_sha256"] == entry["content_sha256"]
    assert hit["record_sha256"] == entry["record_sha256"]
    fixture = fixtures[entry["record"]["id"]]
    assert (selection / entry["record_path"]).read_bytes() == fixture[1]
    assert (selection / entry["content_path"]).read_bytes() == fixture[2]
verification = subprocess.run(["sha256sum", "-c", "SHA256SUMS"], cwd=selection, capture_output=True)
assert verification.returncode == 0, verification.stderr
(out / "export-checksums.stdout").write_bytes(verification.stdout)

catalog = json.loads(execute("catalog", [store]))["search"]
assert catalog["matching_artifacts"] == 5
assert catalog["excluded_nontext"] == 0
assert catalog["matches"][3]["content_bytes"] == 2
filtered = json.loads(execute("exact-filters", [store, "--job", "job-output", "--run", "run-b-new",
                             "--type", "report", "--key", "release", "--scope", "review",
                             "--status", "active"]))["search"]
assert [m["record"]["id"] for m in filtered["matches"]] == ["b-new"]
archived = json.loads(execute("archived", [store, "--status", "archived"]))["search"]
assert [m["record"]["id"] for m in archived["matches"]] == ["a-old"]
assert json.loads(execute("case-sensitive", [store, "--text", "Release"]))["search"]["matching_artifacts"] == 0
assert json.loads(execute("literal", [store, "--text", "ready.*"]))["search"]["matching_artifacts"] == 0
limited = json.loads(execute("limited", query + ["--limit", "1"]))["search"]
assert limited["truncated"] and limited["matching_artifacts"] == 2 and len(limited["matches"]) == 1
for label, options in [
    ("truncated-export", query + ["--limit", "1"]),
    ("empty-export", [store, "--text", "no-such-output"]),
]:
    destination = out / label
    execute(label, options + ["--export", destination], 1)
    assert not destination.exists()
execute("destination-exists", query + ["--export", selection], 1)
execute("export-inside-source", query + ["--export", store / "export"], 1)
assert not (store / "export").exists()

artifact("e-json", '{"message":"invoice 🌙"}'.encode(), content_type="Application/Vnd.Example+Json; charset=utf-8")
json_hit = json.loads(execute("json-mime", [store, "--text", "invoice 🌙"]))["search"]
assert [m["record"]["id"] for m in json_hit["matches"]] == ["e-json"]
empty_store = out / "empty-store"
empty_store.mkdir()
assert json.loads(execute("empty-store", [empty_store]))["search"]["matching_artifacts"] == 0
# Damaged records and content remain visible as incomplete-search issues.
artifact("f-bad-utf8", b"\xff")
artifact("g-missing", b"x", path=str(store / "artifacts/g-missing/absent"))
artifact("h-malformed", b"x")
(store / "artifacts/h-malformed/record.json").write_text("{broken")
artifact("i-deleted", b"release ready")
(store / "index/deleted-artifacts").mkdir()
(store / "index/deleted-artifacts/i-deleted.json").write_text("{}")
partial = json.loads(execute("partial", query))["search"]
assert partial["matching_artifacts"] == 2 and partial["deleted_records"] == 1
assert {i["artifact_id"] for i in partial["issues"]} == {"f-bad-utf8", "g-missing", "h-malformed"}
execute("partial-export", query + ["--export", out / "incomplete"], 1)
assert not (out / "incomplete").exists()
artifact("j-large", b"")
with (store / "artifacts/j-large/report.txt").open("wb") as f:
    f.seek(16777216)
    f.write(b"x")
large = json.loads(execute("large", query))["search"]
assert "j-large" in {i["artifact_id"] for i in large["issues"]}
# Escaping is exercised using the actual executable, not a separately rendered fixture.
artifact("k-control", b"needle\x1b[31m\n", job_id="fake\nrow")
escaped = execute("escaped", [store, "--text", "needle", "--format", "text"])
assert b"\x1b" not in escaped and b"fake\nrow" not in escaped
for label, args in [
    ("unknown-option", [store, "--unknown", "x"]),
    ("duplicate-option", [store, "--text", "a", "--text", "b"]),
    ("missing-value", [store, "--text"]),
    ("empty-text", [store, "--text", ""]),
    ("multiline", [store, "--text", "a\nb"]),
    ("invalid-status", [store, "--status", "completed"]),
    ("invalid-limit", [store, "--limit", "33"]),
    ("missing-root", [out / "missing"]),
    ("usage", []),
]:
    execute(label, args, 1)
execute("help", ["--help"])
# Sparse synthetic data proves the total-read ceiling and the useful narrowing path.
original_store = store
store = out / "bounds-store"
store.mkdir()
for i in range(4):
    record, _, _ = artifact(f"large-{i}", b"", job_id="large")
    with pathlib.Path(record["path"]).open("wb") as f:
        f.truncate(16777216)
artifact("tiny", b"x", job_id="small")
execute("total-read-limit", [store], 1)
small = json.loads(execute("narrow-large-store", [store, "--job", "small"]))["search"]
assert small["matching_artifacts"] == 1 and small["matches"][0]["content_bytes"] == 1
store = original_store
crowded = out / "crowded-store"
(crowded / "artifacts").mkdir(parents=True)
for i in range(2049):
    (crowded / "artifacts" / str(i)).touch()
execute("directory-entry-limit", [crowded], 1)
assert len(list((crowded / "artifacts").iterdir())) == 2049
(out / "cli-receipts.json").write_text(json.dumps(receipts, indent=2) + "\n")
(out / "fixture-hashes.json").write_text(json.dumps(snapshot(), indent=2) + "\n")
print(f"{len(receipts)} native CLI invocations passed; exact matched export checksums passed")
