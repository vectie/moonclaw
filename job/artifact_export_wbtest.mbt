///|
async fn export_test_store() -> (String, SystemStore, ArtifactStore) {
  let root = @fsx.mkdtemp("/tmp/moonclaw-artifact-export-XXXXXX")
  let store = SystemStore::new(root=@pathx.join(root, "store"))
  let artifacts = ArtifactStore::new(store~)
  (root, store, artifacts)
}

///|
async fn export_test_write(
  artifacts : ArtifactStore,
  id : String,
  content : Bytes,
  file_name~ : String = "content.bin",
) -> ArtifactRecord {
  artifacts.write_bytes(
    {
      run_id: "run-" + id,
      job_id: "job-export",
      artifact_type: "result",
      logical_key: Some("final"),
      content_type: "application/octet-stream",
      file_name: Some(file_name),
      metadata: { "fixture": "synthetic local producer" },
      scope: ["review"],
      content,
      append_only: true,
    },
    id,
    123,
  )
}

///|
async test "artifact export copies producer binary text and exact records across revisions without index repair" {
  let (root, store, artifacts) = export_test_store()
  let left = export_test_write(
    artifacts,
    "old",
    b"\xef\xbb\xbfhello\r\n",
    file_name="report.txt",
  )
  let right = export_test_write(
    artifacts,
    "new",
    b"\x00\xff\xfe\x80",
    file_name="image.bin",
  )
  store.save_artifact({ ..left, status: Archived, })
  let left_record = @fs.read_file(store.artifact_record_file(left.id)).binary()
  @fsx.write_to_file(store.artifacts_index_file(), "{broken index")
  let destination = @pathx.join(root, "export")
  let result = artifacts.export_selected(["old", "new"], destination)
  inspect(result.schema, content="moonclaw.artifact-export.v1")
  inspect(result.artifacts.length(), content="2")
  inspect(result.total_content_bytes, content="14")
  inspect(result.artifacts[0].record.version, content="1")
  inspect(result.artifacts[1].record.version, content="2")
  assert_true(result.artifacts[0].record.status is Archived)
  assert_eq(result.artifacts[1].record.run_id, "run-new")
  assert_eq(
    @fs.read_file(@pathx.join(destination, result.artifacts[0].record_path)).binary(),
    left_record,
  )
  for entry in result.artifacts {
    let content = @fs.read_file(@pathx.join(destination, entry.content_path)).binary()
    assert_eq(content, @fs.read_file(entry.record.path).binary())
    assert_eq(
      entry.content_sha256,
      @capability.sha256_digest_ref_v1(content).text(),
    )
  }
  assert_eq(
    @json.parse(@fsx.read_file(@pathx.join(destination, "manifest.json"))),
    result.to_json(),
  )
  assert_eq(@fsx.read_file(store.artifacts_index_file()), "{broken index")
  assert_eq(@fs.read_file(right.path).binary(), b"\x00\xff\xfe\x80")
  assert_true(result.to_readme().contains("revision 2"))
  assert_true(result.to_readme().contains("Runtime evidence only"))
}

///|
async test "artifact export retains original future metadata fields and safe collision-free filenames" {
  let (root, store, artifacts) = export_test_store()
  let a = export_test_write(artifacts, "a", b"", file_name="same 🌙.txt")
  let b = export_test_write(artifacts, "b", b"b", file_name="same 🌙.txt")
  let raw = a.to_json().stringify()
  let raw = "{\n  \"future_provenance\": {\"v\": 7}, " +
    raw[1:].to_string() +
    "\n"
  @fsx.write_to_file(store.artifact_record_file(a.id), raw)
  let result = export_retained_artifacts(
    store.root,
    [a.id, b.id],
    @pathx.join(root, "portable"),
  )
  inspect(result.artifacts[0].content_path, content="files/1-same__.txt")
  inspect(result.artifacts[1].content_path, content="files/2-same__.txt")
  inspect(result.artifacts[0].content_bytes, content="0")
  assert_eq(@fsx.read_file(@pathx.join(root, "portable/records/1.json")), raw)
  assert_true(
    @fsx.read_file(@pathx.join(root, "portable/SHA256SUMS")).contains(
      "  manifest.json\n",
    ),
  )
}

///|
async test "artifact export validates all selections before creating output" {
  let (root, store, artifacts) = export_test_store()
  let a = export_test_write(artifacts, "a", b"original")
  let destination = @pathx.join(root, "never-created")
  for ids in [[], ["a", "a"], ["a", "missing"], ["../a"], [""]] {
    assert_true(
      (try? export_retained_artifacts(store.root, ids, destination)) is Err(_),
    )
    assert_false(@fsx.exists(destination))
  }
  @fsx.write_to_file(store.artifact_record_file(a.id), "{broken")
  assert_true(
    (try? export_retained_artifacts(store.root, ["a"], destination)) is Err(_),
  )
  assert_false(@fsx.exists(destination))
  store.save_artifact({ ..a, path: @pathx.join(root, "outside.bin"), })
  @fs.write_file(
    @pathx.join(root, "outside.bin"),
    b"outside",
    create_mode=CreateNew,
  )
  assert_true(
    (try? export_retained_artifacts(store.root, ["a"], destination)) is Err(_),
  )
  assert_false(@fsx.exists(destination))
  store.save_artifact(a)
  @fsx.make_directory(
    @pathx.join(store.root, "index/deleted-artifacts"),
    recursive=true,
  )
  @fsx.write_to_file(store.artifact_deleted_file("a"), "{}")
  assert_true(
    (try? export_retained_artifacts(store.root, ["a"], destination)) is Err(_),
  )
  assert_false(@fsx.exists(destination))
}

///|
async test "artifact export refuses destination reuse and store writes" {
  let (root, store, artifacts) = export_test_store()
  let a = export_test_write(artifacts, "a", b"keep")
  let destination = @pathx.join(root, "copy")
  let first = export_retained_artifacts(store.root, ["a"], destination)
  let original_manifest = @fsx.read_file(
    @pathx.join(destination, "manifest.json"),
  )
  assert_true(
    (try? export_retained_artifacts(store.root, ["a"], destination)) is Err(_),
  )
  assert_eq(
    @fsx.read_file(@pathx.join(destination, "manifest.json")),
    original_manifest,
  )
  for output in [store.root, @pathx.join(store.root, "new-export"), a.path] {
    assert_true(
      (try? export_retained_artifacts(store.root, ["a"], output)) is Err(_),
    )
  }
  assert_false(@fsx.exists(@pathx.join(store.root, "new-export")))
  assert_eq(@fs.read_file(a.path).binary(), b"keep")
  assert_eq(first.artifacts[0].record.id, "a")
}

///|
async test "artifact export bounds selection and content before publishing" {
  let (root, store, artifacts) = export_test_store()
  let ids : Array[String] = []
  for i in 0..<32 {
    let id = "part-\{i}"
    ignore(export_test_write(artifacts, id, b""))
    ids.push(id)
  }
  let result = export_retained_artifacts(
    store.root,
    ids,
    @pathx.join(root, "all"),
  )
  assert_eq(result.artifacts.length(), 32)
  assert_eq(result.total_content_bytes, 0)
  ids.push("extra")
  assert_true(
    (try? export_retained_artifacts(
      store.root,
      ids,
      @pathx.join(root, "too-many"),
    ))
    is Err(_),
  )
  let huge = export_test_write(artifacts, "huge", b"")
  let file = @fs.create(huge.path)
  file.write_at(b"x", position=16777216L)
  file.close()
  assert_true(
    (try? export_retained_artifacts(
      store.root,
      ["huge"],
      @pathx.join(root, "too-large"),
    ))
    is Err(_),
  )
  assert_false(@fsx.exists(@pathx.join(root, "too-large")))
}
