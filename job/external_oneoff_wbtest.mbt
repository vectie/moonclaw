///|
async fn oneoff_test_app(root : String) -> GatewayJobApp {
  @fsx.make_directory(root + "/input", recursive=true, exists_ok=true)
  @fsx.make_directory(root + "/skills/oneoff", recursive=true, exists_ok=true)
  @fsx.write_to_file(root + "/input/source.md", "Local captured fixture input")
  @fsx.write_to_file(
    root + "/skills/oneoff/SKILL.md",
    "Read the captured input; report exact evidence",
  )
  @fsx.write_to_file(
    root + "/moonclaw.jobs.json",
    (
      {
        "jobs": {
          "profiles": {
            "town_single": {
              "family": "town_single",
              "steps": [
                {
                  "id": "contribution",
                  "title": "Contribution",
                  "kind": "job.analysis",
                  "prompt_template": "${request}",
                  "metadata": {
                    "enable_tools": false,
                    "web_search": false,
                    "disable_adaptive": true,
                    "retry_max_attempts": 1,
                    "timeout_ms": 1000,
                  },
                },
              ],
            },
          },
        },
      } : Json).stringify(),
  )
  let app = GatewayJobApp::new(
    root=moonclaw_jobs_root(root),
    cwd=root,
    home=root,
    workspace=@workspace.WorkspaceRuntime::new(home=root, cwd=root),
    next_id=() => "unused",
    now=() => 100,
  )
  app.load()
  app
}

///|
async fn oneoff_test_packet(
  root : String,
  id : String,
  question : String,
) -> String {
  let path = root + "/" + id + ".json"
  @fsx.write_to_file(
    path,
    (
      {
        "packet_id": id,
        "title": "Fixture contribution",
        "summary": "Local fixture",
        "request_text": question,
        "profile": "town_single",
        "output_contract": "Return UTF-8 source-bound text",
        "context_pages": ["input/source.md"],
        "skill_paths": ["skills/oneoff/SKILL.md"],
        "notes": [],
        "tags": [],
        "metadata": { "workspace_root": root },
      } : Json).stringify(),
  )
  path
}

///|
async test "oneoff durable prepared run resumes once and packet/profile changes do not duplicate" {
  @fsx.with_temporary_directory("claw-oneoff-XXXXXX", async fn(root) {
    let app = oneoff_test_app(root)
    let path = oneoff_test_packet(
      root, "source-revision-a", "Read frozen observations",
    )
    let pending = match app.start_external_oneoff_file(path, execute=false) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(pending.status, "Pending")
    assert_eq(pending.proposal_id, "oneoff-source-revision-a")
    assert_eq(pending.run_id, "run-oneoff-source-revision-a")
    let calls = Ref::{ val: 0, }
    let executor = AnalysisExecutor::new(run=fn(request) {
      calls.val += 1
      Ok({
        model_name: "local-fixture",
        content: "Actual fixture output for " +
        request.source_prompt +
        "\n水\u0000tail",
        conversation_id: None,
        usage: None,
        metadata: { "synthetic": true },
      })
    })
    let completed = match
      app.start_external_oneoff_file(path, analysis_executor=Some(executor)) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(completed.status, "Succeeded")
    assert_eq(calls.val, 1)
    let output = @fsx.read_file(completed.workspace_dir.unwrap() + "/report.md")
    assert_true(output.contains("水\u0000tail"))
    assert_eq(
      app.start_external_oneoff_file(path, analysis_executor=Some(executor)),
      Ok(completed),
    )
    assert_eq(calls.val, 1)
    ignore(
      oneoff_test_packet(root, "source-revision-a", "Changed source bytes"),
    )
    assert_true(
      app.start_external_oneoff_file(path, analysis_executor=Some(executor))
      is Err(_),
    )
    assert_eq(calls.val, 1)
    assert_eq(
      @fsx.read_file(completed.workspace_dir.unwrap() + "/report.md"),
      output,
    )
    assert_eq(app.runtime().store().list_job_proposals().length(), 1)
  })
}

///|
async test "oneoff failed and uncertain running contributions do not reexecute" {
  @fsx.with_temporary_directory("claw-oneoff-failure-XXXXXX", async fn(root) {
    let app = oneoff_test_app(root)
    let path = oneoff_test_packet(root, "failed-source", "Fail fixture")
    let calls = Ref::{ val: 0, }
    let executor = AnalysisExecutor::new(run=fn(_) {
      calls.val += 1
      Err("deterministic local failure")
    })
    let failed = match
      app.start_external_oneoff_file(path, analysis_executor=Some(executor)) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(failed.status, "Failed")
    assert_eq(
      app.start_external_oneoff_file(path, analysis_executor=Some(executor)),
      Ok(failed),
    )
    assert_eq(calls.val, 1)
    let unknown_path = oneoff_test_packet(
      root, "unknown-source", "Uncertain fixture",
    )
    let pending = match
      app.start_external_oneoff_file(unknown_path, execute=false) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    let run = app.runtime().store().get_run(pending.run_id).unwrap()
    app.runtime().store().save_run({ ..run, status: Running, })
    let unknown = match
      app.start_external_oneoff_file(
        unknown_path,
        analysis_executor=Some(executor),
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(unknown.status, "Running")
    assert_eq(calls.val, 1)
  })
}
