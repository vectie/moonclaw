///|
fn comparison_test_root() -> String raise {
  // Preserve these small fixtures for inspection rather than cleaning them up.
  @fsx.mkdtemp("/tmp/moonclaw-artifact-comparison-XXXXXX")
}

///|
async fn comparison_test_pair(
  root : String,
) -> (ArtifactRecord, ArtifactRecord) {
  let artifacts = ArtifactStore::new(store=SystemStore::new(root~))
  let left = artifacts.write(
    ArtifactWriteRequest::new(
      run_id="run-old",
      job_id="job-review",
      artifact_type="report",
      logical_key=Some("result"),
      content_type="text/markdown",
      content="# Result\nOld detail\nUnchanged\n",
    ),
    "revision-old",
    100,
  )
  let right = artifacts.write(
    ArtifactWriteRequest::new(
      run_id="run-new",
      job_id="job-review",
      artifact_type="report",
      logical_key=Some("result"),
      content_type="text/markdown",
      content="# Result\nNew detail\nUnchanged\nAdded 🌙",
    ),
    "revision-new",
    200,
  )
  (left, right)
}

///|
async test "artifact comparison loads exact durable revisions without loading or repairing index" {
  let root = comparison_test_root()
  let (left, right) = comparison_test_pair(root)
  let store = SystemStore::new(root~)
  @fsx.write_to_file(
    store.artifacts_index_file(),
    "{intentionally-broken-cache",
  )
  let result = ArtifactStore::new(store~).compare_text(left.id, right.id)
  inspect(result.left.record.id, content="revision-old")
  inspect(result.right.record.run_id, content="run-new")
  inspect(result.left.record.version, content="1")
  inspect(result.right.record.version, content="2")
  inspect(result.diff.added_lines, content="2")
  inspect(result.diff.removed_lines, content="1")
  inspect(result.diff.unchanged_lines, content="2")
  assert_eq(
    result.left.content_sha256,
    @capability.sha256_digest_ref_v1(@fs.read_file(left.path).binary()).text(),
  )
  assert_eq(
    result.right.content_bytes,
    @fs.read_file(right.path).binary().length(),
  )
  assert_eq(
    @fsx.read_file(store.artifacts_index_file()),
    "{intentionally-broken-cache",
  )
  assert_eq(store.list_artifacts().length(), 0)
  let reverse = compare_retained_artifacts(root, right.id, left.id)
  assert_eq(reverse.diff.added_lines, result.diff.removed_lines)
  assert_eq(reverse.diff.removed_lines, result.diff.added_lines)
  assert_true(compare_retained_artifacts(root, left.id, left.id).diff.identical)
}

///|
async test "artifact comparison rejects different output lineage" {
  let root = comparison_test_root()
  let (left, right) = comparison_test_pair(root)
  let store = SystemStore::new(root~)
  for
    changed in [
      { ..right, job_id: "other-job", },
      { ..right, artifact_type: "other-type", },
      { ..right, logical_key: Some("other-key"), },
    ] {
    store.save_artifact(changed)
    assert_true(
      (try? compare_retained_artifacts(root, left.id, right.id)) is Err(_),
    )
  }
}

///|
async test "artifact comparison refuses missing record content deleted identity and binary" {
  let root = comparison_test_root()
  let (left, right) = comparison_test_pair(root)
  let store = SystemStore::new(root~)
  assert_true(
    (try? compare_retained_artifacts(root, "missing", right.id)) is Err(_),
  )
  for id in ["", ".", "..", "../revision-old", "bad/id", "bad\\id", "bad\n"] {
    assert_true((try? compare_retained_artifacts(root, id, right.id)) is Err(_))
  }
  store.save_artifact({ ..right, path: right.path + ".absent", })
  assert_true(
    (try? compare_retained_artifacts(root, left.id, right.id)) is Err(_),
  )
  store.save_artifact({ ..right, content_type: "image/png", })
  assert_true(
    (try? compare_retained_artifacts(root, left.id, right.id)) is Err(_),
  )
  store.save_artifact(right)
  @fs.write_file(right.path, b"invalid\xff")
  assert_true(
    (try? compare_retained_artifacts(root, left.id, right.id)) is Err(_),
  )
  @fs.write_file(right.path, b"a\x00b")
  assert_true(
    (try? compare_retained_artifacts(root, left.id, right.id)) is Err(_),
  )
  @fs.write_file(right.path, b"valid")
  @fsx.make_directory(
    @pathx.join(root, "index/deleted-artifacts"),
    recursive=true,
  )
  write_artifact_checkpoint(store.artifact_deleted_file(right.id), b"{}")
  assert_true(
    (try? compare_retained_artifacts(root, left.id, right.id)) is Err(_),
  )
}

///|
async test "artifact comparison binds checkpoint identity and validates numeric version" {
  let root = comparison_test_root()
  let (left, right) = comparison_test_pair(root)
  let store = SystemStore::new(root~)
  @fsx.write_to_file(
    store.artifact_record_file(right.id),
    left.to_json().stringify(),
  )
  assert_true(
    (try? compare_retained_artifacts(root, left.id, right.id)) is Err(_),
  )
  @fsx.write_to_file(
    store.artifact_record_file(right.id),
    right
    .to_json()
    .stringify()
    .replace(old="\"version\":2", new="\"version\":2.5"),
  )
  assert_true(
    (try? compare_retained_artifacts(root, left.id, right.id)) is Err(_),
  )
  @fsx.write_to_file(store.artifact_record_file(right.id), "{broken")
  assert_true(
    (try? compare_retained_artifacts(root, left.id, right.id)) is Err(_),
  )
  store.save_artifact({ ..right, path: left.path, })
  assert_true(
    (try? compare_retained_artifacts(root, left.id, right.id)) is Err(_),
  )
}

///|
async test "artifact comparison supports archived JSON with exact newline and Unicode bytes" {
  let root = comparison_test_root()
  let (left, right) = comparison_test_pair(root)
  let store = SystemStore::new(root~)
  store.save_artifact({
    ..left,
    status: Archived,
    content_type: "application/json; charset=utf-8",
  })
  store.save_artifact({ ..right, content_type: "application/example+json", })
  @fs.write_file(left.path, @encoding/utf8.encode("{\"moon\":\"🌙\"}\r\n"))
  @fs.write_file(right.path, @encoding/utf8.encode("{\"moon\":\"🌙\"}\n"))
  let result = compare_retained_artifacts(root, left.id, right.id)
  assert_true(result.left.record.status is Archived)
  inspect(result.diff.removed_lines, content="1")
  inspect(result.diff.added_lines, content="1")
  assert_true(result.to_markdown().contains("CRLF"))
}

///|
async test "artifact comparison limits file size before reading and retains literal Markdown" {
  let root = comparison_test_root()
  let (left, right) = comparison_test_pair(root)
  let large = @fs.create(right.path)
  large.write_at(b"x", position=1048576L)
  large.close()
  assert_true(
    (try? compare_retained_artifacts(root, left.id, right.id)) is Err(_),
  )
  @fs.write_file(
    right.path,
    @encoding/utf8.encode(
      "<script>alert(1)</script>\n![x](https://example.test)\n",
    ),
  )
  let result = compare_retained_artifacts(root, left.id, right.id)
  let markdown = result.to_markdown()
  assert_false(markdown.contains("<script>"))
  assert_false(markdown.contains("![x]("))
  assert_true(markdown.contains("&lt;script&gt;"))
  assert_true(markdown.contains("revision\\-old"))
  assert_true(markdown.contains("version 2"))
}
