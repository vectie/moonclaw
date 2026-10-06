///|
fn recovery_request(content : String) -> ArtifactWriteRequest {
  ArtifactWriteRequest::new(
    run_id="run-1",
    job_id="job.sample.sync",
    artifact_type="report",
    logical_key=Some("result"),
    content_type="text/markdown",
    content~,
  )
}

///|
async test "artifact recovery restores exact revisions into read API and UI snapshot" {
  @fsx.with_temporary_directory("artifact-recover-ui-XXXXXX", root => {
    let store = SystemStore::new(root~)
    store.save_definition(sample_definition())
    store.save_workflow(sample_workflow())
    store.save_run(sample_run())
    let artifacts = ArtifactStore::new(store~)
    let first = artifacts.write(recovery_request("first revision"), "a1", 100)
    let old_index = @fsx.read_file(store.artifacts_index_file())
    let second = artifacts.write(recovery_request("second revision"), "a2", 200)
    // Simulate a process stopping after record commit but before cache commit.
    @fsx.write_to_file(store.artifacts_index_file(), old_index)
    let reopened = SystemStore::new(root~)
    reopened.load()
    let reader = ArtifactStore::new(store=reopened)
    assert_eq(reader.read_text(first.id), Some("first revision"))
    assert_eq(reader.read_text(second.id), Some("second revision"))
    assert_eq(reader.get(second.id).unwrap().version, 2)
    let snapshot = build_job_ui_snapshot(reopened, "run-1").unwrap()
    assert_eq(snapshot.artifacts.length(), 2)
    assert_true(snapshot.nodes.any(node => node.artifact_id == Some(second.id)))
    @fsx.remove(store.artifacts_index_file())
    let without_index = SystemStore::new(root~)
    without_index.load()
    assert_eq(without_index.list_artifacts().length(), 2)
    assert_eq(
      ArtifactStore::new(store=without_index).read_text("a2"),
      Some("second revision"),
    )
  })
}

///|
async test "artifact recovery tolerates malformed records and legacy index entries" {
  @fsx.with_temporary_directory("artifact-recover-malformed-XXXXXX", root => {
    let store = SystemStore::new(root~)
    let artifacts = ArtifactStore::new(store~)
    ignore(artifacts.write(recovery_request("valid"), "good", 100))
    ignore(
      artifacts.write(recovery_request("prior checkpoint"), "damaged", 200),
    )
    ignore(
      artifacts.write(recovery_request("legacy indexed output"), "legacy", 300),
    )
    @fsx.write_to_file(store.artifact_record_file("damaged"), "{truncated")
    @fsx.remove(store.artifact_record_file("legacy"))
    let reopened = SystemStore::new(root~)
    reopened.load()
    let reader = ArtifactStore::new(store=reopened)
    assert_eq(reader.read_text("good"), Some("valid"))
    assert_eq(reader.read_text("damaged"), Some("prior checkpoint"))
    assert_eq(reader.read_text("legacy"), Some("legacy indexed output"))
    assert_true(
      reopened
      .list_artifact_recovery_issues()
      .any(issue => issue.contains("damaged")),
    )
    assert_true(
      reopened
      .list_artifact_recovery_issues()
      .any(issue => issue.contains("legacy")),
    )
    // A corrupt global cache cannot prevent a different valid record opening.
    @fsx.write_to_file(store.artifacts_index_file(), "{truncated")
    let corrupt_index = SystemStore::new(root~)
    corrupt_index.load()
    assert_eq(
      ArtifactStore::new(store=corrupt_index).read_text("good"),
      Some("valid"),
    )
    assert_eq(corrupt_index.list_artifacts().length(), 1)
    assert_true(
      corrupt_index
      .list_artifact_recovery_issues()
      .any(issue => issue.contains("index checkpoint")),
    )
  })
}

///|
async test "artifact recovery allocates revisions across stale and concurrent stores" {
  @fsx.with_temporary_directory("artifact-recover-writers-XXXXXX", root => {
    let left = SystemStore::new(root~)
    let right = SystemStore::new(root~)
    left.load()
    right.load()
    let a = ArtifactStore::new(store=left)
    let b = ArtifactStore::new(store=right)
    assert_eq(a.write(recovery_request("one"), "a1", 100).version, 1)
    assert_eq(b.write(recovery_request("two"), "a2", 200).version, 2)
    @async.with_task_group(group => {
      group.spawn_bg(() => ignore(a.write(recovery_request("three"), "a3", 300)))
      group.spawn_bg(() => ignore(b.write(recovery_request("four"), "a4", 400)))
    })
    let reopened = SystemStore::new(root~)
    reopened.load()
    let versions = reopened.list_artifacts().map(artifact => artifact.version)
    versions.sort()
    assert_eq(versions, [1, 2, 3, 4])
    assert_eq(ArtifactStore::new(store=reopened).read_text("a1"), Some("one"))
    assert_eq(ArtifactStore::new(store=reopened).read_text("a4"), Some("four"))
  })
}

///|
async test "artifact recovery exposes incomplete record checkpoint without losing confirmed output" {
  @fsx.with_temporary_directory("artifact-recover-record-fault-XXXXXX", root => {
    let store = SystemStore::new(root~)
    let artifacts = ArtifactStore::new(store~)
    ignore(artifacts.write(recovery_request("confirmed"), "a1", 100))
    let blocked = "\{store.artifact_record_file("a2")}.pending"
    @fsx.make_directory(blocked, recursive=true)
    try artifacts.write(recovery_request("uncommitted"), "a2", 200) catch {
      _ => ()
    } noraise {
      _ => fail("record checkpoint fault must be reported")
    }
    assert_true(store.get_artifact("a2") is None)
    let reopened = SystemStore::new(root~)
    reopened.load()
    let reader = ArtifactStore::new(store=reopened)
    assert_eq(reader.read_text("a1"), Some("confirmed"))
    assert_true(reader.get("a2") is None)
    assert_true(
      reopened
      .list_artifact_recovery_issues()
      .any(issue => issue.contains("Incomplete artifact checkpoint: a2")),
    )
    // Uncommitted bytes stay available for investigation, never promoted as a
    // confirmed revision. Retrying persistence does not rerun any execution.
    assert_eq(
      @fsx.read_file(store.artifact_content_file("a2", file_name="content.txt")),
      "uncommitted",
    )
    @fsx.remove(blocked)
    assert_eq(
      reader.write(recovery_request("uncommitted"), "a2", 300).version,
      2,
    )
  })
}

///|
async test "artifact recovery repairs lost acknowledgement without duplicating or replacing output" {
  @fsx.with_temporary_directory("artifact-recover-index-fault-XXXXXX", root => {
    let store = SystemStore::new(root~)
    let artifacts = ArtifactStore::new(store~)
    ignore(artifacts.write(recovery_request("one"), "a1", 100))
    let blocked = "\{store.artifacts_index_file()}.pending"
    @fsx.make_directory(blocked)
    try artifacts.write(recovery_request("two"), "a2", 200) catch {
      _ => ()
    } noraise {
      _ => fail("cache checkpoint fault must be reported")
    }
    let reopened = SystemStore::new(root~)
    reopened.load()
    let reader = ArtifactStore::new(store=reopened)
    assert_eq(reader.read_text("a2"), Some("two"))
    assert_true(
      reopened
      .list_artifact_recovery_issues()
      .any(issue => issue.contains("index repair is pending")),
    )
    @fsx.remove(blocked)
    let retry = reader.write(recovery_request("two"), "a2", 999)
    assert_eq(retry.version, 2)
    assert_eq(retry.created_at, 200)
    try reader.write(recovery_request("different output"), "a2", 1000) catch {
      error => assert_true(error.to_string().contains("different output"))
    } noraise {
      _ =>
        fail("conflicting artifact replay must not overwrite confirmed bytes")
    }
    assert_eq(reader.read_text("a2"), Some("two"))
    assert_eq(reader.list().length(), 2)
  })
}

///|
async test "artifact recovery does not resurrect deleted output from a stale index or writer" {
  @fsx.with_temporary_directory("artifact-recover-delete-XXXXXX", root => {
    let store = SystemStore::new(root~)
    let artifacts = ArtifactStore::new(store~)
    ignore(artifacts.write(recovery_request("delete me"), "a1", 100))
    let stale = SystemStore::new(root~)
    stale.load()
    let old_index = @fsx.read_file(store.artifacts_index_file())
    assert_true(store.delete_artifact("a1"))
    // This is also the deletion crash window: tombstone committed, old cache.
    @fsx.write_to_file(store.artifacts_index_file(), old_index)
    let stale_writer = ArtifactStore::new(store=stale)
    ignore(stale_writer.write(recovery_request("keep me"), "a2", 200))
    let reopened = SystemStore::new(root~)
    reopened.load()
    assert_true(reopened.get_artifact("a1") is None)
    assert_eq(reopened.list_artifacts().length(), 1)
    assert_eq(
      ArtifactStore::new(store=reopened).read_text("a2"),
      Some("keep me"),
    )
  })
}

///|
async test "artifact recovery keeps missing content explicit and does not hide other results" {
  @fsx.with_temporary_directory("artifact-recover-content-XXXXXX", root => {
    let store = SystemStore::new(root~)
    let artifacts = ArtifactStore::new(store~)
    let missing = artifacts.write(recovery_request("missing"), "a1", 100)
    ignore(artifacts.write(recovery_request("readable"), "a2", 200))
    @fsx.remove(missing.path)
    let reopened = SystemStore::new(root~)
    reopened.load()
    let reader = ArtifactStore::new(store=reopened)
    assert_true(reader.get("a1") is Some(_))
    assert_true(reader.read_text("a1") is None)
    assert_eq(reader.read_text("a2"), Some("readable"))
    assert_true(
      reopened
      .list_artifact_recovery_issues()
      .contains("Artifact content is unavailable: a1"),
    )
  })
}
