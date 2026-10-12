"""Multi-reviewer inspection of the existing revision-bound review worksheets."""
import json

from artifact_review import MAX_JSON, STATES, decode, digest, escape, read, require, sha, text, validate

SCHEMA = 'moonclaw.artifact-review-collection.v1'
MAX_COLLECTION = 16 * 1024 * 1024
MAX_WORKSHEETS = 16
MAX_COMBINED_WORKSHEETS = 8 * 1024 * 1024
FOCUSES = ('all', 'needs-changes', 'mixed-states', 'pending')


def configure(commands):
    collect = commands.add_parser('collect', help='save independent reviewer worksheets together for one exact packet')
    collect.add_argument('packet')
    collect.add_argument('worksheets', nargs='+')
    collect.add_argument('--title', default='Artifact feedback collection')
    report = commands.add_parser('collection-report', help='reverify and explore a saved feedback collection')
    report.add_argument('packet')
    report.add_argument('collection')
    report.add_argument('--focus', choices=FOCUSES, default='all')
    report.add_argument('--artifact', help='exact artifact ID; combines with focus')
    report.add_argument('--markdown', action='store_true')


def unpack(collection, source):
    require(isinstance(collection, dict) and set(collection) == {'schema', 'title', 'source', 'reviews'},
            'invalid feedback collection fields')
    require(collection['schema'] == SCHEMA, 'unsupported feedback collection schema')
    text(collection['title'], 'collection title')
    require(collection['source'] == source, 'collection does not match this exact exported packet')
    reviews = collection['reviews']
    require(isinstance(reviews, list) and 1 <= len(reviews) <= MAX_WORKSHEETS,
            'collection requires 1..16 worksheets')
    reviewers, worksheets, total = set(), [], 0
    for entry in reviews:
        require(isinstance(entry, dict) and set(entry) == {'worksheet_sha256', 'worksheet_json'},
                'invalid embedded worksheet fields')
        raw_text = entry['worksheet_json']
        require(isinstance(raw_text, str), 'embedded worksheet must be JSON text')
        raw = raw_text.encode('utf-8')
        total += len(raw)
        require(len(raw) <= MAX_JSON and total <= MAX_COMBINED_WORKSHEETS,
                'worksheets exceed 4 MiB each or 8 MiB combined')
        require(sha(raw) == digest(entry['worksheet_sha256']), 'embedded worksheet fingerprint changed')
        worksheet = validate(decode(raw), source)
        key = worksheet['reviewer'].strip().casefold()
        require(key not in reviewers, 'repeated reviewer label; choose one worksheet per reviewer')
        reviewers.add(key)
        worksheets.append((worksheet, entry['worksheet_sha256']))
    return worksheets


def collect(source, paths, title):
    require(1 <= len(paths) <= MAX_WORKSHEETS, 'collect requires 1..16 worksheets')
    result = {'schema': SCHEMA, 'title': text(title, 'collection title'), 'source': source, 'reviews': []}
    total = 0
    for path in paths:
        raw = read(path, MAX_JSON)
        total += len(raw)
        require(total <= MAX_COMBINED_WORKSHEETS, 'worksheets exceed 8 MiB combined')
        result['reviews'].append({'worksheet_sha256': sha(raw), 'worksheet_json': raw.decode('utf-8')})
    unpack(result, source)
    return result


def report(collection, source, focus='all', artifact_id=None):
    worksheets = unpack(collection, source)
    require(focus in FOCUSES, 'unsupported collection focus')
    require(artifact_id is None or any(row['id'] == artifact_id for row in source['artifacts']),
            'artifact ID is absent from this packet')
    summary = {name: 0 for name in ('needs-changes', 'mixed-states', 'pending', 'all-inspected')}
    rows = []
    for index, artifact in enumerate(source['artifacts']):
        feedback = [{'reviewer': sheet['reviewer'], 'worksheet_sha256': fingerprint,
                     'state': sheet['annotations'][index]['state'], 'note': sheet['annotations'][index]['note']}
                    for sheet, fingerprint in worksheets]
        counts = {state: sum(item['state'] == state for item in feedback) for state in STATES}
        flags = []
        if counts['needs-changes']:
            flags.append('needs-changes')
        if sum(count > 0 for count in counts.values()) > 1:
            flags.append('mixed-states')
        if counts['unreviewed']:
            flags.append('pending')
        if counts['inspected'] == len(worksheets):
            flags.append('all-inspected')
        for flag in flags:
            summary[flag] += 1
        if (focus == 'all' or focus in flags) and (artifact_id is None or artifact['id'] == artifact_id):
            rows.append(dict(artifact, counts=counts, flags=flags, reviews=feedback))
    return {'schema': 'moonclaw.artifact-review-collection-report.v1', 'title': collection['title'],
            'manifest_sha256': source['manifest_sha256'],
            'reviewers': [{'reviewer': sheet['reviewer'], 'worksheet_sha256': fingerprint}
                          for sheet, fingerprint in worksheets],
            'filter': {'focus': focus, 'artifact_id': artifact_id},
            'total_artifacts': len(source['artifacts']), 'matched_artifacts': len(rows),
            'summary': summary, 'artifacts': rows}


def markdown(value):
    lines = ['# ' + escape(value['title']), '',
             'Collected reviewer statements only. No owner acceptance, execution permission, or majority decision.', '',
             'Verified export manifest: ' + value['manifest_sha256'], '',
             f"Showing {value['matched_artifacts']} of {value['total_artifacts']} artifacts; focus: {value['filter']['focus']}", '',
             'Whole-collection counts (overlapping): ' + '; '.join(f'{key}: {count}' for key, count in value['summary'].items()), '',
             'Mixed states include unreviewed entries; they are not necessarily a disagreement. All-inspected is not acceptance.', '',
             '## Included reviewers', '']
    if value['filter']['artifact_id'] is not None:
        lines += ['Artifact filter: ' + escape(value['filter']['artifact_id']), '']
    for reviewer in value['reviewers']:
        lines += ['- ' + escape(reviewer['reviewer']) + ': ' + reviewer['worksheet_sha256']]
    lines.append('')
    if not value['artifacts']:
        lines += ['No artifacts match this selection. The complete collection was still verified.', '']
    for row in value['artifacts']:
        lines += ['## ' + escape(row['id']), '',
                  f"Run: {escape(row['run_id'])}; job: {escape(row['job_id'])}", '',
                  f"Output: {escape(row['logical_key'] if row['logical_key'] is not None else '(no logical key)')}; revision {row['version']}; recorded state {row['status']}", '',
                  'Review counts: ' + '; '.join(f'{key}: {count}' for key, count in row['counts'].items()), '',
                  'View flags: ' + ', '.join(row['flags']), '',
                  f"[Open exported content]({row['content_path']}) · [Original record]({row['record_path']})", '',
                  'Content: ' + row['content_sha256'], '']
        for feedback in row['reviews']:
            lines += ['### ' + escape(feedback['reviewer']) + ': ' + feedback['state'], '',
                      'Note: ' + escape(feedback['note']), '',
                      'Worksheet: ' + feedback['worksheet_sha256'], '']
    return '\n'.join(lines) + '\n'


def execute(args, source):
    if args.command == 'collect':
        value = collect(source, args.worksheets, args.title)
    else:
        collection = decode(read(args.collection, MAX_COLLECTION))
        value = report(collection, source, args.focus, args.artifact)
        if args.markdown:
            return markdown(value)
    return json.dumps(value, ensure_ascii=False, indent=2) + '\n'
