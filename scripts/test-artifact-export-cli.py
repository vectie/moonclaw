#!/usr/bin/env python3
"""Check the compiled local exporter and portable outputs using synthetic records."""
import hashlib
import json
import pathlib
import shutil
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


def artifact(name, data, *, filename="report.txt", **changes):
    folder = store / "artifacts" / name
    folder.mkdir(parents=True)
    content = folder / filename
    content.write_bytes(data)
    record = dict(id=name, run_id="run-" + name, job_id="job-output", artifact_type="result",
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
    "old": artifact("old", b"\xef\xbb\xbfline one\r\n", status="Archived"),
    "new": artifact("new", "line two 🌙\n".encode(), version=2),
    "binary": artifact("binary", b"\x89PNG\r\n\x00\xff\xfe", filename="image.bin",
                       job_id="different-job", content_type="image/png"),
    "empty": artifact("empty", b"", filename="same 🌙.txt"),
    "collision": artifact("collision", b"x", filename="same 🌙.txt"),
}
(store / "index").mkdir()
(store / "index" / "artifacts.json").write_text("{broken index")
export = out / "selected"
manifest = json.loads(execute("selected", [store, export, *fixtures]))
assert manifest["schema"] == "moonclaw.artifact-export.v1"
assert manifest["total_content_bytes"] == sum(len(v[2]) for v in fixtures.values())
assert json.loads((export / "manifest.json").read_bytes()) == manifest
assert len(manifest["artifacts"]) == len(fixtures)
for entry, (name, (record, raw, data)) in zip(manifest["artifacts"], fixtures.items()):
    assert entry["record"]["id"] == name
    assert entry["record"]["run_id"] == record["run_id"]
    assert entry["record"]["version"] == record["version"]
    assert (export / entry["content_path"]).read_bytes() == data
    assert (export / entry["record_path"]).read_bytes() == raw
    assert entry["content_sha256"] == digest(data)
    assert entry["record_sha256"] == digest(raw)
    assert entry["content_bytes"] == len(data)
paths = [e["content_path"] for e in manifest["artifacts"]]
assert len(set(paths)) == len(paths)
assert "files/4-same__.txt" in paths and "files/5-same__.txt" in paths
readme = (export / "README.txt").read_text()
assert "revision 2" in readme and "Archived" in readme and "sha256sum -c SHA256SUMS" in readme

# Relocation and verification need neither MoonClaw nor a source-store path.
portable = out / "relocated-copy"
shutil.copytree(export, portable)
verification = subprocess.run(["sha256sum", "-c", "SHA256SUMS"], cwd=portable, capture_output=True)
assert verification.returncode == 0, verification.stderr
(out / "portable-checksums.stdout").write_bytes(verification.stdout)
# Keep the original intact; show external checksum verification detects changed content.
(portable / paths[0]).write_bytes(b"changed review copy")
changed = subprocess.run(["sha256sum", "-c", "SHA256SUMS"], cwd=portable, capture_output=True)
assert changed.returncode == 1
(out / "changed-copy-checksums.stdout").write_bytes(changed.stdout)
(out / "changed-copy-checksums.stderr").write_bytes(changed.stderr)

# Repeat into a new folder is byte deterministic; reusing any destination is refused.
repeat = out / "repeat"
assert json.loads(execute("repeat", [store, repeat, *fixtures])) == manifest
for p in export.rglob("*"):
    if p.is_file():
        assert p.read_bytes() == (repeat / p.relative_to(export)).read_bytes()
execute("existing-export", [store, export, "old"], 1)
execute("inside-store", [store, store / "export", "old"], 1)
assert not (store / "export").exists()
# A parent symlink pointing into the source cannot make an in-store export.
(out / "store-alias").symlink_to(store, target_is_directory=True)
execute("inside-store-alias", [store, out / "store-alias" / "export", "old"], 1)
existing = out / "existing.txt"
existing.write_bytes(b"keep")
execute("existing-file", [store, existing, "old"], 1)
assert existing.read_bytes() == b"keep"
for label, ids in [("duplicate", ["old", "old"]), ("missing", ["old", "absent"]),
                   ("traversal", ["../old"]), ("too-many", ["old"] * 33)]:
    dest = out / ("reject-" + label)
    execute(label, [store, dest, *ids], 1)
    assert not dest.exists()
for name, changes in [("wrong-id", {"id": "another"}), ("fractional", {"version": 1.5}),
                      ("outside", {"path": fixtures["old"][0]["path"]}),
                      ("missing-content", {"path": str(store / "artifacts/missing-content/absent")})]:
    artifact(name, b"x", **changes)
    dest = out / ("reject-" + name)
    execute(name, [store, dest, "old", name], 1)
    assert not dest.exists()
artifact("malformed", b"x")
(store / "artifacts/malformed/record.json").write_text("{broken")
artifact("deleted", b"x")
(store / "index/deleted-artifacts").mkdir()
(store / "index/deleted-artifacts/deleted.json").write_text("{}")
artifact("large", b"")
with (store / "artifacts/large/report.txt").open("wb") as f:
    f.seek(16777216)
    f.write(b"x")
for name in ["malformed", "deleted", "large"]:
    dest = out / ("reject-" + name)
    execute(name, [store, dest, name], 1)
    assert not dest.exists()
execute("help", ["--help"])
execute("usage", [], 1)
execute("missing-selection", [store, out / "empty-selection"], 1)
(out / "cli-receipts.json").write_text(json.dumps(receipts, indent=2) + "\n")
(out / "fixture-hashes.json").write_text(json.dumps(snapshot(), indent=2) + "\n")
print(f"{len(receipts)} native CLI invocations passed; portable checksums passed and detected a changed copy")
