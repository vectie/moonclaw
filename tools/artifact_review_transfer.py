"""Carry explicitly selected old notes into reinspection of supplied new copies."""
import json

from artifact_review import (MAX_JSON, create, decode, digest, escape, packet, read,
                             require, sha, text, validate)

SCHEMA = 'moonclaw.artifact-review-transfer.v1'
MAX_TRANSFER = 16 * 1024 * 1024


def configure(commands):
    transfer = commands.add_parser('carry-notes', help='map selected prior notes to a different verified packet for reinspection')
    transfer.add_argument('packet', help='new target packet')
    transfer.add_argument('previous_packet')
    transfer.add_argument('worksheet', help='worksheet for the previous packet')
    transfer.add_argument('mapping', help='explicit from_artifact/to_artifact pairs')
    for name, description in [('carried-worksheet', 'export a fresh unreviewed worksheet from a saved carry-forward'),
                              ('carried-report', 'inspect exact carried notes and both revision identities')]:
        command = commands.add_parser(name, help=description)
        command.add_argument('packet')
        command.add_argument('previous_packet')
        command.add_argument('transfer')
        if name == 'carried-report':
            command.add_argument('--markdown', action='store_true')


def mappings(value, before, after):
    require(isinstance(value, dict) and set(value) == {'mappings'}, 'mapping input requires only mappings')
    rows = value['mappings']
    require(isinstance(rows, list) and 1 <= len(rows) <= 32, 'choose 1..32 explicit mappings')
    old = {row['id'] for row in before['artifacts']}
    new = {row['id'] for row in after['artifacts']}
    left, right = set(), set()
    for row in rows:
        require(isinstance(row, dict) and set(row) == {'from_artifact', 'to_artifact'}, 'each mapping needs from_artifact and to_artifact')
        a, b = text(row['from_artifact'], 'from_artifact'), text(row['to_artifact'], 'to_artifact')
        require(a in old and b in new, 'mapping must name exact known artifacts in the selected packets')
        require(a not in left and b not in right, 'mapping must be one-to-one; repeated source or target')
        left.add(a); right.add(b)
    return rows


def unpack(value, before, after):
    require(isinstance(value, dict) and set(value) == {'schema', 'target_source', 'previous_worksheet_sha256', 'previous_worksheet_json', 'mappings'}, 'invalid carry-forward fields')
    require(value['schema'] == SCHEMA, 'unsupported carry-forward schema')
    require(before != after, 'carry-forward needs different exact packets; use annotate for the same packet')
    require(value['target_source'] == after, 'carry-forward does not match this exact target packet')
    raw = value['previous_worksheet_json']
    require(isinstance(raw, str) and len(raw.encode('utf-8')) <= MAX_JSON, 'invalid embedded previous worksheet')
    require(sha(raw.encode('utf-8')) == digest(value['previous_worksheet_sha256']), 'previous worksheet fingerprint changed')
    sheet = validate(decode(raw.encode('utf-8')), before)
    return sheet, mappings({'mappings': value['mappings']}, before, after)


def worksheet(value, before, after):
    old, selected = unpack(value, before, after)
    result = create(after, old['reviewer'])
    annotations = {row['artifact_id']: row for row in old['annotations']}
    targets = {row['artifact_id']: row for row in result['annotations']}
    for mapping in selected:
        prior = annotations[mapping['from_artifact']]
        prefix = ('Carried prior-revision note; this target still requires inspection.\n'
                  'Source manifest: ' + before['manifest_sha256'] + '\n'
                  'Source artifact: ' + json.dumps(prior['artifact_id'], ensure_ascii=False) + '\n'
                  'Prior checklist state: ' + prior['state'] + '\nPrior note:\n')
        note = prefix + prior['note']
        require(len(note) <= 16384, 'carried note and provenance exceed 16384 characters; shorten the prior worksheet note explicitly before carrying')
        targets[mapping['to_artifact']]['note'] = note
    return validate(result, after)


def report(value, before, after):
    sheet, selected = unpack(value, before, after)
    left = {row['id']: row for row in before['artifacts']}
    right = {row['id']: row for row in after['artifacts']}
    annotations = {row['artifact_id']: row for row in sheet['annotations']}
    return dict(schema='moonclaw.artifact-review-transfer-report.v1', reviewer=sheet['reviewer'],
                previous_worksheet_sha256=value['previous_worksheet_sha256'],
                previous_manifest_sha256=before['manifest_sha256'], target_manifest_sha256=after['manifest_sha256'],
                mappings=[dict(previous=left[row['from_artifact']], target=right[row['to_artifact']],
                               previous_annotation=annotations[row['from_artifact']], target_state='unreviewed',
                               content_relation='same-bytes' if left[row['from_artifact']]['content_sha256'] == right[row['to_artifact']]['content_sha256'] else 'different-bytes') for row in selected],
                uncarried_previous_artifacts=[row for row in before['artifacts'] if row['id'] not in {v['from_artifact'] for v in selected}],
                blank_target_artifacts=[row for row in after['artifacts'] if row['id'] not in {v['to_artifact'] for v in selected}])


def markdown(value):
    lines = ['# Carry prior notes into reinspection', '',
             'Explicit correspondence chosen by the operator, not proven revision ancestry. All target states are unreviewed.', '',
             'Reviewer label: ' + escape(value['reviewer']), '',
             'Previous manifest: ' + value['previous_manifest_sha256'], '',
             'Target manifest: ' + value['target_manifest_sha256'], '',
             'Previous worksheet: ' + value['previous_worksheet_sha256'], '',
             'No files are sent, no runtime state changes, and no inspection or acceptance is inferred.', '']
    for row in value['mappings']:
        a, b, note = row['previous'], row['target'], row['previous_annotation']
        lines += ['## ' + escape(a['id']) + ' → ' + escape(b['id']), '',
                  f"Previous run/job: {escape(a['run_id'])} / {escape(a['job_id'])}; revision {a['version']}", '',
                  f"Target run/job: {escape(b['run_id'])} / {escape(b['job_id'])}; revision {b['version']}", '',
                  'Previous content: ' + a['content_sha256'], '', 'Target content: ' + b['content_sha256'], '',
                  'Content comparison: ' + row['content_relation'] + '; target: unreviewed', '',
                  'Prior state: ' + note['state'], '', 'Prior note: ' + escape(note['note']), '']
    lines += ['Previous artifacts not carried: ' + str(len(value['uncarried_previous_artifacts'])), '',
              'Target artifacts starting blank: ' + str(len(value['blank_target_artifacts'])), '',
              'Keep both packets and the saved carry-forward to retain complete provenance. No path here implies a shared directory.', '']
    for label, key in [('Not carried', 'uncarried_previous_artifacts'), ('Blank target', 'blank_target_artifacts')]:
        lines.extend(label + ': ' + escape(row['id']) for row in value[key])
    return '\n'.join(lines) + '\n'


def execute(args, after):
    before = packet(args.previous_packet)
    if args.command == 'carry-notes':
        raw = read(args.worksheet, MAX_JSON)
        value = dict(schema=SCHEMA, target_source=after, previous_worksheet_sha256=sha(raw),
                     previous_worksheet_json=raw.decode('utf-8'),
                     mappings=mappings(decode(read(args.mapping, MAX_JSON)), before, after))
        worksheet(value, before, after)  # Refuse a handoff that cannot yield a valid worksheet.
    else:
        value = decode(read(args.transfer, MAX_TRANSFER))
        fresh = worksheet(value, before, after)
        if args.command == 'carried-worksheet':
            output = json.dumps(fresh, ensure_ascii=False, indent=2) + '\n'
            require(len(output.encode('utf-8')) <= MAX_JSON, 'carried worksheet exceeds 4 MiB')
            return output
        value = report(value, before, after)
        if args.markdown:
            return markdown(value)
    return json.dumps(value, ensure_ascii=False, indent=2) + '\n'
