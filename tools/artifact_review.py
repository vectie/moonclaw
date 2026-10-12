#!/usr/bin/env python3
"""Offline, revision-bound reviewer notes for MoonClaw portable artifact exports."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys

SCHEMA = 'moonclaw.artifact-review-notes.v1'
STATES = ('unreviewed', 'inspected', 'needs-changes')
MAX_JSON = 4 * 1024 * 1024
RECORD_FIELDS = ('id', 'run_id', 'job_id', 'artifact_type', 'logical_key', 'version',
                 'status', 'path', 'content_type', 'metadata', 'created_at', 'archived_at', 'scope')


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(data):
    return 'sha256:' + hashlib.sha256(data).hexdigest()


def pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, 'duplicate JSON key: ' + key)
        result[key] = value
    return result


def decode(data):
    return json.loads(data.decode('utf-8'), object_pairs_hook=pairs,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite JSON number')))


def read(path, limit):
    descriptor = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
    with os.fdopen(descriptor, 'rb') as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_size <= limit, 'not a bounded regular file: ' + str(path))
        data = stream.read(limit + 1)
        require(len(data) <= limit, 'file exceeds limit: ' + str(path))
        return data


def text(value, name, limit=4096, nonempty=True):
    require(isinstance(value, str) and len(value) <= limit and '\x00' not in value,
            'invalid ' + name)
    require(not nonempty or value.strip(), 'blank ' + name)
    return value


def integer(value, name, minimum=0):
    require(type(value) is int and value >= minimum, 'invalid ' + name)
    return value


def digest(value):
    require(isinstance(value, str) and re.fullmatch(r'sha256:[0-9a-f]{64}', value), 'invalid SHA-256')
    return value


def packet(root):
    root = Path(root)
    require(root.is_dir() and not root.is_symlink(), 'packet must be a regular directory')
    for name in ('files', 'records'):
        require((root / name).is_dir() and not (root / name).is_symlink(), 'invalid packet directory: ' + name)
    raw = read(root / 'manifest.json', MAX_JSON)
    manifest = decode(raw)
    require(isinstance(manifest, dict) and manifest.get('schema') == 'moonclaw.artifact-export.v1', 'unsupported export schema')
    entries = manifest.get('artifacts')
    require(isinstance(entries, list) and 1 <= len(entries) <= 32, 'export requires 1..32 artifacts')
    identities, paths, rows, total = set(), set(), [], 0
    for entry in entries:
        require(isinstance(entry, dict), 'invalid export entry')
        record = entry.get('record')
        require(isinstance(record, dict), 'missing artifact record')
        identity = text(record.get('id'), 'artifact id')
        require(identity not in identities, 'duplicate artifact id')
        identities.add(identity)
        for field in ('run_id', 'job_id', 'artifact_type', 'status'):
            text(record.get(field), field)
        require(record['status'] in ('Active', 'Archived'), 'unsupported artifact state')
        if record.get('logical_key') is not None:
            text(record['logical_key'], 'logical_key', nonempty=False)
        require(all(key in record for key in RECORD_FIELDS if key not in ('logical_key', 'archived_at')), 'incomplete artifact record')
        for field in ('path', 'content_type'):
            text(record[field], field, nonempty=False)
        require(type(record['created_at']) is int and (record.get('archived_at') is None or type(record['archived_at']) is int), 'invalid record timestamp')
        require(isinstance(record['scope'], list) and all(isinstance(v, str) for v in record['scope']), 'invalid record scope')
        integer(record.get('version'), 'artifact version', 1)
        size = integer(entry.get('content_bytes'), 'content_bytes')
        require(size <= 16 * 1024 * 1024, 'content exceeds 16 MiB')
        total += size
        require(total <= 64 * 1024 * 1024, 'packet exceeds 64 MiB')
        for field, pattern, limit, hash_field in (
                ('record_path', r'records/[1-9][0-9]*\.json', 256 * 1024, 'record_sha256'),
                ('content_path', r'files/[1-9][0-9]*-[A-Za-z0-9._-]+', 16 * 1024 * 1024, 'content_sha256')):
            member = entry.get(field)
            require(isinstance(member, str) and re.fullmatch(pattern, member) and member not in paths,
                    'unsafe or duplicate exported member')
            paths.add(member)
            data = read(root / member, limit)
            require(sha(data) == digest(entry.get(hash_field)), 'exported member fingerprint changed: ' + member)
            if field == 'record_path':
                original = decode(data)
                require(isinstance(original, dict) and all(key in original for key in RECORD_FIELDS if key not in ('logical_key', 'archived_at')), 'incomplete original artifact record')
                # The producer retains unknown raw fields, but emits a typed ArtifactRecord in the manifest.
                require({key: original.get(key) for key in RECORD_FIELDS} == {key: record.get(key) for key in RECORD_FIELDS},
                        'original record disagrees with typed manifest fields')
            else:
                require(len(data) == size, 'content size disagrees with manifest')
        rows.append({key: record.get(key) for key in ('id', 'job_id', 'run_id', 'logical_key', 'artifact_type', 'version', 'status')} |
                    {key: entry[key] for key in ('record_path', 'content_path', 'record_sha256', 'content_sha256', 'content_bytes')})
    require(integer(manifest.get('total_content_bytes'), 'total_content_bytes') == total, 'packet total mismatch')
    require(read(root / 'manifest.json', MAX_JSON) == raw, 'manifest changed during verification')
    return {'manifest_sha256': sha(raw), 'artifacts': rows}


def create(source, reviewer):
    return {'schema': SCHEMA, 'reviewer': text(reviewer, 'reviewer', 256), 'source': source,
            'annotations': [{'artifact_id': row['id'], 'state': 'unreviewed', 'note': ''} for row in source['artifacts']]}


def validate(worksheet, source):
    require(isinstance(worksheet, dict) and set(worksheet) == {'schema', 'reviewer', 'source', 'annotations'}, 'invalid worksheet fields')
    require(worksheet['schema'] == SCHEMA, 'unsupported worksheet schema')
    text(worksheet['reviewer'], 'reviewer', 256)
    require(worksheet['source'] == source, 'worksheet does not match this exact exported packet')
    annotations = worksheet['annotations']
    require(isinstance(annotations, list) and len(annotations) == len(source['artifacts']), 'incomplete annotations')
    for annotation, row in zip(annotations, source['artifacts']):
        require(isinstance(annotation, dict) and set(annotation) == {'artifact_id', 'state', 'note'}, 'invalid annotation fields')
        require(annotation['artifact_id'] == row['id'], 'annotation identity/order mismatch')
        require(annotation['state'] in STATES, 'invalid reviewer state')
        text(annotation['note'], 'note', 16384, False)
    return worksheet


def annotate(worksheet, changes):
    require(isinstance(changes, dict) and set(changes) == {'annotations'}, 'changes require only annotations')
    edits = changes['annotations']
    require(isinstance(edits, list) and 1 <= len(edits) <= 32, 'changes require 1..32 annotations')
    result = decode(json.dumps(worksheet, ensure_ascii=False).encode())
    index = {a['artifact_id']: a for a in result['annotations']}
    seen = set()
    for edit in edits:
        require(isinstance(edit, dict) and set(edit) == {'artifact_id', 'state', 'note'}, 'each edit needs artifact_id, state, note')
        key = text(edit['artifact_id'], 'artifact_id')
        require(key in index and key not in seen, 'unknown or repeated annotation id')
        seen.add(key)
        index[key].update(edit)
    return validate(result, worksheet['source'])


def escape(value):
    value = str(value).replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
    return re.sub(r'([\\`*_{}\[\]()#+.!|~>\-])', r'\\\1', value).replace('\r', '').replace('\n', '\n    ')


def markdown(worksheet):
    counts = {state: sum(a['state'] == state for a in worksheet['annotations']) for state in STATES}
    lines = ['# Artifact review notes', '', 'Local reviewer annotations only. No artifact acceptance, execution permission, or promotion.', '',
             'Reviewer: ' + escape(worksheet['reviewer']), '', 'Verified export manifest: ' + worksheet['source']['manifest_sha256'], '',
             '; '.join(f'{state}: {count}' for state, count in counts.items()), '']
    for row, annotation in zip(worksheet['source']['artifacts'], worksheet['annotations']):
        lines += ['## ' + escape(row['id']), '', f"Run: {escape(row['run_id'])}; job: {escape(row['job_id'])}", '',
                  f"Output: {escape(row['logical_key'] if row['logical_key'] is not None else '(no logical key)')}; revision {row['version']}; recorded state {row['status']}", '',
                  'Reviewer state: ' + annotation['state'], '', 'Note: ' + escape(annotation['note']), '',
                  f"[Open exported content]({row['content_path']}) · [Original record]({row['record_path']})", '',
                  'Content: ' + row['content_sha256'], '']
    return '\n'.join(lines) + '\n'


def main(argv=None):
    # Delay the optional CLI extension import: it reuses this module's worksheet
    # contract and does not alter the established single-reviewer operations.
    import artifact_review_collection as collection
    import artifact_review_progress as progress
    import artifact_review_coverage as coverage
    import artifact_review_transfer as transfer
    import artifact_review_csv as review_csv
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    collection.configure(commands)
    progress.configure(commands)
    coverage.configure(commands)
    transfer.configure(commands)
    review_csv.configure(commands)
    new = commands.add_parser('create', help='verify a portable export and make a blank worksheet')
    new.add_argument('packet')
    new.add_argument('--reviewer', required=True)
    edit = commands.add_parser('annotate', help='apply explicit notes and return a new worksheet')
    show = commands.add_parser('report', help='reverify copies and render saved annotations')
    for sub in (edit, show):
        sub.add_argument('packet')
        sub.add_argument('worksheet')
    edit.add_argument('--changes', required=True)
    show.add_argument('--markdown', action='store_true')
    args = parser.parse_args(argv)
    try:
        source = packet(args.packet)
        if args.command in ('export-csv', 'import-csv'):
            output = review_csv.execute(args, source)
            require(len(output.encode('utf-8')) <= MAX_JSON, 'CSV review result exceeds 4 MiB')
            sys.stdout.write(output)
            return 0
        if args.command in ('carry-notes', 'carried-worksheet', 'carried-report'):
            output = transfer.execute(args, source)
            require(len(output.encode('utf-8')) <= transfer.MAX_TRANSFER, 'carry-forward result exceeds 16 MiB')
            sys.stdout.write(output)
            return 0
        if args.command in ('collect', 'collection-report', 'collection-compare', 'review-plan', 'review-coverage'):
            if args.command in ('review-plan', 'review-coverage'):
                output = coverage.execute(args, source)
            else:
                output = progress.execute(args, source) if args.command == 'collection-compare' else collection.execute(args, source)
            require(len(output.encode('utf-8')) <= collection.MAX_COLLECTION, 'collection result exceeds 16 MiB')
            sys.stdout.write(output)
            return 0
        if args.command == 'create':
            result = create(source, args.reviewer)
        else:
            result = validate(decode(read(args.worksheet, MAX_JSON)), source)
            if args.command == 'annotate':
                result = annotate(result, decode(read(args.changes, MAX_JSON)))
        output = markdown(result) if args.command == 'report' and args.markdown else json.dumps(result, ensure_ascii=False, indent=2) + '\n'
        require(len(output.encode()) <= MAX_JSON, 'result exceeds 4 MiB')
        sys.stdout.write(output)
        return 0
    except (ValueError, OSError, UnicodeError, TypeError, RecursionError) as error:
        print('Artifact review refused: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
