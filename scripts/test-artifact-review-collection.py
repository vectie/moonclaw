#!/usr/bin/env python3
"""Real-file, dependency-free feedback collection workflows with retained evidence."""
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
EVIDENCE = Path(os.environ.get('MOONCLAW_COLLECTION_EVIDENCE') or tempfile.mkdtemp(prefix='moonclaw-feedback-')).resolve()
EVIDENCE.mkdir(exist_ok=True)
print('Retained evidence: ' + str(EVIDENCE), flush=True)


def sha(data):
    return 'sha256:' + hashlib.sha256(data).hexdigest()


def write(path, value):
    path.write_bytes((json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode())


def fixture(root):
    (root / 'files').mkdir(parents=True)
    (root / 'records').mkdir()
    entries = []
    for index, (identity, version, state, content) in enumerate([
            ('draft-1', 1, 'Archived', b'First draft\n'),
            ('draft-2', 2, 'Active', 'Current 月 draft\n'.encode()),
            ('image', 1, 'Active', b'\x00\xff')], 1):
        record = dict(id=identity, run_id='run-17', job_id='job-report',
                      logical_key='report' if index < 3 else None, artifact_type='analysis.report',
                      version=version, status=state, path='/private/original/' + identity,
                      content_type='application/octet-stream', created_at=10 * index,
                      archived_at=20 if state == 'Archived' else None, metadata={'source': 'synthetic'}, scope=['fixture'])
        record_bytes = (json.dumps(dict(record, producer_extension={'retained': True}), indent=2) + '\n').encode()
        entry = dict(record=record, record_path=f'records/{index}.json', content_path=f'files/{index}-output.bin',
                     record_sha256=sha(record_bytes), content_sha256=sha(content), content_bytes=len(content))
        (root / entry['record_path']).write_bytes(record_bytes)
        (root / entry['content_path']).write_bytes(content)
        entries.append(entry)
    write(root / 'manifest.json', dict(schema='moonclaw.artifact-export.v1', artifacts=entries,
                                     total_content_bytes=sum(entry['content_bytes'] for entry in entries)))


class CollectionTests(unittest.TestCase):
    def setUp(self):
        self.root = EVIDENCE / self._testMethodName
        self.root.mkdir()
        self.packet = self.root / 'packet'
        fixture(self.packet)
        self.number = 0

    def invoke(self, *args, success=True):
        inputs = {path: sha(path.read_bytes()) for path in self.root.rglob('*') if path.is_file()}
        run = subprocess.run([sys.executable, str(CLI), *map(str, args)], cwd=self.root,
                             capture_output=True, timeout=20)
        self.number += 1
        for stream in ('stdout', 'stderr'):
            (self.root / f'{self.number}.{stream}').write_bytes(getattr(run, stream))
        for path, fingerprint in inputs.items():
            self.assertEqual(sha(path.read_bytes()), fingerprint, str(path))
        if success:
            self.assertEqual(run.returncode, 0, run.stderr.decode())
        else:
            self.assertNotEqual(run.returncode, 0)
            self.assertEqual(run.stdout, b'')
            self.assertTrue(run.stderr)
        return run.stdout

    def worksheet(self, name, label, states, notes=None):
        initial = self.root / (name + '-blank.json')
        initial.write_bytes(self.invoke('create', self.packet, '--reviewer', label))
        changes = self.root / (name + '-changes.json')
        notes = notes or ['', '', '']
        write(changes, {'annotations': [dict(artifact_id=key, state=state, note=note)
                                       for key, state, note in zip(('draft-1', 'draft-2', 'image'), states, notes)]})
        result = self.root / (name + '.json')
        result.write_bytes(self.invoke('annotate', self.packet, initial, '--changes', changes))
        return result

    def reviews(self):
        return [self.worksheet('alex', 'Alex', ['inspected', 'needs-changes', 'unreviewed'],
                               ['Archived comparison', 'Fix the 月 total\nKeep all rows.', '']),
                self.worksheet('bea', 'Bea', ['inspected', 'inspected', 'unreviewed'],
                               ['', 'I inspected this exact revision.', '']),
                self.worksheet('cam', 'Cam', ['inspected', 'needs-changes', 'inspected'],
                               ['', 'Add the source reference.', 'Checked binary with a trusted viewer.'])]

    def collection(self, paths=None, title='Report feedback'):
        paths = paths or self.reviews()
        result = self.root / 'collection.json'
        result.write_bytes(self.invoke('collect', self.packet, *paths, '--title', title))
        return result, paths

    def test_combine_reopen_relocate_and_preserve_exact_reviewer_sources(self):
        saved, paths = self.collection()
        collection = json.loads(saved.read_bytes())
        self.assertEqual(len(collection['reviews']), 3)
        for entry, path in zip(collection['reviews'], paths):
            self.assertEqual(entry['worksheet_json'].encode(), path.read_bytes())
            self.assertEqual(entry['worksheet_sha256'], sha(path.read_bytes()))
        output = self.invoke('collection-report', self.packet, saved)
        report = json.loads(output)
        self.assertEqual(report['summary'], {'needs-changes': 1, 'mixed-states': 2, 'pending': 1, 'all-inspected': 1})
        self.assertEqual([row['id'] for row in report['artifacts']], ['draft-1', 'draft-2', 'image'])
        self.assertEqual(report['artifacts'][0]['status'], 'Archived')
        self.assertEqual([row['reviewer'] for row in report['artifacts'][1]['reviews']], ['Alex', 'Bea', 'Cam'])
        self.assertEqual(report['artifacts'][1]['reviews'][0]['note'], 'Fix the 月 total\nKeep all rows.')
        self.assertEqual(report['artifacts'][1]['counts']['needs-changes'], 2)
        self.assertEqual(self.invoke('collection-report', self.packet, saved), output)
        relocated = self.root / 'copied packet'; shutil.copytree(self.packet, relocated)
        relocated_collection = self.root / 'copied collection.json'; shutil.copyfile(saved, relocated_collection)
        for path in paths:
            path.rename(path.with_suffix('.retired'))
        self.assertEqual(self.invoke('collection-report', relocated, relocated_collection), output)
        self.assertNotIn('/private/original/', output.decode())

    def test_focus_views_keep_all_opinions_and_do_not_vote(self):
        saved, _ = self.collection()
        expected = {'needs-changes': ['draft-2'], 'mixed-states': ['draft-2', 'image'], 'pending': ['image']}
        for focus, ids in expected.items():
            result = json.loads(self.invoke('collection-report', self.packet, saved, '--focus', focus))
            self.assertEqual([row['id'] for row in result['artifacts']], ids)
            self.assertEqual(result['total_artifacts'], 3)
            self.assertEqual(result['matched_artifacts'], len(ids))
            self.assertTrue(all(len(row['reviews']) == 3 for row in result['artifacts']))
        changed = json.loads(self.invoke('collection-report', self.packet, saved, '--focus', 'needs-changes'))
        self.assertEqual(changed['artifacts'][0]['reviews'][1]['state'], 'inspected')
        self.assertIn('mixed-states', changed['artifacts'][0]['flags'])

    def test_exact_artifact_and_empty_selection_are_explicit(self):
        saved, _ = self.collection()
        result = json.loads(self.invoke('collection-report', self.packet, saved, '--artifact', 'draft-1'))
        self.assertEqual([row['id'] for row in result['artifacts']], ['draft-1'])
        empty = self.invoke('collection-report', self.packet, saved, '--artifact', 'draft-1', '--focus', 'pending', '--markdown').decode()
        self.assertIn('Showing 0 of 3 artifacts', empty)
        self.assertIn('No artifacts match', empty)
        self.invoke('collection-report', self.packet, saved, '--artifact', 'DRAFT-1', success=False)

    def test_readable_export_links_and_inert_text(self):
        paths = self.reviews()
        malicious = self.worksheet('markup', '[Name](https://example.invalid)', ['inspected'] * 3,
                                   ['<script>no</script> [link](https://example.invalid)\n# text', '', ''])
        saved, _ = self.collection(paths + [malicious], title='<b>Feedback</b> [title](https://example.invalid)')
        output = self.invoke('collection-report', self.packet, saved, '--markdown')
        readable = self.packet / 'team-review.md'; readable.write_bytes(output)
        content = output.decode()
        self.assertNotIn('<script>', content)
        self.assertNotIn('<b>', content)
        self.assertNotIn('[Name](https://example.invalid)', content)
        self.assertIn('No owner acceptance', content)
        self.assertIn('Mixed states include unreviewed', content)
        links = re.findall(r'(?<!\\)\]\(([^)]+)\)', content)
        self.assertEqual(len(links), 6)
        for link in links:
            self.assertTrue((readable.parent / link).is_file(), link)

    def test_updated_feedback_requires_explicit_recollection(self):
        saved, paths = self.collection()
        old = self.invoke('collection-report', self.packet, saved)
        replacement = self.worksheet('alex-later', 'Alex', ['inspected'] * 3, ['', 'Rechecked revised explanation.', ''])
        self.invoke('collect', self.packet, *paths, replacement, success=False)
        new = self.root / 'new-collection.json'
        new.write_bytes(self.invoke('collect', self.packet, replacement, paths[1], paths[2]))
        report = json.loads(self.invoke('collection-report', self.packet, new))
        self.assertEqual(report['artifacts'][1]['counts']['needs-changes'], 1)
        self.assertEqual(report['artifacts'][1]['reviews'][0]['note'], 'Rechecked revised explanation.')
        self.assertEqual(self.invoke('collection-report', self.packet, saved), old)
        duplicate = self.worksheet('alias', '  aLeX  ', ['inspected'] * 3)
        self.invoke('collect', self.packet, paths[0], duplicate, success=False)

    def test_single_reviewer_and_caller_order_remain_meaningful(self):
        paths = self.reviews()
        saved, _ = self.collection([paths[1]])
        report = json.loads(self.invoke('collection-report', self.packet, saved))
        self.assertEqual(report['summary']['mixed-states'], 0)
        self.assertEqual(report['summary']['pending'], 1)
        saved.write_bytes(self.invoke('collect', self.packet, paths[2], paths[0]))
        report = json.loads(self.invoke('collection-report', self.packet, saved))
        self.assertEqual([entry['reviewer'] for entry in report['reviewers']], ['Cam', 'Alex'])
        self.assertEqual(report['artifacts'][1]['counts']['needs-changes'], 2)

    def test_other_packet_or_changed_copies_refuse_feedback(self):
        saved, paths = self.collection()
        other = self.root / 'other'; fixture(other)
        manifest = other / 'manifest.json'
        manifest.write_bytes(manifest.read_bytes() + b'\n')
        self.invoke('collect', other, *paths, success=False)
        self.invoke('collection-report', other, saved, success=False)
        (self.packet / 'files/3-output.bin').write_bytes(b'changed')
        self.invoke('collection-report', self.packet, saved, '--artifact', 'draft-1', success=False)

    def test_every_embedded_review_is_checked_before_filtering(self):
        saved, _ = self.collection()
        value = json.loads(saved.read_bytes())
        entry = value['reviews'][2]
        changed = json.loads(entry['worksheet_json'])
        changed['annotations'][2]['state'] = 'accepted'
        entry['worksheet_json'] = json.dumps(changed)
        write(saved, value)
        self.invoke('collection-report', self.packet, saved, '--artifact', 'draft-1', success=False)
        entry['worksheet_sha256'] = sha(entry['worksheet_json'].encode())
        write(saved, value)
        self.invoke('collection-report', self.packet, saved, '--artifact', 'draft-1', success=False)

    def test_collection_limits_and_help(self):
        paths = self.reviews()
        self.invoke('collect', self.packet, *([paths[0]] * 17), success=False)
        self.invoke('collect', self.packet, success=False)
        self.assertIn(b'collection-report', self.invoke('--help'))
        self.assertIn(b'--focus', self.invoke('collection-report', '--help'))
        # JSON whitespace still counts toward the byte budget. No arbitrary file
        # is accepted just because the parsed worksheet would be small.
        big = []
        for index, path in enumerate(paths):
            padded = self.root / f'padded-{index}.json'
            padded.write_bytes(path.read_bytes().ljust(3 * 1024 * 1024, b' '))
            big.append(padded)
        self.invoke('collect', self.packet, *big, success=False)


if __name__ == '__main__':
    unittest.main()
