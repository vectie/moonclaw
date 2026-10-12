"""Explicit reviewer assignments and coverage of exact-packet feedback."""
import json

from artifact_review import decode, escape, read, require, sha, text
from artifact_review_collection import MAX_COLLECTION, unpack

SCHEMA = 'moonclaw.artifact-review-plan.v1'


def configure(commands):
    plan = commands.add_parser('review-plan', help='bind explicit reviewer/artifact assignments to a verified packet')
    plan.add_argument('packet')
    plan.add_argument('assignments', help='JSON object containing assignments')
    plan.add_argument('--title', default='Artifact review plan')
    coverage = commands.add_parser('review-coverage', help='show missing and returned feedback against an explicit plan')
    coverage.add_argument('packet')
    coverage.add_argument('plan')
    coverage.add_argument('collection', nargs='?', help='optional saved feedback collection; omit when none has returned')
    coverage.add_argument('--markdown', action='store_true')


def validate_plan(plan, source):
    require(isinstance(plan, dict) and set(plan) == {'schema', 'title', 'source', 'assignments'}, 'invalid review plan fields')
    require(plan['schema'] == SCHEMA, 'unsupported review plan schema')
    require(plan['source'] == source, 'plan does not match this exact exported packet')
    text(plan['title'], 'plan title')
    assignments = plan['assignments']
    require(isinstance(assignments, list) and 1 <= len(assignments) <= 16, 'plan requires 1..16 reviewers')
    known = {row['id'] for row in source['artifacts']}
    seen = set()
    for assignment in assignments:
        require(isinstance(assignment, dict) and set(assignment) == {'reviewer', 'artifact_ids'}, 'invalid assignment fields')
        label = text(assignment['reviewer'], 'reviewer', 256)
        key = label.strip().casefold()
        require(key not in seen, 'repeated reviewer label in plan')
        seen.add(key)
        ids = assignment['artifact_ids']
        require(isinstance(ids, list) and 1 <= len(ids) <= 32, 'assignment requires 1..32 artifact IDs')
        selected = set()
        for identity in ids:
            text(identity, 'assigned artifact id')
            require(identity in known and identity not in selected, 'unknown or repeated assigned artifact ID')
            selected.add(identity)
    return plan


def create_plan(source, raw, title):
    require(isinstance(raw, dict) and set(raw) == {'assignments'}, 'assignment input requires only assignments')
    return validate_plan({'schema': SCHEMA, 'title': text(title, 'plan title'),
                          'source': source, 'assignments': raw['assignments']}, source)


def report(plan, source, plan_sha256, collection=None, collection_sha256=None):
    validate_plan(plan, source)
    worksheets = [] if collection is None else unpack(collection, source)
    returned = {sheet['reviewer'].strip().casefold(): (sheet, fingerprint) for sheet, fingerprint in worksheets}
    summary = {key: 0 for key in ('assigned_pairs', 'missing_feedback', 'unreviewed', 'inspected',
                                   'needs-changes', 'unassigned_feedback', 'unassigned_artifacts')}
    artifacts = []
    for index, artifact in enumerate(source['artifacts']):
        expected, assigned_keys = [], set()
        for assignment in plan['assignments']:
            if artifact['id'] not in assignment['artifact_ids']:
                continue
            key = assignment['reviewer'].strip().casefold()
            assigned_keys.add(key)
            match = returned.get(key)
            feedback = None
            if match is not None:
                sheet, fingerprint = match
                annotation = sheet['annotations'][index]
                feedback = {'reviewer': sheet['reviewer'], 'worksheet_sha256': fingerprint,
                            'state': annotation['state'], 'note': annotation['note']}
            state = feedback['state'] if feedback is not None else 'missing_feedback'
            summary['assigned_pairs'] += 1
            summary[state] += 1
            expected.append({'expected_reviewer': assignment['reviewer'], 'coverage': state, 'feedback': feedback})
        extras = []
        for sheet, fingerprint in worksheets:
            if sheet['reviewer'].strip().casefold() not in assigned_keys:
                annotation = sheet['annotations'][index]
                extras.append({'reviewer': sheet['reviewer'], 'worksheet_sha256': fingerprint,
                               'state': annotation['state'], 'note': annotation['note']})
        summary['unassigned_feedback'] += len(extras)
        summary['unassigned_artifacts'] += int(not expected)
        artifacts.append(dict(artifact, expected=expected, unassigned_feedback=extras))
    return {'schema': 'moonclaw.artifact-review-coverage.v1', 'title': plan['title'],
            'manifest_sha256': source['manifest_sha256'], 'plan_sha256': plan_sha256,
            'collection_sha256': collection_sha256, 'summary': summary, 'artifacts': artifacts}


def markdown(value):
    lines = ['# ' + escape(value['title']), '',
             'Explicit assignment coverage only. Missing feedback is not completion; inspected is not acceptance.', '',
             'Manifest: ' + value['manifest_sha256'], '', 'Plan: ' + value['plan_sha256'], '',
             'Collection: ' + (value['collection_sha256'] or '(none supplied)'), '',
             '; '.join(f'{key}: {count}' for key, count in value['summary'].items()), '']
    for row in value['artifacts']:
        lines += ['## ' + escape(row['id']), '',
                  f"Run: {escape(row['run_id'])}; job: {escape(row['job_id'])}; revision: {row['version']}", '',
                  f"[Open exported content]({row['content_path']}) · [Original record]({row['record_path']})", '']
        if not row['expected']:
            lines += ['No reviewer assigned to this artifact.', '']
        for entry in row['expected']:
            lines += ['### Expected: ' + escape(entry['expected_reviewer']), '', 'Coverage: ' + entry['coverage'], '']
            feedback = entry['feedback']
            if feedback is None:
                lines += ['No worksheet with this reviewer label was supplied in the collection.', '']
            else:
                lines += ['Returned label: ' + escape(feedback['reviewer']), '',
                          'Note: ' + escape(feedback['note']), '', 'Worksheet: ' + feedback['worksheet_sha256'], '']
        if row['unassigned_feedback']:
            lines += ['### Unassigned feedback (retained, outside required coverage)', '']
        for feedback in row['unassigned_feedback']:
            lines += ['Reviewer: ' + escape(feedback['reviewer']) + '; state: ' + feedback['state'], '',
                      'Note: ' + escape(feedback['note']), '', 'Worksheet: ' + feedback['worksheet_sha256'], '']
    return '\n'.join(lines) + '\n'


def execute(args, source):
    if args.command == 'review-plan':
        value = create_plan(source, decode(read(args.assignments, MAX_COLLECTION)), args.title)
    else:
        plan_raw = read(args.plan, MAX_COLLECTION)
        collection_raw = read(args.collection, MAX_COLLECTION) if args.collection else None
        value = report(decode(plan_raw), source, sha(plan_raw),
                       decode(collection_raw) if collection_raw is not None else None,
                       sha(collection_raw) if collection_raw is not None else None)
        if args.markdown:
            return markdown(value)
    return json.dumps(value, ensure_ascii=False, indent=2) + '\n'
