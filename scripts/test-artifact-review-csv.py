#!/usr/bin/env python3
"""Real-file review CSV editing journeys; retain fixtures and CLI output."""
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

CLI = Path(__file__).resolve().parents[1] / 'tools/artifact_review.py'
EVIDENCE = Path(os.environ.get('MOONCLAW_REVIEW_CSV_EVIDENCE') or tempfile.mkdtemp(prefix='moonclaw-review-csv-')).resolve()
EVIDENCE.mkdir(exist_ok=True)
print('Retained evidence: ' + str(EVIDENCE), flush=True)


def sha(raw):
    return 'sha256:' + hashlib.sha256(raw).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def fixture(root):
    (root / 'files').mkdir(parents=True)
    (root / 'records').mkdir()
    entries = []
    for number, identity, status, content in [(1, '00123', 'Archived', b'old report\r\n'),
            (2, '=report 月', 'Active', 'Updated total 月\n'.encode()), (3, 'image', 'Active', b'\x00\xff')]:
        record = dict(id=identity, run_id='@run', job_id='00100', logical_key='report' if number < 3 else None,
                      artifact_type='analysis', version=number, status=status, path='/private/runtime/' + identity,
                      content_type='text/plain', metadata={}, created_at=number, archived_at=None, scope=[])
        raw = json.dumps(dict(record, future_field='kept in original')).encode()
        rp, cp = f'records/{number}.json', f'files/{number}-output.bin'
        (root / rp).write_bytes(raw); (root / cp).write_bytes(content)
        entries.append(dict(record=record, record_path=rp, content_path=cp, record_sha256=sha(raw),
                            content_sha256=sha(content), content_bytes=len(content)))
    write(root / 'manifest.json', dict(schema='moonclaw.artifact-export.v1', artifacts=entries,
                                     total_content_bytes=sum(row['content_bytes'] for row in entries)))


class CsvReviewTests(unittest.TestCase):
    def setUp(self):
        self.root = EVIDENCE / self._testMethodName; self.root.mkdir()
        self.packet = self.root / 'packet'; fixture(self.packet); self.count = 0
        self.sheet = self.root / 'base.json'; self.csv = self.root / 'review.csv'
        sheet = json.loads(self.invoke('create', self.packet, '--reviewer', '+Alex 月'))
        sheet['annotations'][0].update(state='inspected', note='Keep archived copy')
        sheet['annotations'][1].update(state='needs-changes', note='=SUM(1,2)\r\n"Quoted", 月')
        sheet['annotations'][2].update(state='unreviewed', note="'original apostrophe")
        write(self.sheet, sheet)

    def invoke(self, *args, success=True):
        before = {p: p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        process = subprocess.run([sys.executable, str(CLI), *map(str, args)], cwd=self.root,
                                 capture_output=True, timeout=15)
        self.count += 1
        for stream in ('stdout', 'stderr'):
            (self.root / f'{self.count}.{stream}').write_bytes(getattr(process, stream))
        for path, raw in before.items(): self.assertEqual(path.read_bytes(), raw, str(path))
        if success: self.assertEqual(process.returncode, 0, process.stderr.decode())
        else:
            self.assertNotEqual(process.returncode, 0)
            self.assertEqual(process.stdout, b'')
            self.assertTrue(process.stderr)
        return process.stdout

    def export(self, *extra):
        raw = self.invoke('export-csv', self.packet, self.sheet, *extra)
        self.csv.write_bytes(raw)
        reader = csv.DictReader(io.StringIO(raw.decode(), newline=''))
        return reader.fieldnames, list(reader)

    def save_csv(self, header, rows, bom=False):
        output = io.StringIO(newline='')
        writer = csv.DictWriter(output, header, quoting=csv.QUOTE_ALL, lineterminator='\r\n')
        writer.writeheader(); writer.writerows(rows)
        self.csv.write_bytes(('\ufeff' if bom else '').encode() + output.getvalue().encode())

    def test_noop_roundtrip_preserves_full_notes_ids_and_revision_order(self):
        header, rows = self.export()
        self.assertEqual(rows[0]['artifact_id'], '00123')
        self.assertEqual(rows[1]['artifact_id'], "'=report 月")
        self.assertEqual(rows[1]['note'], '\'=SUM(1,2)\r\n"Quoted", 月')
        self.assertEqual(rows[2]['note'], "''original apostrophe")
        self.assertIn('artifact_id', rows[1]['text_prefixed_columns'])
        self.assertNotIn('/private/runtime/', self.csv.read_text())
        updated = self.invoke('import-csv', self.packet, self.sheet, self.csv)
        self.assertEqual(json.loads(updated), json.loads(self.sheet.read_bytes()))
        preview = json.loads(self.invoke('import-csv', self.packet, self.sheet, self.csv, '--preview'))
        self.assertEqual(preview['summary'], dict(selected_artifacts=3, changed_artifacts=0,
                         unchanged_selected_artifacts=3, omitted_artifacts=0))
        self.assertEqual(preview['changes'], [])

    def test_edit_preview_apply_and_continue_collection_and_coverage(self):
        header, rows = self.export()
        rows[0].update(state='needs-changes', note='Recheck archived comparison, "row 2"\r\n月')
        rows[1].update(state='inspected', note='Corrected total checked.')
        rows[1]['text_prefixed_columns'] = rows[1]['text_prefixed_columns'].replace(';note', '')
        self.save_csv(header, rows)
        preview = json.loads(self.invoke('import-csv', self.packet, self.sheet, self.csv, '--preview'))
        self.assertEqual(preview['worksheet_sha256'], sha(self.sheet.read_bytes()))
        self.assertEqual(preview['csv_sha256'], sha(self.csv.read_bytes()))
        self.assertEqual(preview['summary']['changed_artifacts'], 2)
        self.assertEqual(preview['changes'][0]['after']['note'], rows[0]['note'])
        self.assertEqual(preview['changes'][1]['before']['state'], 'needs-changes')
        updated = self.root / 'updated.json'
        updated.write_bytes(self.invoke('import-csv', self.packet, self.sheet, self.csv))
        self.assertIn('Corrected total checked', self.invoke('report', self.packet, updated, '--markdown').decode())
        collection = self.root / 'feedback.json'
        collection.write_bytes(self.invoke('collect', self.packet, updated))
        assignments = self.root / 'assignments.json'
        write(assignments, {'assignments': [{'reviewer': '+Alex 月', 'artifact_ids': ['00123', '=report 月']}]})
        plan = self.root / 'plan.json'; plan.write_bytes(self.invoke('review-plan', self.packet, assignments))
        report = json.loads(self.invoke('review-coverage', self.packet, plan, collection))
        self.assertEqual(report['summary']['inspected'], 1)
        self.assertEqual(report['summary']['needs-changes'], 1)

    def test_subset_reordering_and_bom_preserve_omitted_annotations(self):
        header, rows = self.export('--artifact', '00123', '--artifact', 'image')
        self.assertEqual(len(rows), 2)
        rows[1]['note'] = ''
        rows[1]['text_prefixed_columns'] = rows[1]['text_prefixed_columns'].replace(';note', '')
        rows[1]['state'] = 'inspected'
        self.save_csv(list(reversed(header)), list(reversed(rows)), bom=True)
        updated = json.loads(self.invoke('import-csv', self.packet, self.sheet, self.csv))
        original = json.loads(self.sheet.read_bytes())
        self.assertEqual(updated['annotations'][1], original['annotations'][1])
        self.assertEqual(updated['annotations'][2]['note'], '')
        self.assertEqual([a['artifact_id'] for a in updated['annotations']], ['00123', '=report 月', 'image'])
        preview = json.loads(self.invoke('import-csv', self.packet, self.sheet, self.csv, '--preview'))
        self.assertEqual(preview['summary']['omitted_artifacts'], 1)
        self.assertEqual(preview['summary']['changed_artifacts'], 1)

    def test_deleted_csv_row_is_omitted_not_cleared(self):
        header, rows = self.export()
        self.save_csv(header, rows[:1])
        self.assertEqual(json.loads(self.invoke('import-csv', self.packet, self.sheet, self.csv)),
                         json.loads(self.sheet.read_bytes()))
        self.save_csv(header, [])
        self.invoke('import-csv', self.packet, self.sheet, self.csv, success=False)

    def test_relocated_packet_base_and_csv_reopen_without_original_paths(self):
        self.export()
        moved = self.root / 'moved'; moved.mkdir()
        shutil.copytree(self.packet, moved / 'packet')
        shutil.copy2(self.sheet, moved / 'base.json'); shutil.copy2(self.csv, moved / 'review.csv')
        self.assertEqual(self.invoke('import-csv', self.packet, self.sheet, self.csv),
                         self.invoke('import-csv', moved / 'packet', moved / 'base.json', moved / 'review.csv'))

    def test_stale_base_and_changed_reference_refuse_without_partial_output(self):
        header, rows = self.export()
        updated = self.root / 'new-base.json'; sheet = json.loads(self.sheet.read_bytes())
        sheet['annotations'][2]['note'] = 'A later observation'; write(updated, sheet)
        self.invoke('import-csv', self.packet, updated, self.csv, success=False)
        reformatted = self.root / 'reformatted.json'; reformatted.write_text(json.dumps(json.loads(self.sheet.read_bytes())))
        self.invoke('import-csv', self.packet, reformatted, self.csv, success=False)
        rows[0]['revision'] = '2'; self.save_csv(header, rows)
        self.invoke('import-csv', self.packet, self.sheet, self.csv, '--preview', success=False)

    def test_packet_drift_is_checked_even_when_only_other_row_selected(self):
        self.export('--artifact', '00123')
        (self.packet / 'files/3-output.bin').write_bytes(b'changed')
        self.invoke('import-csv', self.packet, self.sheet, self.csv, success=False)

    def test_new_formula_note_and_apostrophe_notes_remain_literal(self):
        header, rows = self.export('--artifact', '00123')
        for note in ['=1+2', '  @SUM(1)', "'quoted note", '\tstart', '\r\nstart']:
            rows[0]['note'] = note; self.save_csv(header, rows)
            updated = json.loads(self.invoke('import-csv', self.packet, self.sheet, self.csv))
            self.assertEqual(updated['annotations'][0]['note'], note)
            new = self.root / 'next.json'; write(new, updated)
            emitted = self.invoke('export-csv', self.packet, new, '--artifact', '00123')
            exported = list(csv.DictReader(io.StringIO(emitted.decode(), newline='')))[0]
            self.assertEqual(exported['note'], "'" + note)
            self.assertIn('note', exported['text_prefixed_columns'].split(';'))

    def test_prefix_edit_guidance_and_invalid_states_do_not_guess(self):
        header, rows = self.export('--artifact', '=report 月')
        rows[0]['note'] = 'Edited without prefix'; self.save_csv(header, rows)
        self.invoke('import-csv', self.packet, self.sheet, self.csv, success=False)
        rows[0]['text_prefixed_columns'] = rows[0]['text_prefixed_columns'].replace(';note', '')
        rows[0]['state'] = 'accepted'; self.save_csv(header, rows)
        self.invoke('import-csv', self.packet, self.sheet, self.csv, success=False)
        rows[0]['state'] = 'inspected'; rows[0]['note'] = '月' * 16385; self.save_csv(header, rows)
        self.invoke('import-csv', self.packet, self.sheet, self.csv, success=False)

    def test_duplicate_or_broken_rows_and_selection_refuse(self):
        header, rows = self.export('--artifact', '00123')
        self.save_csv(header, rows * 2)
        self.invoke('import-csv', self.packet, self.sheet, self.csv, success=False)
        self.save_csv(header, rows)
        self.csv.write_bytes(self.csv.read_bytes() + b'"unfinished')
        self.invoke('import-csv', self.packet, self.sheet, self.csv, success=False)
        self.invoke('export-csv', self.packet, self.sheet, '--artifact', 'missing', success=False)
        self.invoke('export-csv', self.packet, self.sheet, '--artifact', '00123', '--artifact', '00123', success=False)


if __name__ == '__main__':
    unittest.main()
