///|
fn artifact_test_store(root : String) -> ArtifactStore {
  let store = SystemStore::new(root~)
  ArtifactStore::new(store~)
}

///|
async test "ArtifactStore writes reads and filters artifacts" {
  @fsx.with_temporary_directory("job-artifact-store-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let artifacts = artifact_test_store(root)
    let first = artifacts.write(
      ArtifactWriteRequest::new(
        run_id="run-1",
        job_id="research.topic.sync",
        artifact_type="paper.summary",
        logical_key=Some("paper:1"),
        content_type="text/markdown",
        scope=["research", "paper:1"],
        content="# Summary",
      ),
      "artifact-1",
      100,
    )
    let second = artifacts.write(
      ArtifactWriteRequest::new(
        run_id="run-2",
        job_id="research.paper.parse",
        artifact_type="paper.chunks",
        logical_key=Some("paper:2"),
        content_type="application/json",
        scope=["research", "paper:2"],
        content="{\"chunks\":2}",
      ),
      "artifact-2",
      200,
    )

    inspect(first.version, content="1")
    inspect(second.content_type, content="application/json")
    inspect(
      artifacts.read_text("artifact-1").unwrap_or(""),
      content="# Summary",
    )
    inspect(
      artifacts
      .list(query=ArtifactQuery::new(job_id=Some("research.topic.sync")))
      .map(fn(artifact) { artifact.id })
      .join(","),
      content="artifact-1",
    )
    inspect(
      artifacts
      .list(query=ArtifactQuery::new(scope=Some("paper:2")))
      .map(fn(artifact) { artifact.id })
      .join(","),
      content="artifact-2",
    )
  })
}

///|
async test "ArtifactStore supports append-only versions and mutable overwrite" {
  @fsx.with_temporary_directory("job-artifact-version-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let artifacts = artifact_test_store(root)

    let v1 = artifacts.write(
      ArtifactWriteRequest::new(
        run_id="run-1",
        job_id="research.topic.sync",
        artifact_type="paper.summary",
        logical_key=Some("paper:1"),
        content="v1",
      ),
      "artifact-1",
      100,
    )
    let v2 = artifacts.write(
      ArtifactWriteRequest::new(
        run_id="run-1",
        job_id="research.topic.sync",
        artifact_type="paper.summary",
        logical_key=Some("paper:1"),
        content="v2",
      ),
      "artifact-2",
      200,
    )
    let mutable = artifacts.write(
      ArtifactWriteRequest::new(
        run_id="run-1",
        job_id="research.topic.sync",
        artifact_type="paper.latest",
        logical_key=Some("paper:latest"),
        content="old",
        append_only=false,
      ),
      "artifact-3",
      300,
    )
    let overwritten = artifacts.write(
      ArtifactWriteRequest::new(
        run_id="run-1",
        job_id="research.topic.sync",
        artifact_type="paper.latest",
        logical_key=Some("paper:latest"),
        content="new",
        append_only=false,
      ),
      "artifact-4",
      400,
    )

    inspect(v1.version, content="1")
    inspect(v2.version, content="2")
    inspect(mutable.id, content="artifact-3")
    inspect(overwritten.id, content="artifact-3")
    inspect(artifacts.read_text("artifact-3").unwrap_or(""), content="new")
  })
}

///|
async test "ArtifactStore archives and cleans up artifacts by retention policy" {
  @fsx.with_temporary_directory("job-artifact-retention-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let artifacts = artifact_test_store(root)
    ignore(
      artifacts.write(
        ArtifactWriteRequest::new(
          run_id="run-1",
          job_id="research.topic.sync",
          artifact_type="paper.summary",
          logical_key=Some("paper:1"),
          scope=["research"],
          content="old",
        ),
        "artifact-1",
        100,
      ),
    )
    ignore(
      artifacts.write(
        ArtifactWriteRequest::new(
          run_id="run-2",
          job_id="research.topic.sync",
          artifact_type="paper.summary",
          logical_key=Some("paper:2"),
          scope=["research"],
          content="new",
        ),
        "artifact-2",
        200,
      ),
    )

    let report = artifacts.apply_retention(
      ArtifactRetentionPolicy::new(
        artifact_type=Some("paper.summary"),
        keep_latest=Some(1),
      ),
      500,
    )
    inspect(report.archived_ids.join(","), content="artifact-1")
    inspect(report.deleted_ids.length(), content="0")
    inspect(
      artifacts
      .get("artifact-1")
      .map(fn(artifact) { artifact.status.to_json().stringify() })
      .unwrap_or(""),
      content="\"Archived\"",
    )

    let deleted = artifacts.apply_retention(
      ArtifactRetentionPolicy::new(
        artifact_type=Some("paper.summary"),
        max_age_ms=Some(50),
        archive_before_delete=false,
      ),
      500,
    )
    inspect(deleted.deleted_ids.join(","), content="artifact-2")
    inspect(artifacts.get("artifact-2") is None, content="true")
  })
}
