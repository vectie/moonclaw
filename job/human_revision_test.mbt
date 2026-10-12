///|
async test "public human revision API retains exact JSON as a separate copy" {
  @fsx.with_temporary_directory("human-revision-public-XXXXXX", root => {
    let store = @job.SystemStore::new(root~)
    store.save_run({
      id: "run-json",
      job_id: "job-json",
      trigger: Manual,
      parent_run_id: None,
      parent_step_id: None,
      depth: 0,
      workspace_dir: None,
      status: Succeeded,
      attempt: 1,
      retry_of: None,
      started_at: Some(1),
      finished_at: Some(2),
      summary: None,
      error: None,
    })
    let artifacts = @job.ArtifactStore::new(store~)
    let parent = artifacts.write(
      @job.ArtifactWriteRequest::new(
        run_id="run-json",
        job_id="job-json",
        artifact_type="result",
        content_type="application/json",
        content="{\"value\":1}\n",
      ),
      "json-source",
      3,
    )
    let source = artifacts.human_revision_source("run-json", parent.id)
    guard source
      is { "revision_source": { "parent_digest": String(digest), .. }, .. } else {
      fail("public source digest")
    }
    let saved = artifacts.save_human_revision(
      "run-json",
      parent.id,
      "json-save-001",
      digest,
      "{\"value\":\"世界\"}\n",
      4,
    )
    assert_eq(saved.artifact_type, "human_revision")
    assert_eq(saved.content_type, "application/json")
    assert_eq(
      artifacts.read_bytes("run-json", saved.id),
      Some(@encoding/utf8.encode("{\"value\":\"世界\"}\n")),
    )
    assert_eq(
      artifacts.read_bytes("run-json", parent.id),
      Some(@encoding/utf8.encode("{\"value\":1}\n")),
    )
    assert_eq(
      artifacts
      .save_human_revision(
        "run-json",
        parent.id,
        "json-save-001",
        digest,
        "{\"value\":\"世界\"}\n",
        9,
      )
      .to_json(),
      saved.to_json(),
    )
    assert_eq(artifacts.list().length(), 2)
  })
}
