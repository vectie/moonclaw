///|
fn search_test_store() -> (String, SystemStore, ArtifactStore) raise {
  let root = @fsx.mkdtemp("/tmp/moonclaw-artifact-search-XXXXXX")
  let store = SystemStore::new(root=@pathx.join(root, "store"))
  let artifacts = ArtifactStore::new(store~)
  (root, store, artifacts)
}

///|
async fn search_test_write(
  artifacts : ArtifactStore,
  id : String,
  content : String,
  job_id~ : String = "job-search",
  run_id~ : String = "run-search",
) -> ArtifactRecord {
  artifacts.write(
    ArtifactWriteRequest::new(
      run_id~,
      job_id~,
      artifact_type="report",
      logical_key=Some("release"),
      scope=["review"],
      content~,
    ),
    id,
    123,
  )
}

///|
async test "artifact search finds exact archived and active revisions with source filters and no index repair" {
  let (_, store, artifacts) = search_test_store()
  let old = search_test_write(
    artifacts,
    "a-old",
    "first\nrelease ready\n",
    run_id="run-old",
  )
  ignore(
    search_test_write(
      artifacts,
      "b-new",
      "release ready twice\nrelease ready\n",
      run_id="run-new",
    ),
  )
  ignore(
    search_test_write(artifacts, "c-other", "release ready", job_id="different"),
  )
  store.save_artifact({ ..old, status: Archived, })
  @fsx.write_to_file(store.artifacts_index_file(), "{broken index")
  let result = search_retained_artifacts(
    store.root,
    query=ArtifactQuery::new(job_id=Some("job-search")),
    text=Some("release ready"),
  )
  assert_eq(result.matching_artifacts, 2)
  assert_eq(result.matches[0].record.id, "a-old")
  assert_true(result.matches[0].record.status is Archived)
  assert_eq(result.matches[0].lines[0].line, 2)
  assert_eq(result.matches[1].matching_lines, 2)
  assert_eq(
    result.matches[0].content_sha256,
    @capability.sha256_digest_ref_v1(b"first\nrelease ready\n").text(),
  )
  assert_eq(@fsx.read_file(store.artifacts_index_file()), "{broken index")
  let query = ArtifactQuery::new(
    job_id=Some("job-search"),
    run_id=Some("run-new"),
    artifact_type=Some("report"),
    logical_key=Some("release"),
    scope=Some("review"),
    status=Some(Active),
  )
  let selected = search_retained_artifacts(
    store.root,
    query~,
    text=Some("release"),
  )
  assert_eq(selected.matches.length(), 1)
  assert_eq(selected.matches[0].record.id, "b-new")
  assert_eq(
    search_retained_artifacts(store.root, query={
      ..query,
      scope: Some("none"),
    }).matches.length(),
    0,
  )
  assert_eq(
    search_retained_artifacts(store.root, text=Some("Release")).matches.length(),
    0,
  )
}

///|
async test "artifact search catalogs binary and empty output and discloses nontext and malformed UTF8" {
  let (_, store, artifacts) = search_test_store()
  let binary = search_test_write(artifacts, "binary", "")
  @fsx.write_bytes_to_file(binary.path, b"\x00\xff")
  store.save_artifact({ ..binary, content_type: "image/png", })
  ignore(search_test_write(artifacts, "empty", ""))
  let invalid = search_test_write(artifacts, "invalid", "")
  @fsx.write_bytes_to_file(invalid.path, b"\xff")
  let all = search_retained_artifacts(store.root)
  assert_eq(all.matches.length(), 3)
  assert_eq(all.matches[0].content_bytes, 2)
  assert_eq(all.matches[1].content_bytes, 0)
  let text = search_retained_artifacts(store.root, text=Some("needle"))
  assert_eq(text.excluded_nontext, 1)
  assert_eq(text.issues.length(), 1)
  assert_eq(text.issues[0].artifact_id, "invalid")
  assert_eq(text.matching_artifacts, 0)
}

///|
async test "artifact search returns bounded Unicode snippets and literal single-line matches" {
  let (_, store, artifacts) = search_test_store()
  let prefix = Array::make(270, "🌙").join("")
  ignore(
    search_test_write(
      artifacts,
      "literal",
      prefix + "[Moon]🌙 tail\r\n[Moon]\n[Moon]\n[Moon]\n",
    ),
  )
  let result = search_retained_artifacts(store.root, text=Some("[Moon]🌙"))
  assert_eq(result.matches.length(), 1)
  assert_true(result.matches[0].lines[0].excerpt.contains("[Moon]🌙"))
  assert_true(result.matches[0].lines[0].excerpt.has_prefix("…"))
  assert_true(result.matches[0].lines[0].excerpt.iter().count() <= 242)
  let all = search_retained_artifacts(store.root, text=Some("[Moon]"))
  assert_eq(all.matches[0].matching_lines, 4)
  assert_eq(all.matches[0].lines.length(), 3)
  assert_true(all.to_text().contains("first 3 shown"))
  for needle in ["", "a\nb", "a\rb", Array::make(129, "x").join("")] {
    assert_true(
      (Ok(search_retained_artifacts(store.root, text=Some(needle))) catch {
        error => Err(error)
      })
      is Err(_),
    )
  }
  for limit in [0, 33] {
    assert_true(
      (Ok(search_retained_artifacts(store.root, limit~)) catch {
        error => Err(error)
      })
      is Err(_),
    )
  }
}

///|
async test "artifact search reports partial checkpoints and ignores retained deletions" {
  let (root, store, artifacts) = search_test_store()
  ignore(search_test_write(artifacts, "a-good", "needle"))
  let broken = search_test_write(artifacts, "b-broken", "needle")
  @fsx.write_to_file(store.artifact_record_file(broken.id), "{broken")
  let deleted = search_test_write(artifacts, "c-deleted", "needle")
  @fsx.make_directory(
    @pathx.dirname(store.artifact_deleted_file(deleted.id)),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(store.artifact_deleted_file(deleted.id), "{}")
  let result = search_retained_artifacts(store.root, text=Some("needle"))
  assert_eq(result.matches.length(), 1)
  assert_eq(result.deleted_records, 1)
  assert_eq(result.issues.length(), 1)
  let output = @pathx.join(root, "refused")
  assert_true(
    (Ok(result.export_selected(output)) catch { error => Err(error) }) is Err(_),
  )
  assert_false(@fsx.exists(output))
}

///|
async test "artifact search exports the complete observed exact selection and rejects changed or truncated results" {
  let (root, store, artifacts) = search_test_store()
  let first = search_test_write(artifacts, "a", "match A")
  ignore(search_test_write(artifacts, "b", "match B"))
  let raw = first.to_json().stringify()
  @fsx.write_to_file(
    store.artifact_record_file(first.id),
    "{\"future\":7," + raw[1:].to_owned(),
  )
  let full = search_retained_artifacts(store.root, text=Some("match"))
  let exported = full.export_selected(@pathx.join(root, "selected"))
  assert_eq(exported.artifacts.length(), 2)
  assert_eq(
    exported.artifacts[0].content_sha256,
    full.matches[0].content_sha256,
  )
  assert_eq(
    @fsx.read_file(@pathx.join(root, "selected/records/1.json")),
    @fsx.read_file(store.artifact_record_file("a")),
  )
  let limited = search_retained_artifacts(
    store.root,
    text=Some("match"),
    limit=1,
  )
  assert_true(limited.truncated)
  assert_eq(limited.matching_artifacts, 2)
  assert_true(
    (Ok(limited.export_selected(@pathx.join(root, "truncated"))) catch {
      error => Err(error)
    })
    is Err(_),
  )
  assert_false(@fsx.exists(@pathx.join(root, "truncated")))
  @fsx.write_to_file(first.path, "match altered")
  assert_true(
    (Ok(full.export_selected(@pathx.join(root, "changed"))) catch {
      error => Err(error)
    })
    is Err(_),
  )
  assert_false(@fsx.exists(@pathx.join(root, "changed")))
  @fsx.write_to_file(first.path, "match A")
  store.save_artifact({ ..first, status: Archived, })
  assert_true(
    (Ok(full.export_selected(@pathx.join(root, "metadata-changed"))) catch {
      error => Err(error)
    })
    is Err(_),
  )
  assert_false(@fsx.exists(@pathx.join(root, "metadata-changed")))
}

///|
async test "artifact search text output escapes terminal and newline content and no match exports nothing" {
  let (root, store, artifacts) = search_test_store()
  ignore(
    search_test_write(artifacts, "a", "needle\u001b[31m\n", job_id="fake\nrow"),
  )
  let result = search_retained_artifacts(store.root, text=Some("needle"))
  let rendered = result.to_text()
  assert_false(rendered.contains("\u001b"))
  assert_false(rendered.contains("fake\nrow"))
  assert_true(rendered.contains("Runtime evidence only"))
  let empty = search_retained_artifacts(store.root, text=Some("missing"))
  assert_true(
    (Ok(empty.export_selected(@pathx.join(root, "empty"))) catch {
      error => Err(error)
    })
    is Err(_),
  )
  assert_false(@fsx.exists(@pathx.join(root, "empty")))
}
