#!/usr/bin/env python3
"""Compiled portable export -> relocate -> import -> inspect -> export workflow.
Fixtures are synthetic, retained, provider-free and never deleted.
"""
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys

build = pathlib.Path(sys.argv[1]).resolve()
out = pathlib.Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=False)
receipts = []


def digest(data):
    return "sha256:" + hashlib.sha256(data).hexdigest()


def snapshot(root):
    return {str(p.relative_to(root)): digest(p.read_bytes())
            for p in root.rglob("*") if p.is_file() and not p.is_symlink()}


def execute(label, tool, args, expected=0):
    binary = build / "native/debug/build/cmd" / tool / (tool + ".exe")
    result = subprocess.run([str(binary), *map(str, args)], capture_output=True)
    (out / (label + ".stdout")).write_bytes(result.stdout)
    (out / (label + ".stderr")).write_bytes(result.stderr)
    receipts.append(dict(case=label, tool=tool, args=list(map(str, args)),
                         exit=result.returncode, stdout_sha256=digest(result.stdout),
                         stderr_sha256=digest(result.stderr)))
    (out / "cli-receipts.json").write_text(json.dumps(receipts, indent=2) + "\n")
    assert result.returncode == expected, (label, result.returncode, result.stderr)
    if expected:
        assert not result.stdout and result.stderr, label
        return None
    return json.loads(result.stdout) if result.stdout.startswith(b"{") else result.stdout


producer = out / "producer"
fixtures = {}
for i, (id, data, mime) in enumerate([
    ("old", b"draft\r\n", "text/plain"),
    ("new", "ready 🌙\nexact result\n".encode(), "text/plain"),
    ("binary", b"\x00\xff\xfe\x80\r\n", "application/octet-stream"),
    ("empty", b"", "text/plain"),
]):
    directory = producer / "artifacts" / id
    directory.mkdir(parents=True)
    path = directory / "report 🌙.txt"
    path.write_bytes(data)
    record = dict(id=id, job_id="job-output", run_id="run-" + id,
                  artifact_type="report", logical_key="review", version=i + 1,
                  status="Archived" if id == "old" else "Active", path=str(path),
                  content_type=mime, metadata={"fixture": "synthetic producer"},
                  created_at=123, archived_at=124 if id == "old" else None,
                  scope=["inspection"], future_field={"preserve": ["🌙", 7]})
    if record["archived_at"] is None:
        record.pop("archived_at")
    raw = (json.dumps(record, indent=2, ensure_ascii=False) + "\n").encode()
    (directory / "record.json").write_bytes(raw)
    fixtures[id] = (record, raw, data)
producer_before = snapshot(producer)
packet_before_move = out / "export-before-copy"
manifest = execute("export", "export_artifacts", [producer, packet_before_move, *fixtures])
assert snapshot(producer) == producer_before
packet = out / "received-packet"
shutil.copytree(packet_before_move, packet)
# Make original absolute content paths genuinely unavailable without deleting them.
producer.rename(out / "producer-retained-offline")
packet_before = snapshot(packet)
inspection = out / "inspection"
result = execute("import", "import_artifacts", [packet, inspection])
assert result["schema"] == "moonclaw.artifact-import.v1"
assert result["source_manifest_sha256"] == digest((packet / "manifest.json").read_bytes())
assert json.loads((inspection / "import.json").read_bytes()) == result
assert (inspection / "provenance/manifest.json").read_bytes() == (packet / "manifest.json").read_bytes()
for entry in result["artifacts"]:
    record, original, data = fixtures[entry["record"]["id"]]
    assert {k: v for k, v in entry["record"].items() if k != "path"} == {
        k: v for k, v in manifest["artifacts"][list(fixtures).index(record["id"])]["record"].items()
        if k != "path"}
    stored = inspection / "artifacts" / record["id"] / "record.json"
    actual_record = json.loads(stored.read_bytes())
    assert actual_record == {**record, "path": str(inspection / "artifacts" / record["id"] / "content.bin")}
    assert pathlib.Path(actual_record["path"]).read_bytes() == data
    assert (inspection / entry["original_record_path"]).read_bytes() == original
    assert entry["record_sha256"] == digest(stored.read_bytes())
    assert entry["original_record_sha256"] == digest(original)
    assert entry["content_sha256"] == digest(data)
assert not (inspection / "definitions.json").exists() and not (inspection / "index").exists()
inspection_before = snapshot(inspection)
search = execute("search", "search_artifacts", [inspection, "--text", "ready 🌙"])["search"]
assert search["matching_artifacts"] == 1 and search["matches"][0]["record"]["id"] == "new"
assert not search["issues"]
text = execute("inspect-text", "search_artifacts", [inspection, "--format", "text"])
assert b"revision 2" in text and b"Archived" in text and b"Runtime evidence only" in text
compared = execute("compare", "compare_artifacts", [inspection, "old", "new"])
assert compared["left"]["content_sha256"] == digest(fixtures["old"][2])
assert compared["right"]["content_sha256"] == digest(fixtures["new"][2])
selected = out / "selected-again"
selection = execute("search-export", "search_artifacts", [inspection, "--text", "ready 🌙", "--export", selected])
assert selection["export"]["artifacts"][0]["content_sha256"] == digest(fixtures["new"][2])
reexported = out / "all-again"
roundtrip = execute("reexport", "export_artifacts", [inspection, reexported, *fixtures])
assert [e["content_sha256"] for e in roundtrip["artifacts"]] == [e["content_sha256"] for e in manifest["artifacts"]]
check = subprocess.run(["sha256sum", "-c", "SHA256SUMS"], cwd=reexported, capture_output=True)
(out / "reexport-checksums.stdout").write_bytes(check.stdout)
assert check.returncode == 0, check.stderr
assert snapshot(inspection) == inspection_before and snapshot(packet) == packet_before
execute("reuse-destination", "import_artifacts", [packet, inspection], 1)
assert snapshot(inspection) == inspection_before
execute("nested-destination", "import_artifacts", [packet, packet / "nested"], 1)
assert not (packet / "nested").exists()
# Independent packet variants demonstrate whole-input validation before output.
mutations = [
    ("unknown-schema", lambda m: m.update(schema="other.v1")),
    ("empty-selection", lambda m: m.update(artifacts=[])),
    ("too-many", lambda m: m.update(artifacts=m["artifacts"] * 9)),
    ("fractional-total", lambda m: m.update(total_content_bytes=m["total_content_bytes"] + .5)),
    ("incorrect-total", lambda m: m.update(total_content_bytes=m["total_content_bytes"] + 1)),
    ("oversized-total", lambda m: m.update(total_content_bytes=67108865)),
    ("fractional-length", lambda m: m["artifacts"][1].update(content_bytes=1.5)),
    ("oversized-content", lambda m: m["artifacts"][1].update(content_bytes=16777217)),
    ("negative-length", lambda m: m["artifacts"][1].update(content_bytes=-1)),
    ("wrong-length", lambda m: m["artifacts"][1].update(content_bytes=1)),
    ("traversal", lambda m: m["artifacts"][1].update(content_path="../outside")),
    ("absolute-member", lambda m: m["artifacts"][1].update(record_path="/etc/passwd")),
    ("record-digest", lambda m: m["artifacts"][1].update(record_sha256="sha256:" + "0" * 64)),
    ("content-digest", lambda m: m["artifacts"][1].update(content_sha256="sha256:" + "0" * 64)),
    ("record-conflict", lambda m: m["artifacts"][1]["record"].update(job_id="different-job")),
    ("fractional-version", lambda m: m["artifacts"][1]["record"].update(version=2.5)),
    ("duplicate-id", lambda m: m["artifacts"][1]["record"].update(id="old")),
]
for label, change in mutations:
    variant = out / ("packet-" + label)
    shutil.copytree(packet, variant)
    altered = json.loads((variant / "manifest.json").read_bytes())
    change(altered)
    (variant / "manifest.json").write_text(json.dumps(altered))
    destination = out / ("refused-" + label)
    before = snapshot(variant)
    execute(label, "import_artifacts", [variant, destination], 1)
    assert not destination.exists() and snapshot(variant) == before
# Exact content/record corruption, missing members and external symlink member.
for label, member in [("changed-content", manifest["artifacts"][1]["content_path"]),
                      ("changed-record", manifest["artifacts"][1]["record_path"]),
                      ("missing-member", manifest["artifacts"][1]["content_path"]),
                      ("outside-symlink", manifest["artifacts"][1]["content_path"])]:
    variant = out / ("packet-" + label)
    shutil.copytree(packet, variant)
    file = variant / member
    if label.startswith("changed"):
        file.write_bytes(file.read_bytes() + b"x")
    else:
        file.rename(file.with_name(file.name + ".retained"))
        if label == "outside-symlink":
            file.symlink_to(packet / member)
    destination = out / ("refused-" + label)
    execute(label, "import_artifacts", [variant, destination], 1)
    assert not destination.exists()
# A valid original record at the byte ceiling can grow when its path relocates.
variant = out / "packet-relocated-record-limit"
shutil.copytree(packet, variant)
altered = json.loads((variant / "manifest.json").read_bytes())
entry = altered["artifacts"][0]
record = json.loads((variant / entry["record_path"]).read_bytes())
record["path"] = "/x"
record["metadata"] = {"padding": ""}
encode = lambda value: json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()
record["metadata"]["padding"] = "x" * (262144 - len(encode(record)))
raw = encode(record)
assert len(raw) == 262144
(variant / entry["record_path"]).write_bytes(raw)
shutil.copyfile(variant / entry["content_path"], variant / "files/1-x")
entry.update(record=record, record_sha256=digest(raw), content_path="files/1-x")
(variant / "manifest.json").write_bytes(encode(altered))
execute("relocated-record-limit", "import_artifacts", [variant, out / "refused-relocated-record-limit"], 1)
assert not (out / "refused-relocated-record-limit").exists()
execute("usage", "import_artifacts", [], 1)
execute("missing-packet", "import_artifacts", [out / "absent", out / "never-created"], 1)
execute("help", "import_artifacts", ["--help"])
assert snapshot(packet) == packet_before
print(f"Passed {len(receipts)} compiled command scenarios; all fixtures retained in {out}")
