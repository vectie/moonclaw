///|
async test "portable import preserves producer identity and opens search comparison and reexport" {
  let root = @fsx.mkdtemp("/tmp/moonclaw-artifact-import-XXXXXX")
  let store = SystemStore::new(root=@pathx.join(root, "producer"))
  let artifacts = ArtifactStore::new(store~)
  for (id, content) in [("old", "draft\r\n"), ("new", "ready 🌙\n")] {
    ignore(
      artifacts.write(
        {
          run_id: "run-" + id,
          job_id: "job-import",
          artifact_type: "report",
          logical_key: Some("review"),
          content_type: "text/plain",
          file_name: Some("report.txt"),
          metadata: { "producer": "synthetic fixture" },
          scope: ["inspection"],
          content,
          append_only: true,
        },
        id,
        42,
      ),
    )
  }
  guard artifacts.get("old") is Some(old) else {
    fail("Missing producer output")
  }
  store.save_artifact({ ..old, status: Archived, })
  let packet = @pathx.join(root, "packet")
  let exported = export_retained_artifacts(store.root, ["old", "new"], packet)
  let destination = @pathx.join(root, "inspection")
  let imported = import_artifact_export(packet, destination)
  inspect(imported.schema, content="moonclaw.artifact-import.v1")
  inspect(imported.artifacts.length(), content="2")
  assert_eq(imported.artifacts[0].record.id, "old")
  assert_true(imported.artifacts[0].record.status is Archived)
  assert_eq(imported.artifacts[1].record.version, 2)
  for i, entry in imported.artifacts {
    assert_eq(entry.content_sha256, exported.artifacts[i].content_sha256)
    assert_eq(entry.original_record_sha256, exported.artifacts[i].record_sha256)
    assert_eq(
      @fs.read_file(@pathx.join(destination, entry.original_record_path)).binary(),
      @fs.read_file(@pathx.join(packet, exported.artifacts[i].record_path)).binary(),
    )
    assert_eq(
      @fs.read_file(entry.record.path).binary(),
      @fs.read_file(exported.artifacts[i].record.path).binary(),
    )
  }
  let search = search_retained_artifacts(destination, text=Some("ready 🌙"))
  assert_eq(search.matching_artifacts, 1)
  assert_eq(search.matches[0].record.id, "new")
  assert_eq(search.issues.length(), 0)
  let compared = compare_retained_artifacts(destination, "old", "new")
  assert_eq(compared.left.content_sha256, exported.artifacts[0].content_sha256)
  assert_eq(compared.right.content_sha256, exported.artifacts[1].content_sha256)
  let selected = search.export_selected(@pathx.join(root, "selected"))
  assert_eq(
    selected.artifacts[0].content_sha256,
    exported.artifacts[1].content_sha256,
  )
  let recovered = SystemStore::new(root=destination)
  recovered.reload_artifacts_unlocked()
  assert_eq(recovered.list_artifacts().length(), 2)
  assert_eq(recovered.list_artifact_recovery_issues().length(), 0)
  assert_eq(recovered.list_runs().length(), 0)
  assert_false(@fsx.exists(@pathx.join(destination, "index")))
  assert_true((try? import_artifact_export(packet, destination)) is Err(_))
}

///|
async test "portable import refuses empty packets and malformed numerical fields before output" {
  let root = @fsx.mkdtemp("/tmp/moonclaw-artifact-import-XXXXXX")
  let packet = @pathx.join(root, "packet")
  @fs.mkdir(packet)
  let output = @pathx.join(root, "not-created")
  let invalid : Json = {
    "schema": "moonclaw.artifact-export.v1",
    "artifacts": [],
    "total_content_bytes": 0,
  }
  @fsx.write_to_file(@pathx.join(packet, "manifest.json"), invalid.stringify())
  assert_true((try? import_artifact_export(packet, output)) is Err(_))
  assert_false(@fsx.exists(output))
  let numbers : Array[Json] = [{ "n": 1.5 }, { "n": "1" }, { "n": -1 }]
  for json in numbers {
    assert_true((try? import_integer(json, "n", 1)) is Err(_))
  }
  import_integer({ "n": 1 }, "n", 1)
}
