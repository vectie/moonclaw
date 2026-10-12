#!/usr/bin/env python3
"""Exercise the actual native command with producer-shaped, local-only fixtures."""
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

def artifact(name, content, version=1, **changes):
    directory = store / "artifacts" / name
    directory.mkdir(parents=True)
    path = directory / "content.txt"
    path.write_bytes(content)
    record = dict(id=name, run_id="run-" + name, job_id="job-review",
                  artifact_type="report", logical_key="result", version=version,
                  status="Active", path=str(path), content_type="text/plain",
                  metadata={"fixture": "synthetic producer-shaped input"},
                  created_at=version * 100, scope=[])
    record.update(changes)
    (directory / "record.json").write_text(json.dumps(record), encoding="utf-8")
    return record

def execute(label, args, expected=0):
    retained_before = {str(p): digest(p.read_bytes()) for p in store.rglob("*") if p.is_file()}
    result = subprocess.run([str(binary), *map(str, args)], capture_output=True)
    assert {str(p): digest(p.read_bytes()) for p in store.rglob("*") if p.is_file()} == retained_before, label
    (out / (label + ".stdout")).write_bytes(result.stdout)
    (out / (label + ".stderr")).write_bytes(result.stderr)
    assert result.returncode == expected, (label, result.returncode, result.stderr)
    if expected:
        assert result.stdout == b"" and result.stderr, label
    receipts.append(dict(case=label, exit=result.returncode,
                         stdout_sha256=digest(result.stdout),
                         stderr_sha256=digest(result.stderr)))
    return result.stdout

before = "# Review\nOld\nStable\n".encode()
after = "# Review\nNew 🌙\nStable\nAdded".encode()
a = artifact("old", before)
b = artifact("new", after, 2)
# A bad index is intentional: comparison must neither use nor rewrite it.
(store / "index").mkdir()
(store / "index" / "artifacts.json").write_text("{bad cache")

initial = {str(p): digest(p.read_bytes()) for p in store.rglob("*") if p.is_file()}
first = execute("forward", [store, "old", "new"])
result = json.loads(first)
assert result["left"]["record"] == a and result["right"]["record"] == b
assert result["left"]["content_sha256"] == digest(before)
assert result["right"]["content_sha256"] == digest(after)
assert result["right"]["content_bytes"] == len(after)
assert result["diff"]["added_lines"] == 2
assert result["diff"]["removed_lines"] == 1
assert result["diff"]["unchanged_lines"] == 2
assert execute("repeat", [store, "old", "new"]) == first
reverse = json.loads(execute("reverse", [store, "new", "old"]))
assert reverse["diff"]["added_lines"] == 1 and reverse["diff"]["removed_lines"] == 2
same = json.loads(execute("identical", [store, "old", "old"]))
assert same["diff"]["identical"] is True
markdown = execute("markdown", [store, "old", "new", "--markdown"]).decode()
assert "version 2" in markdown and "no final newline" in markdown
assert "Right line 2 added" in markdown
assert {str(p): digest(p.read_bytes()) for p in store.rglob("*") if p.is_file()} == initial

artifact("empty", b"", 3)
artifact("lf", b"a\n", 4)
artifact("crlf", b"a\r\n", 5)
artifact("no-final", b"a", 6)
artifact("bom", b"\xef\xbb\xbfa\n", 7)
assert json.loads(execute("empty", [store, "empty", "empty"]))["diff"]["left_lines"] == 0
assert json.loads(execute("ending", [store, "crlf", "lf"]))["diff"]["removed_lines"] == 1
assert json.loads(execute("final-newline", [store, "no-final", "lf"]))["diff"]["identical"] is False
assert json.loads(execute("bom", [store, "bom", "lf"]))["diff"]["identical"] is False
artifact("inert", b"<script>x</script>\n![x](https://example.test)\n", 8)
escaped = execute("inert", [store, "empty", "inert", "--markdown"]).decode()
assert "<script>" not in escaped and "![x](" not in escaped and "&lt;script&gt;" in escaped
artifact("invalid-utf8", b"\xff", 9)
artifact("nul", b"a\x00b", 10)
artifact("binary", b"not a PNG", 11, content_type="image/png")
artifact("other", b"different", 12, logical_key="another-output")
artifact("fractional", b"x", 1.5)
artifact("oversize", b"x" * 1048577, 13)
artifact("too-many-lines", b"a\n" * 2001, 14)
artifact("wrong-id", b"x", 15, id="different-id")
artifact("missing-content", b"x", 16, path=str(store / "absent.txt"))
artifact("outside", b"x", 17, path=a["path"])
artifact("deleted", b"x", 18)
(store / "index" / "deleted-artifacts").mkdir()
(store / "index" / "deleted-artifacts" / "deleted.json").write_text("{}")
artifact("malformed", b"x", 19)
(store / "artifacts" / "malformed" / "record.json").write_text("{broken")
for name in ["invalid-utf8", "nul", "binary", "other", "fractional", "oversize",
             "too-many-lines", "wrong-id", "missing-content", "outside", "deleted",
             "malformed", "absent"]:
    execute("reject-" + name, [store, "old", name], 1)
execute("reject-traversal", [store, "../old", "new"], 1)
execute("reject-arguments", [], 1)
execute("reject-option", [store, "old", "new", "--unknown"], 1)
execute("help", ["--help"])

final = {str(p.relative_to(out)): digest(p.read_bytes())
         for p in store.rglob("*") if p.is_file()}
(out / "fixture-hashes.json").write_text(json.dumps(final, indent=2) + "\n")
(out / "cli-receipts.json").write_text(json.dumps(receipts, indent=2) + "\n")
print(f"{len(receipts)} native CLI invocations passed; fixture bytes retained in {out}")
