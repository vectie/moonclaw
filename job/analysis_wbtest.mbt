///|
async fn analysis_test_engine(
  root : String,
  config : AnalysisStepConfig,
  workspace_dir? : String? = None,
) -> WorkflowEngine {
  let runtime = RuntimeManager::new(root~)
  let workflow = WorkflowDefinition::{
    id: "workflow.analysis",
    kind: "analysis",
    steps: [
      WorkflowStepDefinition::{
        id: "analyze",
        kind: "job.analysis",
        config: config.to_json(),
        retry_policy: None,
      },
    ],
    output_bindings: ["analyze"],
  }
  runtime.register_definition(JobDefinition::{
    id: "job.analysis",
    kind: "job.analysis",
    enabled: true,
    config: {},
    schedule: None,
    retry_policy: None,
    workflow_id: Some(workflow.id),
    created_at: 1,
    updated_at: 1,
    tags: ["analysis"],
  })
  runtime.register_workflow(workflow)
  runtime
  .store()
  .save_run(JobRun::{
    id: "run-analysis-1",
    job_id: "job.analysis",
    trigger: TriggerSource::Manual,
    parent_run_id: None,
    parent_step_id: None,
    depth: 0,
    workspace_dir,
    status: RunStatus::Pending,
    attempt: 1,
    retry_of: None,
    started_at: None,
    completed_at: None,
    summary: None,
    error: None,
  })
  WorkflowEngine::new(runtime~)
}

///|
async test "analysis_step_handler prefers run workspace over config cwd" {
  @fsx.with_temporary_directory("job-analysis-workspace-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config_cwd = @pathx.join(dir, "config-cwd")
    let run_workspace = @pathx.join(dir, "run-workspace")
    @fsx.make_directory(config_cwd, recursive=true)
    @fsx.make_directory(run_workspace, recursive=true)
    @fsx.make_directory(
      run_workspace
      |> @pathx.join("skills")
      |> @pathx.join("research-paper-summary"),
      recursive=true,
    )
    @fsx.write_to_file(
      run_workspace
      |> @pathx.join("skills")
      |> @pathx.join("research-paper-summary")
      |> @pathx.join("SKILL.md"),
      "RUN_WORKSPACE_SKILL_MARKER",
    )
    let config = AnalysisStepConfig::new(
      prompt="Check working directory selection.",
      cwd=Some(config_cwd),
      preferred_skills=["research-paper-summary"],
    )
    let engine = analysis_test_engine(
      root,
      config,
      workspace_dir=Some(run_workspace),
    )
    let captured : Ref[String] = { val: "" }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          captured.val = request.cwd
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content: request.prompt,
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
        now=fn() { 1000 },
      ),
    )
    ignore(
      match engine.execute_run("run-analysis-1", fn() { 1000 }) {
        Ok(result) => result
        Err(error) => fail(error)
      },
    )
    inspect(captured.val, content=run_workspace)
  })
}

///|
async test "analysis_step_handler persists report and result artifacts" {
  @fsx.with_temporary_directory("job-analysis-handler-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Summarize the parsed paper output.",
      preferred_skills=["paper-reading"],
      artifacts=AnalysisArtifactConfig::new(logical_key=Some("paper:1"), scope=[
        "research", "paper:1",
      ]),
      policy=AnalysisPolicy::new(max_total_tokens=Some(200)),
    )
    let engine = analysis_test_engine(root, config)
    let requests : Ref[Int] = { val: 0 }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          requests.val = requests.val + 1
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content: "A concise analysis report.",
            conversation_id: Some("conv-1"),
            usage: Some(@ai.usage(input_tokens=40, output_tokens=60)),
            metadata: { "captured_prompt": request.prompt },
          })
        }),
        now=fn() { 1000 },
      ),
    )

    let result = match engine.execute_run("run-analysis-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(requests.val, content="1")
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    inspect(
      result.outputs
      .get("analyze")
      .map(fn(output) { output.stringify().contains("report_artifact_id") })
      .unwrap_or(false),
      content="true",
    )
    let stored_artifacts = engine.runtime.store().list_artifacts()
    inspect(stored_artifacts.length(), content="2")
    inspect(
      stored_artifacts.map(fn(artifact) { artifact.artifact_type }).join(","),
      content="analysis.report,analysis.result",
    )
  })
}

///|
async test "analysis_step_handler passes execution routing hints into executor" {
  @fsx.with_temporary_directory("job-analysis-routing-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Route this analysis through ACP.",
      cwd=Some(dir),
      execution_mode=Some("acp"),
      execution_target=Some("codex-main"),
    )
    let engine = analysis_test_engine(root, config)
    let captured_mode : Ref[String] = { val: "" }
    let captured_target : Ref[String] = { val: "" }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          captured_mode.val = request.execution_mode.unwrap_or("")
          captured_target.val = request.execution_target.unwrap_or("")
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content: "ok",
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
        now=fn() { 1000 },
      ),
    )

    ignore(
      match engine.execute_run("run-analysis-1", fn() { 1000 }) {
        Ok(result) => result
        Err(error) => fail(error)
      },
    )
    inspect(captured_mode.val, content="acp")
    inspect(captured_target.val, content="codex-main")
  })
}

///|
async test "analysis_step_handler loads local skill file content into prompt" {
  @fsx.with_temporary_directory("job-analysis-skill-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let skill_dir = dir
      |> @pathx.join("skills")
      |> @pathx.join("research-paper-summary")
    @fsx.make_directory(skill_dir, recursive=true)
    @fsx.write_to_file(
      skill_dir |> @pathx.join("SKILL.md"),
      [
        "---", "name: research-paper-summary", "description: test skill", "---",
        "", "Include the exact phrase SKILL_SUMMARY_MARKER.",
      ].join("\n"),
    )
    let config = AnalysisStepConfig::new(
      prompt="Summarize the parsed paper output.",
      cwd=Some(dir),
      preferred_skills=["research-paper-summary"],
    )
    let engine = analysis_test_engine(root, config)
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content: request.prompt,
            conversation_id: Some("conv-1"),
            usage: None,
            metadata: { "captured_prompt": request.prompt },
          })
        }),
        now=fn() { 1000 },
      ),
    )
    let result = match engine.execute_run("run-analysis-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(
      result.outputs
      .get("analyze")
      .map(fn(output) { output.stringify().contains("SKILL_SUMMARY_MARKER") })
      .unwrap_or(false),
      content="true",
    )
  })
}

///|
async test "analysis_step_handler includes relevant memory context in prompt" {
  @fsx.with_temporary_directory("job-analysis-memory-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Summarize the parsed paper output.",
      cwd=Some(dir),
      artifacts=AnalysisArtifactConfig::new(scope=["research"]),
    )
    let engine = analysis_test_engine(root, config)
    engine.runtime
    .store()
    .save_memory(MemoryRecord::{
      id: "memory-analysis-1",
      kind: "note",
      title: Some("research memory"),
      content: "Remember to highlight benchmark coverage and action-conditioned evaluation.",
      metadata: {},
      tags: ["research"],
      scope: ["research"],
      workspace: Some(dir),
      agent_id: None,
      channel_id: None,
      account_id: None,
      recipient: None,
      thread_id: None,
      source_artifact_id: None,
      status: MemoryStatus::Active,
      created_at: 10,
      updated_at: 10,
      archived_at: None,
    })
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content: request.prompt,
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
        now=fn() { 1000 },
      ),
    )
    let _ = match engine.execute_run("run-analysis-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    let artifacts = ArtifactStore::new(store=engine.runtime.store())
    let report_artifact = artifacts.list(
        query=ArtifactQuery::new(artifact_type=Some("analysis.report")),
      )[0]
    let report_text = artifacts.read_text(report_artifact.id).unwrap_or("")
    inspect(
      report_text.contains("Relevant long-term memory for this step"),
      content="true",
    )
    inspect(
      report_text.contains("action-conditioned evaluation"),
      content="true",
    )
  })
}

///|
test "requested_model_name_or_none treats default as auto-detect" {
  inspect(requested_model_name_or_none("default") is None, content="true")
  inspect(requested_model_name_or_none("  ") is None, content="true")
  inspect(
    requested_model_name_or_none("qwen/qwen3-coder-plus").unwrap_or(""),
    content="qwen/qwen3-coder-plus",
  )
}

///|
async test "analysis_step_handler skips when matching artifact already exists" {
  @fsx.with_temporary_directory("job-analysis-skip-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Should be skipped.",
      policy=AnalysisPolicy::new(skip_if_artifact_exists=true),
      artifacts=AnalysisArtifactConfig::new(logical_key=Some("paper:1")),
    )
    let engine = analysis_test_engine(root, config)
    let artifacts = ArtifactStore::new(store=engine.runtime.store())
    ignore(
      artifacts.write(
        ArtifactWriteRequest::new(
          run_id="run-previous",
          job_id="job.analysis",
          artifact_type="analysis.report",
          logical_key=Some("paper:1"),
          content="Existing report",
        ),
        "artifact-existing",
        100,
      ),
    )
    let requests : Ref[Int] = { val: 0 }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(_request) {
          requests.val = requests.val + 1
          Ok(AnalysisExecution::{
            model_name: "default",
            content: "unexpected",
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
        now=fn() { 200 },
      ),
    )

    let result = match engine.execute_run("run-analysis-1", fn() { 200 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(requests.val, content="0")
    inspect(
      result.steps[0].summary.unwrap_or(""),
      content="Skipped existing analysis artifact",
    )
  })
}

///|
async test "analysis_step_handler enforces timeout and token budget policies" {
  @fsx.with_temporary_directory("job-analysis-policy-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let timeout_engine = analysis_test_engine(
      root |> @pathx.join("timeout"),
      AnalysisStepConfig::new(
        prompt="timeout",
        policy=AnalysisPolicy::new(timeout_ms=Some(10)),
      ),
    )
    timeout_engine.register_handler(
      analysis_step_handler(
        runtime=timeout_engine.runtime,
        executor=AnalysisExecutor::new(run=async fn(_request) {
          @async.sleep(50)
          Ok(AnalysisExecution::{
            model_name: "default",
            content: "late",
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
        now=fn() { 300 },
      ),
    )
    inspect(
      timeout_engine.execute_run("run-analysis-1", fn() { 300 })
      is Err("Analysis step analyze timed out after 10ms"),
      content="true",
    )

    let budget_engine = analysis_test_engine(
      root |> @pathx.join("budget"),
      AnalysisStepConfig::new(
        prompt="budget",
        policy=AnalysisPolicy::new(max_total_tokens=Some(50)),
      ),
    )
    budget_engine.register_handler(
      analysis_step_handler(
        runtime=budget_engine.runtime,
        executor=AnalysisExecutor::new(run=fn(_request) {
          Ok(AnalysisExecution::{
            model_name: "default",
            content: "too large",
            conversation_id: None,
            usage: Some(@ai.usage(input_tokens=40, output_tokens=30)),
            metadata: {},
          })
        }),
        now=fn() { 400 },
      ),
    )
    inspect(
      budget_engine.execute_run("run-analysis-1", fn() { 400 })
      is Err("Analysis exceeded token budget: 70 > 50"),
      content="true",
    )
  })
}

///|
async test "setup_analysis_agent registers execute_command tool" {
  let agent = @agent.new(
    @model.Model::new(
      api_key="",
      base_url="https://example.invalid/v1",
      name="test-model",
      safe_zone_tokens=4096,
    ),
    cwd="/tmp",
    logger=@pino.logger("job-analysis-test", @pino.Transport::console()),
  )
  setup_analysis_agent(agent, "/tmp")
  inspect(agent.tools().contains("execute_command"), content="true")
}
