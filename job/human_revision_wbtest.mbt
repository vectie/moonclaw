///|
async test "human revision lineage is unambiguous for colon bearing run and artifact IDs" {
  @fsx.with_temporary_directory("human-revision-colon-XXXXXX", root => {
    let store = SystemStore::new(root~)
    store.save_run({ ..sample_run(), id: "run:a", })
    store.save_run({ ..sample_run(), id: "run", })
    let artifacts = ArtifactStore::new(store~)
    ignore(
      artifacts.write(
        { ..recovery_request("source"), run_id: "run:a", },
        "root",
        1,
      ),
    )
    ignore(
      artifacts.write(
        { ..recovery_request("source"), run_id: "run", },
        "a:root",
        2,
      ),
    )
    let digest = human_revision_digest(b"source")
    let left = artifacts.save_human_revision(
      "run:a", "root", "colon-save-001", digest, "left", 3,
    )
    let right = artifacts.save_human_revision(
      "run", "a:root", "colon-save-001", digest, "right", 4,
    )
    assert_true(left.logical_key != right.logical_key)
    assert_eq(left.version, 1)
    assert_eq(right.version, 1)
  })
}

///|
async test "human revisions preserve exact source and lineage with duplicate concurrent replay" {
  @fsx.with_temporary_directory("human-revision-lineage-XXXXXX", root => {
    let store = SystemStore::new(root~)
    store.save_run(sample_run())
    let artifacts = ArtifactStore::new(store~)
    let original = artifacts.write(
      recovery_request("source\u0000报告\n"),
      "source",
      100,
    )
    let before_run = Json(store.list_runs())
    let source = artifacts.human_revision_source("run-1", "source")
    guard source
      is {
        "content": String(text),
        "revision_source": { "parent_digest": String(digest), .. },
        ..
      } else {
      fail("source envelope")
    }
    assert_eq(text, "source\u0000报告\n")
    let stale = SystemStore::new(root~)
    stale.load()
    let other = ArtifactStore::new(store=stale)
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        ignore(
          artifacts.save_human_revision(
            "run-1", "source", "same-save-001", digest, "human\u0000世界\n", 200,
          ),
        )
      })
      group.spawn_bg(() => {
        ignore(
          other.save_human_revision(
            "run-1", "source", "same-save-001", digest, "human\u0000世界\n", 300,
          ),
        )
      })
    })
    store.load()
    assert_eq(artifacts.list().length(), 2)
    let saved = artifacts.save_human_revision(
      "run-1", "source", "same-save-001", digest, "human\u0000世界\n", 999,
    )
    assert_eq(saved.artifact_type, "human_revision")
    assert_eq(saved.version, 1)
    assert_eq(saved.job_id, original.job_id)
    assert_eq(
      artifacts.read_bytes("run-1", original.id),
      Some(@encoding/utf8.encode(text)),
    )
    guard saved.metadata is Object(saved_metadata) else {
      fail("saved metadata")
    }
    assert_eq(saved_metadata["parent_artifact_id"], "source")
    assert_eq(saved_metadata["parent_version"], 1)
    assert_eq(saved_metadata["parent_digest"], Json(digest))
    assert_eq(saved_metadata["execution_output"], false)
    assert_eq(saved_metadata["accepted_output"], false)
    let (parent, _, revised_digest) = artifacts.human_revision_parent_unlocked(
      "run-1",
      saved.id,
    )
    let next = artifacts.save_human_revision(
      "run-1",
      parent.id,
      "next-save-002",
      revised_digest,
      "second human copy",
      400,
    )
    assert_eq(next.version, 2)
    assert_eq(next.logical_key, saved.logical_key)
    guard next.metadata is Object(next_metadata) else { fail("next metadata") }
    assert_eq(next_metadata["parent_artifact_id"], Json(saved.id))
    assert_eq(next_metadata["lineage_root_id"], "source")
    try
      artifacts.save_human_revision(
        "run-1", "source", "same-save-001", digest, "conflicting bytes", 1000,
      )
    catch {
      error =>
        assert_true(error.to_string().contains("already records different"))
    } noraise {
      _ => fail("conflicting save ID must fail")
    }
    assert_eq(Json(store.list_runs()), before_run)
    let reopened = SystemStore::new(root~)
    reopened.load()
    assert_eq(
      ArtifactStore::new(store=reopened).read_bytes("run-1", saved.id),
      Some(@encoding/utf8.encode("human\u0000世界\n")),
    )
    assert_eq(
      reopened.get_artifact(original.id).unwrap().to_json(),
      original.to_json(),
    )
  })
}

///|
async test "human revisions recover lost cache acknowledgement and retry record checkpoint" {
  @fsx.with_temporary_directory("human-revision-checkpoint-XXXXXX", root => {
    let store = SystemStore::new(root~)
    store.save_run(sample_run())
    let artifacts = ArtifactStore::new(store~)
    let parent = artifacts.write(recovery_request("source"), "source", 100)
    let digest = human_revision_digest(b"source")
    let id = human_revision_id("run-1", "source", "save-cache-001")
    let blocked = store.artifacts_index_file() + ".pending"
    @fsx.make_directory(blocked)
    try
      artifacts.save_human_revision(
        "run-1", "source", "save-cache-001", digest, "committed copy", 200,
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("cache failure is uncertain")
    }
    let reopened = SystemStore::new(root~)
    reopened.load()
    assert_eq(reopened.get_artifact(id).unwrap().created_at, 200)
    @fsx.remove(blocked)
    @fs.write_file(parent.path, b"source changed")
    let reader = ArtifactStore::new(store=reopened)
    let replay = reader.save_human_revision(
      "run-1", "source", "save-cache-001", digest, "committed copy", 999,
    )
    assert_eq(replay.created_at, 200)
    try
      reader.save_human_revision(
        "run-1", "source", "fresh-save-001", digest, "copy", 1000,
      )
    catch {
      error => assert_true(error.to_string().contains("Parent content changed"))
    } noraise {
      _ => fail("changed parent must fail")
    }
    @fs.write_file(parent.path, b"source")
    let record_id = human_revision_id("run-1", "source", "save-record-001")
    let record_block = store.artifact_record_file(record_id) + ".pending"
    @fsx.make_directory(record_block, recursive=true)
    try
      reader.save_human_revision(
        "run-1", "source", "save-record-001", digest, "record draft", 300,
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("record failure must be reported")
    }
    assert_true(reader.get(record_id) is None)
    @fsx.remove(record_block)
    let retry = reader.save_human_revision(
      "run-1", "source", "save-record-001", digest, "record draft", 400,
    )
    assert_eq(retry.version, 2)
    @fsx.remove(store.artifacts_index_file())
    let final_store = SystemStore::new(root~)
    final_store.load()
    assert_eq(final_store.list_artifacts().length(), 3)
  })
}

///|
async test "human revisions reject wrong owner binary invalid UTF8 and unsafe identities" {
  @fsx.with_temporary_directory("human-revision-refusal-XXXXXX", root => {
    let store = SystemStore::new(root~)
    store.save_run(sample_run())
    let artifacts = ArtifactStore::new(store~)
    let parent = artifacts.write(recovery_request("source"), "source", 100)
    for
      (run, id, save) in [
        ("other", "source", "valid-save-001"),
        ("run-1", "missing", "valid-save-001"),
        ("run-1", "source", "../bad-id"),
      ] {
      try
        artifacts.save_human_revision(
          run,
          id,
          save,
          human_revision_digest(b"source"),
          "copy",
          200,
        )
      catch {
        _ => ()
      } noraise {
        _ => fail("invalid source or save ID must fail")
      }
    }
    @fs.write_file(parent.path, b"\xff\x80")
    try
      artifacts.save_human_revision(
        "run-1",
        "source",
        "valid-save-002",
        human_revision_digest(b"\xff\x80"),
        "copy",
        200,
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("invalid UTF8 must fail")
    }
    ignore(
      artifacts.write(
        { ..recovery_request("pdf"), content_type: "application/pdf", },
        "binary",
        101,
      ),
    )
    try
      artifacts.save_human_revision(
        "run-1",
        "binary",
        "valid-save-003",
        human_revision_digest(b"pdf"),
        "copy",
        200,
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("binary must fail")
    }
    assert_eq(artifacts.list().length(), 2)
  })
}
