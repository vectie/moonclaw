#!/usr/bin/env python3
"""Retained native HTML-report smoke. Supply absolute build and new evidence paths."""
import hashlib
import json
import subprocess
import sys
from html.parser import HTMLParser
from pathlib import Path

target, out = map(Path, sys.argv[1:])
assert target.is_absolute() and out.is_absolute()
exe = target / "native/debug/build/cmd/run_report/run_report.exe"
assert exe.is_file(), exe
out.mkdir(parents=True, exist_ok=False)


class Report(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids, self.links, self.tags, self.pres, self.rows = [], [], [], [], []
        self.pre = None
        self.row = None
        self.cell = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        self.tags.append(tag)
        if "id" in attrs:
            self.ids.append(attrs["id"])
        if "href" in attrs:
            self.links.append(attrs["href"])
        assert "src" not in attrs
        assert not any(a.startswith("on") for a in attrs)
        if tag == "pre":
            self.pre = ""
        if tag == "tr":
            self.row = []
        if tag in ("td", "th") and self.row is not None:
            self.cell = ""

    def handle_data(self, data):
        if self.pre is not None:
            self.pre += data
        if self.cell is not None:
            self.cell += data

    def handle_endtag(self, tag):
        if tag == "pre":
            self.pres.append(self.pre)
            self.pre = None
        if tag in ("td", "th") and self.cell is not None:
            self.row.append(self.cell)
            self.cell = None
        if tag == "tr":
            self.rows.append(self.row)
            self.row = None


calls = []


def invoke(name, args, success=True):
    result = subprocess.run([str(exe), *map(str, args)], capture_output=True)
    (out / (name + ".stdout")).write_bytes(result.stdout)
    (out / (name + ".stderr")).write_bytes(result.stderr)
    calls.append({"name": name, "args": list(map(str, args)), "exit": result.returncode})
    (out / "calls.json").write_text(json.dumps(calls, indent=2) + "\n")
    assert result.returncode == (0 if success else 1), (name, result.stderr)
    if not success:
        assert not result.stdout and result.stderr, name
    return result.stdout


def event(timestamp, message, **extra):
    return dict(job_id="job", run_id="shared", timestamp=timestamp,
                event_type="observed", message=message, data=None, **extra)


first = event(-2147483648, "雪 <&>\n</pre><script>literal</script>",
              status={"Unknown": {"detail": "<future>"}}, future=[1, None])
step = event(0, "Completed is only a recorded step status", step_id="", status="Completed")
unrecorded = event(0, "A step without a status", step_id="Run-level")
last = event(2147483647, "Final observation", status=None, step_id=None)
other = dict(event(0, "EXCLUDED OTHER JOB"), job_id="other")
one = out / "first<&.jsonl"
two = out / "second.jsonl"
one.write_text("\n" + "\n".join(json.dumps(x, ensure_ascii=False)
                              for x in [last, other, step, first]) + "\n")
two.write_text("\n".join(json.dumps(x) for x in [unrecorded, step]) + "\n")
before = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [one, two]}
args = [one, two, "--job", "job", "--run", "shared"]
raw = invoke("report", args)
(out / "report.html").write_bytes(raw)
parsed = Report()
parsed.feed(raw.decode())
assert raw.decode().startswith("<!doctype html>")
assert "script" not in parsed.tags and "iframe" not in parsed.tags
assert "link" not in parsed.tags and "form" not in parsed.tags
assert parsed.tags.count("details") == 5
assert len(parsed.ids) == len(set(parsed.ids))
assert all(link.startswith("#") and link[1:] in parsed.ids for link in parsed.links)
assert [json.loads(v) for v in parsed.pres[1::2]] == [first, step, unrecorded, step, last]
assert parsed.pres[0] == first["message"]
assert parsed.rows[1][0] == "Run-level" and parsed.rows[1][3] == "null"
assert parsed.rows[1][4] == "observation 5"
assert "span 4294967295" in parsed.rows[1][2]
assert parsed.rows[2][0] == 'Step ""' and parsed.rows[2][1] == "2"
assert parsed.rows[2][3] == '"Completed"'
assert parsed.rows[3][0] == 'Step "Run-level"'
assert parsed.rows[3][3] == "not recorded" and parsed.rows[3][4] == ""
assert "EXCLUDED OTHER JOB" not in raw.decode()
assert "physical line 5" in raw.decode()
assert invoke("repeat", args) == raw
assert b"Usage: run_report" in invoke("help", ["--help"])
invoke("missing-pair", [one, "--job", "absent", "--run", "shared"], False)
invoke("missing-job", [one, "--run", "shared"], False)
invoke("missing-value", [one, "--job"], False)
invoke("repeated-option", args + ["--run", "shared"], False)
invoke("repeated-file", args + [one], False)
invoke("unknown-option", args + ["--markdown"], False)
invoke("missing-file", [out / "absent.jsonl", "--job", "job", "--run", "shared"], False)
bad = out / "bad-unselected.jsonl"
bad.write_text(json.dumps(other) + "\n{}\n")
invoke("malformed-unselected", args + [bad], False)
assert before == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [one, two]}
(out / "input-hashes.json").write_text(json.dumps(before, indent=2) + "\n")
(out / "result.json").write_text(json.dumps({
    "passed": True, "cli_invocations": len(calls), "selected_observations": 5,
    "checks": ["exact pair", "stable ties and duplicates", "full decoded records",
               "unknown/null/absent statuses", "explicit null step remains run-level", "run versus step scope", "extreme timestamp span",
               "original input provenance", "Unicode/multiline/text escaping",
               "all local fragment links resolve", "determinism", "unchanged input hashes",
               "CLI errors produce no successful stdout"],
    "browser_rendering_tested": False,
}, indent=2) + "\n")
print(f"PASS: {len(calls)} native CLI invocations; HTML structure and decoded content verified")
