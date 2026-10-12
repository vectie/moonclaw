"""CSV editing exchange for the existing exact-revision review worksheet."""
import csv
import io
import json

from artifact_review import MAX_JSON, annotate, decode, read, require, sha, validate

SCHEMA = 'moonclaw.artifact-review-csv.v1'
COLUMNS = ('schema', 'manifest_sha256', 'worksheet_sha256', 'reviewer', 'artifact_id',
           'run_id', 'job_id', 'revision', 'content_path', 'content_sha256', 'state',
           'note', 'text_prefixed_columns')
TEXT_COLUMNS = tuple(name for name in COLUMNS if name not in ('revision', 'state', 'text_prefixed_columns'))
EDITABLE = ('state', 'note')


def configure(commands):
    export = commands.add_parser('export-csv', help='export worksheet rows for local CSV editing')
    intake = commands.add_parser('import-csv', help='apply edited CSV rows to the exact base worksheet')
    for command in (export, intake):
        command.add_argument('packet')
        command.add_argument('worksheet', help='the unchanged base worksheet used for CSV export')
    export.add_argument('--artifact', action='append', help='exact artifact ID; repeat for an explicit subset')
    intake.add_argument('csv', help='edited UTF-8 CSV; omitted rows preserve their annotations')
    intake.add_argument('--preview', action='store_true', help='show complete before/after changes instead of a new worksheet')


def fields(worksheet, worksheet_digest, artifact, annotation):
    return dict(zip(COLUMNS, (SCHEMA, worksheet['source']['manifest_sha256'], worksheet_digest,
                             worksheet['reviewer'], artifact['id'], artifact['run_id'], artifact['job_id'],
                             str(artifact['version']), artifact['content_path'], artifact['content_sha256'],
                             annotation['state'], annotation['note'], '')))


def protect(row):
    """Use the journal CSV's reversible apostrophe convention, never evaluate cells."""
    result = dict(row)
    prefixed = []
    for name in TEXT_COLUMNS:
        value = row[name].lstrip(' ')
        if value and value[0] in "=+-@'\t\r\n\ufeff":
            result[name] = "'" + row[name]
            prefixed.append(name)
    result['text_prefixed_columns'] = ';'.join(prefixed)
    return result


def unprotect(row):
    result = dict(row)
    marked = row['text_prefixed_columns'].split(';') if row['text_prefixed_columns'] else []
    require(len(marked) == len(set(marked)) and all(name in TEXT_COLUMNS for name in marked),
            'invalid text_prefixed_columns; retain only text column names separated by semicolons')
    for name in marked:
        require(row[name].startswith("'"),
                f"{name} is listed in text_prefixed_columns but has no leading apostrophe; "
                'preserve that prefix or remove the column name from the list after editing')
        result[name] = row[name][1:]
    return result


def export_csv(worksheet, fingerprint, selected=None):
    known = {row['id'] for row in worksheet['source']['artifacts']}
    if selected is not None:
        require(len(selected) == len(set(selected)) and all(key in known for key in selected),
                'unknown or repeated selected artifact ID')
    stream = io.StringIO(newline='')
    writer = csv.DictWriter(stream, COLUMNS, quoting=csv.QUOTE_ALL, lineterminator='\r\n')
    writer.writeheader()
    for artifact, annotation in zip(worksheet['source']['artifacts'], worksheet['annotations']):
        if selected is None or artifact['id'] in selected:
            writer.writerow(protect(fields(worksheet, fingerprint, artifact, annotation)))
    return stream.getvalue()


def edits_from_csv(raw, worksheet, fingerprint):
    # The read and field limits bound parsing; no delimiter guessing or type coercion.
    previous_limit = csv.field_size_limit(MAX_JSON)
    try:
        reader = csv.reader(io.StringIO(raw.decode('utf-8-sig'), newline=''), strict=True)
        header = next(reader, [])
        require(len(header) == len(COLUMNS) and set(header) == set(COLUMNS),
                'CSV must retain every exported column exactly once')
        index = {row['id']: (row, annotation) for row, annotation in
                 zip(worksheet['source']['artifacts'], worksheet['annotations'])}
        changes, seen = [], set()
        for cells in reader:
            if not cells:  # Spreadsheet-added empty physical lines carry no annotation.
                continue
            require(len(changes) < 32 and len(cells) == len(COLUMNS), 'CSV requires at most 32 complete rows')
            row = unprotect(dict(zip(header, cells)))
            identity = row['artifact_id']
            require(identity in index and identity not in seen, 'unknown or repeated CSV artifact ID')
            seen.add(identity)
            artifact, annotation = index[identity]
            expected = fields(worksheet, fingerprint, artifact, annotation)
            for name in COLUMNS:
                if name not in (*EDITABLE, 'text_prefixed_columns'):
                    require(row[name] == expected[name],
                            f'CSV reference field {name} changed for {identity}; use the original base worksheet or export again')
            changes.append({'artifact_id': identity, 'state': row['state'], 'note': row['note']})
        require(changes, 'CSV contains no review rows; export or retain at least one artifact row')
        # Apply validation before either preview or worksheet output.
        updated = annotate(worksheet, {'annotations': changes})
        return updated, seen
    except csv.Error as error:
        raise ValueError('invalid review CSV: ' + str(error)) from error
    finally:
        csv.field_size_limit(previous_limit)


def preview(worksheet, updated, selected, fingerprint, csv_digest):
    changes = []
    for artifact, before, after in zip(worksheet['source']['artifacts'], worksheet['annotations'], updated['annotations']):
        if before != after:
            changes.append({'artifact': artifact, 'before': before, 'after': after})
    return {'schema': 'moonclaw.artifact-review-csv-preview.v1',
            'meaning': 'Local reviewer note edits only; inspected is not acceptance.',
            'manifest_sha256': worksheet['source']['manifest_sha256'],
            'worksheet_sha256': fingerprint, 'csv_sha256': csv_digest, 'reviewer': worksheet['reviewer'],
            'summary': {'selected_artifacts': len(selected), 'changed_artifacts': len(changes),
                        'unchanged_selected_artifacts': len(selected) - len(changes),
                        'omitted_artifacts': len(worksheet['annotations']) - len(selected)},
            'selected_artifact_ids': [row['artifact_id'] for row in worksheet['annotations'] if row['artifact_id'] in selected],
            'changes': changes}


def execute(args, source):
    worksheet_raw = read(args.worksheet, MAX_JSON)
    worksheet = validate(decode(worksheet_raw), source)
    fingerprint = sha(worksheet_raw)
    if args.command == 'export-csv':
        return export_csv(worksheet, fingerprint, args.artifact)
    csv_raw = read(args.csv, MAX_JSON)
    updated, selected = edits_from_csv(csv_raw, worksheet, fingerprint)
    result = preview(worksheet, updated, selected, fingerprint, sha(csv_raw)) if args.preview else updated
    return json.dumps(result, ensure_ascii=False, indent=2) + '\n'
