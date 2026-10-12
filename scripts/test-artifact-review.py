#!/usr/bin/env python3
"""Dependency-free, real-file tests; retains all synthetic evidence under a new directory."""
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

CLI = Path(__file__).resolve().parents[1] / 'tools/artifact_review.py'
EVIDENCE = Path(os.environ.get('MOONCLAW_REVIEW_EVIDENCE', tempfile.mkdtemp(prefix='moonclaw-review-')))
EVIDENCE.mkdir(exist_ok=True)
print('Retained evidence: ' + str(EVIDENCE), flush=True)


def sha(data):
    return 'sha256:' + hashlib.sha256(data).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def fixture(root):
    (root / 'files').mkdir(parents=True)
    (root / 'records').mkdir()
    entries = []
    for number, identity, version, state, data in [(1, 'draft-1', 1, 'Archived', b'first draft\n'),
              (2, 'draft-2', 2, 'Active', '月 revised\n'.encode()), (3, 'image', 1, 'Active', b'\x00\xff')]:
        record = dict(id=identity, run_id='run-17', job_id='job-report', logical_key='report' if number < 3 else None,
                      artifact_type='analysis.report', version=version, status=state, path='/original-machine/private/' + identity,
                      content_type='text/plain', created_at=10 * number, archived_at=None, metadata={'unreviewed': True}, scope=['fixture'])
        if state == 'Archived': record['archived_at'] = 20
        record_bytes = (json.dumps(dict(record, future_provenance={'v': 7}), ensure_ascii=False, indent=2) + '\n').encode()
        entry = dict(record=record, record_path=f'records/{number}.json', content_path=f'files/{number}-output.bin',
                     record_sha256=sha(record_bytes), content_sha256=sha(data), content_bytes=len(data))
        (root / entry['record_path']).write_bytes(record_bytes)
        (root / entry['content_path']).write_bytes(data)
        entries.append(entry)
    write(root / 'manifest.json', dict(schema='moonclaw.artifact-export.v1', artifacts=entries,
                                     total_content_bytes=sum(e['content_bytes'] for e in entries)))
    return root


class ReviewTests(unittest.TestCase):
    def setUp(self):
        self.root = EVIDENCE / self._testMethodName
        self.root.mkdir()
        self.packet = fixture(self.root / 'packet')
        self.number = 0

    def invoke(self, *args, success=True):
        before = {str(p.relative_to(self.packet)): sha(p.read_bytes()) for p in self.packet.rglob('*') if p.is_file()}
        process = subprocess.run([sys.executable, str(CLI), *map(str, args)], capture_output=True, timeout=15)
        self.number += 1
        (self.root / f'{self.number}.stdout').write_bytes(process.stdout)
        (self.root / f'{self.number}.stderr').write_bytes(process.stderr)
        self.assertEqual(before, {str(p.relative_to(self.packet)): sha(p.read_bytes()) for p in self.packet.rglob('*') if p.is_file()})
        if success:
            self.assertEqual(process.returncode, 0, process.stderr.decode())
        else:
            self.assertNotEqual(process.returncode, 0)
            self.assertEqual(process.stdout, b'')
            self.assertTrue(process.stderr)
        return process.stdout

    def new(self):
        value = json.loads(self.invoke('create', self.packet, '--reviewer', 'A reviewer'))
        path = self.root / 'review.json'
        write(path, value)
        return path, value

    def test_full_review_handoff_and_relocated_reopen(self):
        path, blank = self.new()
        self.assertEqual([a['state'] for a in blank['annotations']], ['unreviewed'] * 3)
        changes = self.root / 'changes.json'
        write(changes, {'annotations': [{'artifact_id': 'draft-1', 'state': 'inspected', 'note': 'Kept for comparison'},
                                      {'artifact_id': 'draft-2', 'state': 'needs-changes', 'note': 'Check total 月\n<script>bad</script> [x](https://bad.invalid)'}]})
        annotated = json.loads(self.invoke('annotate', self.packet, path, '--changes', changes))
        new = self.root / 'annotated.json'; write(new, annotated)
        self.assertEqual(json.loads(path.read_bytes()), blank)
        self.assertEqual(annotated['source'], blank['source'])
        self.assertEqual(annotated['annotations'][2], blank['annotations'][2])
        markdown = self.invoke('report', self.packet, new, '--markdown').decode()
        self.assertIn('needs-changes: 1', markdown)
        self.assertIn('no logical key', markdown)
        self.assertNotIn('future_provenance', blank['source']['artifacts'][0])
        self.assertNotIn('<script>', markdown)
        self.assertNotIn('[x](https://bad.invalid)', markdown)
        self.assertNotIn('/original-machine/', markdown)
        links = re.findall(r'\]\(([^)]+)\)', markdown)
        self.assertEqual(len(links), 6)
        for link in links: self.assertTrue((self.packet / link).is_file())
        copied = self.root / 'relocated'; shutil.copytree(self.packet, copied)
        self.assertEqual(json.loads(self.invoke('report', copied, new)), annotated)
        self.assertEqual(self.invoke('report', copied, new), self.invoke('report', copied, new))

    def test_changed_content_rejects_saved_feedback(self):
        path, _ = self.new()
        (self.packet / 'files/2-output.bin').write_bytes(b'changed')
        self.invoke('report', self.packet, path, success=False)

    def test_changed_original_record_rejects_feedback(self):
        path, _ = self.new()
        (self.packet / 'records/1.json').write_bytes(b'{}')
        self.invoke('report', self.packet, path, success=False)

    def test_reformatted_manifest_requires_new_worksheet(self):
        path, _ = self.new()
        manifest = self.packet / 'manifest.json'
        manifest.write_text(json.dumps(json.loads(manifest.read_bytes())))
        self.invoke('report', self.packet, path, success=False)

    def test_worksheet_identity_and_status_validation(self):
        path, value = self.new()
        for field, update in [('source', {'manifest_sha256': 'sha256:' + '0' * 64}), ('annotations', []), ('reviewer', '')]:
            invalid = copy.deepcopy(value); invalid[field] = update; write(path, invalid)
            self.invoke('report', self.packet, path, success=False)
        invalid = copy.deepcopy(value); invalid['annotations'][0]['state'] = 'accepted'; write(path, invalid)
        self.invoke('report', self.packet, path, success=False)

    def test_edits_preserve_complete_notes_and_reject_unknowns(self):
        path, value = self.new()
        changes = self.root / 'changes.json'
        valid = {'artifact_id': 'draft-2', 'state': 'inspected', 'note': '=1+2\nAll output checked'}
        write(changes, {'annotations': [valid]})
        result = json.loads(self.invoke('annotate', self.packet, path, '--changes', changes))
        self.assertEqual(result['annotations'][1]['note'], valid['note'])
        for edits in [[valid, valid], [dict(valid, artifact_id='missing')], [dict(valid, state='accepted')], [dict(valid, note=3)]]:
            write(changes, {'annotations': edits})
            self.invoke('annotate', self.packet, path, '--changes', changes, success=False)

    def test_all_entries_checked_even_unreviewed_binary(self):
        (self.packet / 'files/3-output.bin').write_bytes(b'bad')
        self.invoke('create', self.packet, '--reviewer', 'Review', success=False)

    def test_malformed_manifest_and_duplicate_json_fields(self):
        manifest = self.packet / 'manifest.json'
        valid = json.loads(manifest.read_bytes())
        for change in [dict(valid, total_content_bytes=0), dict(valid, schema='other'), dict(valid, artifacts=[])]:
            write(manifest, change)
            self.invoke('create', self.packet, '--reviewer', 'Review', success=False)
        manifest.write_bytes(b'{"schema":1,"schema":2}')
        self.invoke('create', self.packet, '--reviewer', 'Review', success=False)

    def test_member_paths_and_symlinks_refuse(self):
        manifest = self.packet / 'manifest.json'; value = json.loads(manifest.read_bytes())
        value['artifacts'][0]['content_path'] = '../outside'; write(manifest, value)
        self.invoke('create', self.packet, '--reviewer', 'Review', success=False)
        value['artifacts'][0]['content_path'] = 'files/1-output.bin'; write(manifest, value)
        member = self.packet / 'files/1-output.bin'; data = member.read_bytes(); member.unlink()
        target = self.root / 'outside'; target.write_bytes(data); member.symlink_to(target)
        self.invoke('create', self.packet, '--reviewer', 'Review', success=False)

    def test_missing_packet_and_cli_help(self):
        self.invoke('create', self.root / 'absent', '--reviewer', 'Review', success=False)
        self.invoke('--help')
        self.invoke('report', self.packet, success=False)


if __name__ == '__main__':
    unittest.main()
