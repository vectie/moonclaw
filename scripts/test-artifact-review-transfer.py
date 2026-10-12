#!/usr/bin/env python3
"""Real-file CLI journeys for explicit new-revision reinspection."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

CLI = Path(__file__).resolve().parents[1] / 'tools/artifact_review.py'
EVIDENCE = Path(os.environ.get('MOONCLAW_TRANSFER_EVIDENCE') or tempfile.mkdtemp(prefix='moonclaw-transfer-')).resolve()
EVIDENCE.mkdir(exist_ok=True)
print('Retained evidence: ' + str(EVIDENCE), flush=True)
sha = lambda raw: 'sha256:' + hashlib.sha256(raw).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def fixture(root, revision):
    (root / 'files').mkdir(parents=True)
    (root / 'records').mkdir()
    entries = []
    for index, key in enumerate(('report', 'image', 'appendix'), 1):
        content = (b'unchanged image' if key == 'image' else f'{key} version {revision} 月'.encode())
        record = dict(id=f'{key}-{revision}', run_id=f'run-{revision}', job_id='job-a', logical_key=key,
                      artifact_type='analysis', version=revision, status='Active', path='/runtime/' + key,
                      content_type='text/plain', metadata={}, created_at=revision, archived_at=None, scope=[])
        raw = json.dumps(record).encode()
        record_path, content_path = f'records/{index}.json', f'files/{index}-output.txt'
        (root / record_path).write_bytes(raw); (root / content_path).write_bytes(content)
        entries.append(dict(record=record, record_path=record_path, content_path=content_path,
                            record_sha256=sha(raw), content_sha256=sha(content), content_bytes=len(content)))
    write(root / 'manifest.json', dict(schema='moonclaw.artifact-export.v1', artifacts=entries,
                                     total_content_bytes=sum(row['content_bytes'] for row in entries)))


class TransferTests(unittest.TestCase):
    def setUp(self):
        self.root = EVIDENCE / self._testMethodName; self.root.mkdir()
        self.old, self.new = self.root / 'previous', self.root / 'new'
        fixture(self.old, 1); fixture(self.new, 2); self.count = 0
        self.sheet, self.mapping, self.transfer = [self.root / (name + '.json') for name in ('review', 'mapping', 'transfer')]
        sheet = json.loads(self.invoke('create', self.old, '--reviewer', 'Alex 月'))
        sheet['annotations'][0].update(state='needs-changes', note='Correct total\n<script>[do not execute](x)')
        sheet['annotations'][1].update(state='inspected', note='Original image inspected.')
        sheet['annotations'][2].update(state='needs-changes', note='Keep only in old review')
        write(self.sheet, sheet)
        write(self.mapping, {'mappings': [{'from_artifact': 'report-1', 'to_artifact': 'report-2'},
                                          {'from_artifact': 'image-1', 'to_artifact': 'image-2'}]})

    def invoke(self, *args, success=True):
        original = {p: p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        result = subprocess.run([sys.executable, str(CLI), *map(str, args)], capture_output=True, cwd=self.root, timeout=20)
        self.count += 1
        for stream in ('stdout', 'stderr'): (self.root / f'{self.count}.{stream}').write_bytes(getattr(result, stream))
        for path, raw in original.items(): self.assertEqual(path.read_bytes(), raw, str(path))
        if success: self.assertEqual(result.returncode, 0, result.stderr.decode())
        else:
            self.assertNotEqual(result.returncode, 0); self.assertEqual(result.stdout, b''); self.assertTrue(result.stderr)
        return result.stdout

    def carry(self):
        self.transfer.write_bytes(self.invoke('carry-notes', self.new, self.old, self.sheet, self.mapping))
        return json.loads(self.transfer.read_bytes())

    def test_carry_selected_notes_and_continue_normal_review(self):
        value = self.carry()
        self.assertEqual(value['previous_worksheet_json'].encode(), self.sheet.read_bytes())
        self.assertEqual(value['previous_worksheet_sha256'], sha(self.sheet.read_bytes()))
        fresh = self.root / 'fresh.json'
        fresh.write_bytes(self.invoke('carried-worksheet', self.new, self.old, self.transfer))
        sheet = json.loads(fresh.read_bytes())
        self.assertTrue(all(a['state'] == 'unreviewed' for a in sheet['annotations']))
        self.assertEqual(sheet['annotations'][2]['note'], '')
        self.assertTrue(sheet['annotations'][0]['note'].endswith('Correct total\n<script>[do not execute](x)'))
        self.assertIn('Source artifact: "report-1"', sheet['annotations'][0]['note'])
        self.assertIn('Prior checklist state: needs-changes', sheet['annotations'][0]['note'])
        report = self.invoke('report', self.new, fresh, '--markdown').decode()
        self.assertIn('Source manifest:', report); self.assertNotIn('<script>', report)
        changes = self.root / 'changes.json'; write(changes, {'annotations': [{'artifact_id': 'report-2', 'state': 'inspected', 'note': 'Rechecked updated total.'}]})
        reviewed = self.root / 'reviewed.json'; reviewed.write_bytes(self.invoke('annotate', self.new, fresh, '--changes', changes))
        collection = self.root / 'collection.json'; collection.write_bytes(self.invoke('collect', self.new, reviewed))
        final = json.loads(self.invoke('collection-report', self.new, collection))
        self.assertEqual(final['artifacts'][0]['reviews'][0]['state'], 'inspected')
        self.assertEqual(final['artifacts'][1]['reviews'][0]['state'], 'unreviewed')

    def test_report_keeps_both_exact_revisions_and_uncarried_notes(self):
        self.carry(); report = json.loads(self.invoke('carried-report', self.new, self.old, self.transfer))
        self.assertEqual([r['content_relation'] for r in report['mappings']], ['different-bytes', 'same-bytes'])
        self.assertEqual(report['mappings'][0]['previous']['run_id'], 'run-1')
        self.assertEqual(report['mappings'][0]['target']['run_id'], 'run-2')
        self.assertEqual(report['mappings'][1]['previous_annotation']['state'], 'inspected')
        self.assertEqual(report['mappings'][1]['target_state'], 'unreviewed')
        self.assertEqual([r['id'] for r in report['uncarried_previous_artifacts']], ['appendix-1'])
        self.assertEqual([r['id'] for r in report['blank_target_artifacts']], ['appendix-2'])
        markdown = self.invoke('carried-report', self.new, self.old, self.transfer, '--markdown').decode()
        self.assertIn('&lt;script&gt;', markdown); self.assertNotIn('<script>', markdown)
        self.assertIn('not proven revision ancestry', markdown)

    def test_explicit_cross_logical_mapping_never_infers_correspondence(self):
        write(self.mapping, {'mappings': [{'from_artifact': 'report-1', 'to_artifact': 'appendix-2'}]})
        self.carry(); sheet = json.loads(self.invoke('carried-worksheet', self.new, self.old, self.transfer))
        self.assertEqual(sheet['annotations'][0]['note'], '')
        self.assertIn('Correct total', sheet['annotations'][2]['note'])

    def test_relocated_reopen_needs_no_original_worksheet_path(self):
        self.carry(); expected = self.invoke('carried-worksheet', self.new, self.old, self.transfer)
        elsewhere = self.root / 'relocated'; elsewhere.mkdir()
        shutil.copytree(self.old, elsewhere / 'previous'); shutil.copytree(self.new, elsewhere / 'new')
        shutil.copy2(self.transfer, elsewhere / 'transfer.json')
        self.assertEqual(expected, self.invoke('carried-worksheet', elsewhere / 'new', elsewhere / 'previous', elsewhere / 'transfer.json'))

    def test_mapping_must_be_explicit_known_unique_and_nonempty(self):
        for rows in [[], [{'from_artifact': 'missing', 'to_artifact': 'report-2'}],
                     [{'from_artifact': 'report-1', 'to_artifact': 'report-2'}, {'from_artifact': 'report-1', 'to_artifact': 'image-2'}],
                     [{'from_artifact': 'report-1', 'to_artifact': 'report-2'}, {'from_artifact': 'image-1', 'to_artifact': 'report-2'}],
                     [{'from_artifact': 'report-1', 'to_artifact': 'report-2', 'approved': True}]]:
            write(self.mapping, {'mappings': rows}); self.invoke('carry-notes', self.new, self.old, self.sheet, self.mapping, success=False)

    def test_drift_in_either_packet_or_embedded_prior_note_refuses(self):
        self.carry(); original = json.loads(self.transfer.read_bytes())
        altered = dict(original); altered['previous_worksheet_json'] += ' '
        bad = self.root / 'altered.json'; write(bad, altered)
        self.invoke('carried-worksheet', self.new, self.old, bad, success=False)
        for packet in (self.new, self.old):
            content = packet / 'files/1-output.txt'; raw = content.read_bytes(); content.write_bytes(raw + b'changed')
            self.invoke('carried-worksheet', self.new, self.old, self.transfer, success=False)
            content.write_bytes(raw)
        self.invoke('carried-report', self.old, self.new, self.transfer, success=False)

    def test_different_worksheet_binding_and_same_packet_refuse(self):
        self.invoke('carry-notes', self.old, self.old, self.sheet, self.mapping, success=False)
        wrong = self.root / 'wrong.json'; wrong.write_bytes(self.invoke('create', self.new, '--reviewer', 'Alex'))
        self.invoke('carry-notes', self.new, self.old, wrong, self.mapping, success=False)

    def test_full_note_is_never_silently_shortened_to_fit_provenance(self):
        sheet = json.loads(self.sheet.read_bytes()); sheet['annotations'][0]['note'] = '月' * 16384; write(self.sheet, sheet)
        self.invoke('carry-notes', self.new, self.old, self.sheet, self.mapping, success=False)
        self.assertEqual(json.loads(self.sheet.read_bytes())['annotations'][0]['note'], '月' * 16384)


if __name__ == '__main__':
    unittest.main()
