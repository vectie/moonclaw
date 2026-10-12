"""Compare explicitly selected feedback snapshots for the same exact packet."""
import json

from artifact_review import decode, escape, read, sha
from artifact_review_collection import MAX_COLLECTION, unpack


def configure(commands):
    command = commands.add_parser('collection-compare', help='compare reviewer notes between two exact-packet feedback snapshots')
    command.add_argument('packet')
    command.add_argument('before')
    command.add_argument('after')
    command.add_argument('--markdown', action='store_true')


def compare(source, before, after):
    old = unpack(before, source)
    new = unpack(after, source)
    key = lambda sheet: sheet['reviewer'].strip().casefold()
    left = {key(sheet): (sheet, fingerprint) for sheet, fingerprint in old}
    right = {key(sheet): (sheet, fingerprint) for sheet, fingerprint in new}
    order = list(left) + [name for name in right if name not in left]
    reviewers = []
    artifacts = []
    for name in order:
        def identity(mapping):
            if name not in mapping:
                return None
            sheet, fingerprint = mapping[name]
            return {'reviewer': sheet['reviewer'], 'worksheet_sha256': fingerprint}
        reviewers.append({'before': identity(left), 'after': identity(right)})
    counts = dict(added=0, removed=0, changed=0, unchanged=0)
    for index, artifact in enumerate(source['artifacts']):
        rows = []
        for name, reviewer in zip(order, reviewers):
            def annotation(mapping):
                if name not in mapping:
                    return None
                value = mapping[name][0]['annotations'][index]
                return {'state': value['state'], 'note': value['note']}
            a, b = annotation(left), annotation(right)
            kind = 'added' if a is None else 'removed' if b is None else 'unchanged' if a == b else 'changed'
            counts[kind] += 1
            rows.append(dict(reviewer, change=kind, before_annotation=a, after_annotation=b))
        artifacts.append(dict(artifact, feedback=rows))
    return {'schema': 'moonclaw.artifact-review-progress.v1', 'manifest_sha256': source['manifest_sha256'],
            'before_title': before['title'], 'after_title': after['title'], 'reviewers': reviewers,
            'annotation_counts': counts, 'artifacts': artifacts}


def markdown(value):
    lines = ['# Artifact feedback changes', '',
             'Explicit before/after snapshots of reviewer statements. No inferred resolution, acceptance, or chronology.', '',
             'Manifest: ' + value['manifest_sha256'], '',
             'Before: ' + escape(value['before_title']) + ' (' + value['before_collection_sha256'] + ')', '',
             'After: ' + escape(value['after_title']) + ' (' + value['after_collection_sha256'] + ')', '',
             'Annotation counts: ' + '; '.join(f'{name}: {count}' for name, count in value['annotation_counts'].items()), '',
             'Absent reviewers have no statement in that snapshot; removal is not withdrawal or completion.', '']
    for row in value['artifacts']:
        lines += ['## ' + escape(row['id']), '',
                  f"Run: {escape(row['run_id'])}; job: {escape(row['job_id'])}; revision: {row['version']}", '',
                  f"[Open exported content]({row['content_path']}) · [Original record]({row['record_path']})", '',
                  'Content: ' + row['content_sha256'], '']
        for item in row['feedback']:
            label = (item['after'] or item['before'])['reviewer']
            lines += ['### ' + escape(label) + ': ' + item['change'], '']
            for side in ('before', 'after'):
                note = item[side + '_annotation']
                if note is None:
                    lines += [side.title() + ': not included', '']
                else:
                    lines += [side.title() + ': ' + escape(item[side]['reviewer']) + '; ' + note['state'], '',
                              'Note: ' + escape(note['note']), '', 'Worksheet: ' + item[side]['worksheet_sha256'], '']
    return '\n'.join(lines) + '\n'


def execute(args, source):
    a, b = read(args.before, MAX_COLLECTION), read(args.after, MAX_COLLECTION)
    value = compare(source, decode(a), decode(b))
    value.update(before_collection_sha256=sha(a), after_collection_sha256=sha(b))
    return markdown(value) if args.markdown else json.dumps(value, ensure_ascii=False, indent=2) + '\n'
