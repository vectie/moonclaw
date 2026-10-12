#!/usr/bin/env python3
"""Real CLI reviewer-assignment journeys; all inputs and outputs are retained."""
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
EVIDENCE = Path(os.environ.get('MOONCLAW_COVERAGE_EVIDENCE') or tempfile.mkdtemp(prefix='moonclaw-coverage-')).resolve()
EVIDENCE.mkdir(exist_ok=True)
print('Retained evidence: ' + str(EVIDENCE), flush=True)
sha = lambda data: 'sha256:' + hashlib.sha256(data).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def fixture(root):
    (root / 'files').mkdir(parents=True)
    (root / 'records').mkdir()
    rows = []
    for index, identity in enumerate(('draft', 'final', 'chart'), 1):
        content = ('Content 月 ' + identity).encode()
        record = dict(id=identity, run_id='run-9', job_id='job-2', logical_key=identity,
                      artifact_type='analysis', version=index, status='Active',
                      path='/runtime/' + identity, content_type='text/plain', metadata={},
                      created_at=10, archived_at=None, scope=['fixture'])
        raw = json.dumps(record).encode()
        record_path, content_path = f'records/{index}.json', f'files/{index}-output.txt'
        (root / record_path).write_bytes(raw)
        (root / content_path).write_bytes(content)
        rows.append(dict(record=record, record_path=record_path, content_path=content_path,
                         record_sha256=sha(raw), content_sha256=sha(content), content_bytes=len(content)))
    write(root / 'manifest.json', dict(schema='moonclaw.artifact-export.v1', artifacts=rows,
                                     total_content_bytes=sum(row['content_bytes'] for row in rows)))


class CoverageTests(unittest.TestCase):
    def setUp(self):
        self.root = EVIDENCE / self._testMethodName
        self.root.mkdir()
        self.packet = self.root / 'packet'
        fixture(self.packet)
        self.count = 0

    def invoke(self, *args, success=True):
        originals = {p: p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        result = subprocess.run([sys.executable, str(CLI), *map(str, args)], cwd=self.root,
                                capture_output=True, timeout=20)
        self.count += 1
        for stream in ('stdout', 'stderr'):
            (self.root / f'{self.count}.{stream}').write_bytes(getattr(result, stream))
        for p, raw in originals.items():
            self.assertEqual(p.read_bytes(), raw, str(p))
        if success:
            self.assertEqual(result.returncode, 0, result.stderr.decode())
        else:
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, b'')
            self.assertTrue(result.stderr)
        return result.stdout

    def plan(self, assignments=None):
        assignments = assignments or [{'reviewer': 'Alex', 'artifact_ids': ['draft', 'final']},
                                      {'reviewer': 'Bea', 'artifact_ids': ['final']}]
        request, plan = self.root / 'assignments.json', self.root / 'plan.json'
        write(request, {'assignments': assignments})
        plan.write_bytes(self.invoke('review-plan', self.packet, request, '--title', 'Editorial 月 review'))
        return plan

    def collection(self, labels=(' aLEX ',), state='needs-changes'):
        paths = []
        for index, label in enumerate(labels):
            sheet = json.loads(self.invoke('create', self.packet, '--reviewer', label))
            sheet['annotations'][1].update(state=state, note='Fix 月 total\n<script>[link](https://invalid)')
            p = self.root / f'worksheet-{index}.json'
            write(p, sheet)
            paths.append(p)
        result = self.root / 'feedback.json'
        result.write_bytes(self.invoke('collect', self.packet, *paths))
        return result

    def test_initial_missing_then_partial_then_returned(self):
        plan = self.plan()
        initial = json.loads(self.invoke('review-coverage', self.packet, plan))
        self.assertEqual(initial['summary']['missing_feedback'], 3)
        self.assertIsNone(initial['collection_sha256'])
        self.assertEqual(initial['summary']['unassigned_artifacts'], 1)
        partial = json.loads(self.invoke('review-coverage', self.packet, plan, self.collection()))
        self.assertEqual(partial['summary'], dict(assigned_pairs=3, missing_feedback=1, unreviewed=1,
                                                inspected=0, **{'needs-changes': 1},
                                                unassigned_feedback=1, unassigned_artifacts=1))
        self.assertEqual(partial['artifacts'][1]['expected'][0]['feedback']['reviewer'], ' aLEX ')
        self.assertIsNone(partial['artifacts'][1]['expected'][1]['feedback'])
        final = json.loads(self.invoke('review-coverage', self.packet, plan, self.collection(('Alex', 'Bea'), 'inspected')))
        self.assertEqual(final['summary']['missing_feedback'], 0)
        self.assertEqual(final['summary']['unreviewed'], 1)
        self.assertEqual(final['summary']['inspected'], 2)
        self.assertNotIn('accepted', final['summary'])

    def test_extra_feedback_is_visible_without_filling_assignments(self):
        value = json.loads(self.invoke('review-coverage', self.packet, self.plan(), self.collection(('Guest',))))
        self.assertEqual(value['summary']['missing_feedback'], 3)
        self.assertEqual(value['summary']['unassigned_feedback'], 3)
        self.assertEqual(value['artifacts'][1]['unassigned_feedback'][0]['state'], 'needs-changes')
        self.assertIn('Fix 月 total', value['artifacts'][1]['unassigned_feedback'][0]['note'])

    def test_plan_and_collection_reopen_after_relocation(self):
        plan, collection = self.plan(), self.collection()
        expected = self.invoke('review-coverage', self.packet, plan, collection)
        relocated = self.root / 'relocated'
        relocated.mkdir()
        shutil.copytree(self.packet, relocated / 'packet')
        shutil.copy2(plan, relocated / 'plan.json')
        shutil.copy2(collection, relocated / 'feedback.json')
        # No original worksheet paths are passed to the reader.
        self.assertEqual(expected, self.invoke('review-coverage', relocated / 'packet', relocated / 'plan.json', relocated / 'feedback.json'))
        report = json.loads(expected)
        self.assertEqual(report['plan_sha256'], sha(plan.read_bytes()))
        self.assertEqual(report['collection_sha256'], sha(collection.read_bytes()))

    def test_markdown_keeps_exact_links_and_inert_notes(self):
        output = self.invoke('review-coverage', self.packet, self.plan(), self.collection(), '--markdown').decode()
        self.assertIn('missing_feedback', output)
        self.assertIn('No reviewer assigned', output)
        self.assertIn('[Open exported content](files/2-output.txt)', output)
        self.assertNotIn('<script>', output)
        self.assertIn('&lt;script&gt;', output)
        self.assertIn('Fix 月 total', output)

    def test_bad_assignments_refuse_without_output(self):
        for assignments in ([], [{'reviewer': 'Alex', 'artifact_ids': []}],
                            [{'reviewer': 'Alex', 'artifact_ids': ['absent']}],
                            [{'reviewer': 'Alex', 'artifact_ids': ['draft', 'draft']}],
                            [{'reviewer': 'Alex', 'artifact_ids': ['draft']}, {'reviewer': ' alex ', 'artifact_ids': ['final']}],
                            [{'reviewer': '  ', 'artifact_ids': ['draft']}],
                            [{'reviewer': 'Alex', 'artifact_ids': ['draft'], 'accept': True}]):
            p = self.root / 'invalid.json'
            write(p, {'assignments': assignments})
            self.invoke('review-plan', self.packet, p, success=False)

    def test_exact_packet_and_embedded_worksheet_binding(self):
        plan, collection = self.plan(), self.collection()
        other = self.root / 'other'
        shutil.copytree(self.packet, other)
        manifest = other / 'manifest.json'
        manifest.write_bytes(manifest.read_bytes() + b'\n')
        self.invoke('review-coverage', other, plan, collection, success=False)
        value = json.loads(collection.read_bytes())
        value['reviews'][0]['worksheet_json'] += ' '
        changed = self.root / 'changed-collection.json'
        write(changed, value)
        self.invoke('review-coverage', self.packet, plan, changed, success=False)
        (self.packet / 'files/1-output.txt').write_bytes(b'changed')
        self.invoke('review-coverage', self.packet, plan, success=False)

    def test_explicit_replan_changes_scope_only(self):
        first = self.plan()
        first_bytes = first.read_bytes()
        collection = self.collection(('Alex',))
        revised = self.root / 'revised-assignments.json'
        write(revised, {'assignments': [{'reviewer': 'Alex', 'artifact_ids': ['chart']}]})
        second = self.root / 'revised-plan.json'
        second.write_bytes(self.invoke('review-plan', self.packet, revised))
        result = json.loads(self.invoke('review-coverage', self.packet, second, collection))
        self.assertEqual(first.read_bytes(), first_bytes)
        self.assertEqual(result['summary']['assigned_pairs'], 1)
        self.assertEqual(result['summary']['unreviewed'], 1)
        self.assertEqual(result['summary']['unassigned_feedback'], 2)

    def test_saved_plan_is_validated_before_coverage(self):
        plan = self.plan()
        value = json.loads(plan.read_bytes())
        value['assignments'][0]['artifact_ids'] = ['absent']
        invalid = self.root / 'invalid-plan.json'
        write(invalid, value)
        self.invoke('review-coverage', self.packet, invalid, success=False)


if __name__ == '__main__':
    unittest.main()
