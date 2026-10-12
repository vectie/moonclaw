#!/usr/bin/env python3
"""Real CLI review-progress journeys; retain every source and stdout/stderr."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import unittest

if os.environ.get('MOONCLAW_PROGRESS_EVIDENCE'):
    os.environ['MOONCLAW_COLLECTION_EVIDENCE'] = os.environ['MOONCLAW_PROGRESS_EVIDENCE']
spec = importlib.util.spec_from_file_location('collection_fixture', Path(__file__).with_name('test-artifact-review-collection.py'))
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class ProgressTests(unittest.TestCase):
    setUp = fixture.CollectionTests.setUp
    invoke = fixture.CollectionTests.invoke
    worksheet = fixture.CollectionTests.worksheet

    def snapshots(self):
        old = self.worksheet('old', 'Alex', ['inspected', 'needs-changes', 'unreviewed'], ['', 'Fix total\n月', ''])
        new = self.worksheet('new', ' aLEX ', ['inspected', 'inspected', 'unreviewed'], ['', 'Rechecked total', ''])
        bea = self.worksheet('bea', 'Bea', ['inspected'] * 3)
        cam = self.worksheet('cam', 'Cam', ['unreviewed'] * 3)
        before, after = self.root / 'before.json', self.root / 'after.json'
        before.write_bytes(self.invoke('collect', self.packet, old, bea, '--title', 'First pass'))
        after.write_bytes(self.invoke('collect', self.packet, cam, new, '--title', 'Second pass'))
        return before, after

    def test_review_progress_keeps_exact_notes_and_roster_changes(self):
        a, b = self.snapshots()
        report = json.loads(self.invoke('collection-compare', self.packet, a, b))
        self.assertEqual(report['annotation_counts'], dict(added=3, removed=3, changed=1, unchanged=2))
        self.assertEqual(report['before_collection_sha256'], fixture.sha(a.read_bytes()))
        self.assertEqual(report['after_collection_sha256'], fixture.sha(b.read_bytes()))
        row = report['artifacts'][1]
        self.assertEqual(row['id'], 'draft-2')
        self.assertEqual(row['feedback'][0]['before_annotation'], {'state': 'needs-changes', 'note': 'Fix total\n月'})
        self.assertEqual(row['feedback'][0]['after_annotation'], {'state': 'inspected', 'note': 'Rechecked total'})
        self.assertEqual(row['feedback'][1]['change'], 'removed')
        self.assertIsNone(row['feedback'][1]['after_annotation'])
        self.assertEqual(row['feedback'][2]['change'], 'added')
        self.assertNotIn('resolved', row['feedback'][0])

    def test_relocate_reopen_and_same_snapshot(self):
        a, b = self.snapshots()
        expected = self.invoke('collection-compare', self.packet, a, b)
        moved = self.root / 'relocated'
        shutil.copytree(self.packet, moved)
        copy_a, copy_b = self.root / 'saved-a.json', self.root / 'saved-b.json'
        shutil.copy2(a, copy_a); shutil.copy2(b, copy_b)
        self.assertEqual(expected, self.invoke('collection-compare', moved, copy_a, copy_b))
        same = json.loads(self.invoke('collection-compare', moved, copy_a, copy_a))
        self.assertEqual(same['annotation_counts'], dict(added=0, removed=0, changed=0, unchanged=6))

    def test_markdown_links_and_literal_notes(self):
        a, b = self.snapshots()
        value = json.loads(b.read_bytes())
        sheet = json.loads(value['reviews'][0]['worksheet_json'])
        sheet['annotations'][1]['note'] = '<script>x</script>\n# heading [bad](javascript:x)'
        raw = json.dumps(sheet, ensure_ascii=False)
        value['reviews'][0].update(worksheet_json=raw, worksheet_sha256=fixture.sha(raw.encode()))
        fixture.write(b, value)
        text = self.invoke('collection-compare', self.packet, a, b, '--markdown').decode()
        self.assertIn('Before: not included', text)
        self.assertIn('After: not included', text)
        self.assertIn('&lt;script&gt;', text)
        self.assertNotIn('\n# heading', text)
        self.assertIn('[Open exported content](files/2-output.bin)', text)
        self.assertIn('No inferred resolution', text)

    def test_changed_note_same_state_counts_as_changed(self):
        a, b = self.snapshots()
        value = json.loads(b.read_bytes())
        sheet = json.loads(value['reviews'][1]['worksheet_json'])
        sheet['annotations'][0]['note'] = 'New note, same state'
        raw = json.dumps(sheet)
        value['reviews'][1].update(worksheet_json=raw, worksheet_sha256=fixture.sha(raw.encode()))
        fixture.write(b, value)
        report = json.loads(self.invoke('collection-compare', self.packet, a, b))
        self.assertEqual(report['annotation_counts']['changed'], 2)

    def test_wrong_packet_or_tampered_embedded_worksheet_refuses(self):
        a, b = self.snapshots()
        value = json.loads(b.read_bytes())
        value['source']['manifest_sha256'] = 'sha256:' + '0' * 64
        bad = self.root / 'wrong.json'; fixture.write(bad, value)
        self.invoke('collection-compare', self.packet, a, bad, success=False)
        value = json.loads(b.read_bytes())
        value['reviews'][0]['worksheet_json'] += ' '
        fixture.write(bad, value)
        self.invoke('collection-compare', self.packet, a, bad, success=False)

    def test_changed_packet_refuses_before_output(self):
        a, b = self.snapshots()
        (self.packet / 'files/2-output.bin').write_bytes(b'Changed')
        self.invoke('collection-compare', self.packet, a, b, success=False)


if __name__ == '__main__':
    unittest.main()
