///|
async test "prepare_run_workspace creates dedicated git-backed workspace with inherited memory" {
  @fsx.with_temporary_directory("job-run-workspace-XXXXXX", async fn(dir) {
    let workspace_root = dir |> @pathx.join("workspace")
    let jobs_root = dir |> @pathx.join("jobs")
    let snapshot = @workspace.load_workspace_snapshot_from_root(workspace_root)
    inspect(snapshot.root, content=workspace_root)
    @fsx.make_directory(workspace_root |> @pathx.join("wiki"), recursive=true)
    @fsx.make_directory(
      workspace_root |> @pathx.join("skills") |> @pathx.join("wiki-ingest"),
      recursive=true,
    )
    @fsx.write_to_file(
      workspace_root |> @pathx.join("wiki") |> @pathx.join("index.md"),
      "# Index\n",
    )
    @fsx.write_to_file(
      workspace_root |> @pathx.join("RESOLVER.md"),
      "# Resolver\n",
    )
    @fsx.write_to_file(
      workspace_root
      |> @pathx.join("skills")
      |> @pathx.join("wiki-ingest")
      |> @pathx.join("SKILL.md"),
      "# Skill\n",
    )
    let external_source = dir
      |> @pathx.join("external")
      |> @pathx.join("README.md")
    @fsx.make_directory(@pathx.dirname(external_source), recursive=true)
    @fsx.write_to_file(external_source, "# External Source\n")
    @fsx.make_directory(
      workspace_root |> @pathx.join("raw") |> @pathx.join("bootstrap"),
      recursive=true,
    )
    @fsx.write_to_file(
      workspace_root
      |> @pathx.join("raw")
      |> @pathx.join("bootstrap")
      |> @pathx.join("SOURCE_HINTS.md"),
      [
        "# Source Hints",
        "",
        "## Local Repository Follow-Up",
        "",
        "- \{external_source}",
        "- /missing/source.md",
        "",
      ].join("\n"),
    )

    let store = SystemStore::new(root=jobs_root)
    let definition = JobDefinition::{
      id: "job-1",
      kind: "job.analysis",
      enabled: true,
      config: { "workspace": workspace_root },
      schedule: None,
      retry_policy: None,
      workflow_id: None,
      created_at: 1,
      updated_at: 1,
      tags: [],
    }
    let run = JobRun::{
      id: "run-1",
      job_id: definition.id,
      trigger: Manual,
      parent_run_id: None,
      parent_step_id: None,
      depth: 0,
      workspace_dir: None,
      status: Pending,
      attempt: 1,
      retry_of: None,
      started_at: None,
      finished_at: None,
      summary: None,
      error: None,
    }
    store.save_definition(definition)
    store.save_run(run)
    ignore(
      MemoryService::new(store~).remember(
        MemoryWriteRequest::new(
          kind="note",
          title=Some("workspace memory"),
          content="Remember to keep the benchmark appendix.",
          workspace=Some(workspace_root),
          scope=["research"],
        ),
        "memory-1",
        10,
      ),
    )
    ignore(
      MemoryService::new(store~).remember(
        MemoryWriteRequest::new(
          kind="workspace.identity",
          title=Some("Researcher identity"),
          content="You prioritize benchmark rigor over leaderboard claims.",
          workspace=Some(workspace_root),
          tags=["identity"],
          scope=["research"],
        ),
        "memory-identity",
        11,
      ),
    )
    ignore(
      MemoryService::new(store~).remember(
        MemoryWriteRequest::new(
          kind="workspace.routine",
          title=Some("Paper review routine"),
          content="Always end each review with risks, baselines, and missing ablations.",
          workspace=Some(workspace_root),
          tags=["routine"],
          scope=["research"],
        ),
        "memory-routine",
        12,
      ),
    )

    let prepared = prepare_run_workspace(store, definition, run)
    let workspace_dir = prepared.workspace_dir.unwrap_or("")
    inspect(
      workspace_dir.has_suffix(".moonsuite/products/moonclaw/jobs/run-1"),
      content="true",
    )
    inspect(
      @fsx.exists(workspace_root |> @pathx.join("moonclaw-jobs")),
      content="false",
    )
    inspect(@fsx.exists(workspace_dir |> @pathx.join(".git")), content="true")
    inspect(
      @fsx.exists(workspace_dir |> @pathx.join("MEMORY.md")),
      content="false",
    )
    inspect(
      @fsx.exists(workspace_dir |> @pathx.join("IDENTITY.md")),
      content="false",
    )
    inspect(
      @fsx.exists(workspace_dir |> @pathx.join("ROUTINES.md")),
      content="false",
    )
    inspect(
      @fsx.read_file(
        workspace_dir |> @pathx.join("wiki") |> @pathx.join("index.md"),
      ),
      content="# Index\n",
    )
    inspect(
      @fsx.read_file(workspace_dir |> @pathx.join("RESOLVER.md")),
      content="# Resolver\n",
    )
    inspect(
      @fsx.read_file(
        workspace_dir
        |> @pathx.join("skills")
        |> @pathx.join("wiki-ingest")
        |> @pathx.join("SKILL.md"),
      ),
      content="# Skill\n",
    )
    let manifest = @fsx.read_file(
      workspace_dir
      |> @pathx.join(source_hint_mount_dir_name())
      |> @pathx.join(source_hint_mount_manifest_name()),
    )
    inspect(manifest.contains(external_source), content="true")
    inspect(manifest.contains("mounted-sources/"), content="true")
    inspect(manifest.contains("/missing/source.md"), content="true")
    inspect(manifest.contains("missing"), content="true")
    inspect(@fsx.exists(run_workspace_meta_file(workspace_dir)), content="true")
    @fsx.write_to_file(
      workspace_dir |> @pathx.join("MEMORY.md"),
      "# Scratchpad\n\nMy private working note.\n",
    )
    ignore(
      checkpoint_run_workspace(
        store,
        prepared.id,
        "moonclaw: save workspace memory",
      ),
    )
    let stored_memory = store.get_memory("workspace-memory:run-1")
    inspect(stored_memory is Some(_), content="true")
    inspect(
      stored_memory
      .map(fn(memory) { memory.content.contains("private working note") })
      .unwrap_or(false),
      content="true",
    )

    @fsx.write_to_file(workspace_dir |> @pathx.join("NOTE.txt"), "hello")
    inspect(
      checkpoint_run_workspace(store, prepared.id, "moonclaw: checkpoint"),
      content="true",
    )
    let commits = @spawn.spawn(
      "git",
      ["rev-list", "--count", "HEAD"],
      cwd=workspace_dir,
    )
    inspect(commits.stdout.trim(), content="3")
    let workspace_status = render_run_workspace_status(
      store, definition, prepared,
    )
    inspect(workspace_status.contains("Recent commits:"), content="true")
  })
}

///|
async test "prepare_run_workspace nests child runs under parent workspace" {
  @fsx.with_temporary_directory("job-run-subworkspace-XXXXXX", async fn(dir) {
    let workspace_root = dir |> @pathx.join("workspace")
    ignore(@workspace.load_workspace_snapshot_from_root(workspace_root))
    let store = SystemStore::new(root=dir |> @pathx.join("jobs"))
    let definition = JobDefinition::{
      id: "job-parent",
      kind: "job.analysis",
      enabled: true,
      config: { "workspace": workspace_root },
      schedule: None,
      retry_policy: None,
      workflow_id: None,
      created_at: 1,
      updated_at: 1,
      tags: [],
    }
    let parent_run = JobRun::{
      id: "run-parent",
      job_id: definition.id,
      trigger: Manual,
      parent_run_id: None,
      parent_step_id: None,
      depth: 0,
      workspace_dir: None,
      status: Pending,
      attempt: 1,
      retry_of: None,
      started_at: None,
      finished_at: None,
      summary: None,
      error: None,
    }
    let child_run = JobRun::{
      id: "run-child",
      job_id: definition.id,
      trigger: Custom("subjob"),
      parent_run_id: Some(parent_run.id),
      parent_step_id: Some("delegate"),
      depth: 1,
      workspace_dir: None,
      status: Pending,
      attempt: 1,
      retry_of: None,
      started_at: None,
      finished_at: None,
      summary: None,
      error: None,
    }
    store.save_definition(definition)
    store.save_run(parent_run)
    let prepared_parent = prepare_run_workspace(store, definition, parent_run)
    store.save_run(child_run)
    let prepared_child = prepare_run_workspace(store, definition, child_run)
    inspect(
      prepared_child.workspace_dir
      .unwrap_or("")
      .has_prefix(
        prepared_parent.workspace_dir.unwrap_or("")
        |> @pathx.join("moonclaw-subjobs"),
      ),
      content="true",
    )
  })
}
