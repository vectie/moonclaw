///|
async fn analysis_test_engine(
  root : String,
  config : AnalysisStepConfig,
  workspace_dir? : String? = None,
  depth? : Int = 0,
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
    depth,
    workspace_dir,
    status: RunStatus::Pending,
    attempt: 1,
    retry_of: None,
    started_at: None,
    finished_at: None,
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
          let content = if requests.val == 2 {
            "{\"verdict\":\"completed\",\"summary\":\"done\"}"
          } else {
            "A concise analysis report."
          }
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content,
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
    inspect(requests.val, content="2")
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
async test "analysis_step_handler projects tool journal into logs and result metadata" {
  @fsx.with_temporary_directory("job-analysis-tool-journal-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(prompt="Use tools and keep a journal.")
    let engine = analysis_test_engine(root, config)
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          let journal_path = analysis_tool_journal_path(request)
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content: "Finished analysis with tool trace.",
            conversation_id: Some("conv-tool-journal"),
            usage: None,
            metadata: {
              "tool_call_journal_path": journal_path,
              "tool_call_journal": [
                {
                  "phase": "start",
                  "tool": "read_file",
                  "arguments": "{\"path\":\"README.md\"}",
                },
                {
                  "phase": "finish",
                  "tool": "read_file",
                  "ok": true,
                  "preview": "Opened README.md successfully.",
                },
              ],
            },
          })
        }),
        now=fn() { 1000 },
      ),
    )

    let result = match engine.execute_run("run-analysis-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    let step = result.steps[0]
    inspect(step.logs.join("\n").contains("tool journal: "), content="true")
    inspect(
      step.logs.join("\n").contains("tool[start]: read_file"),
      content="true",
    )
    inspect(
      step.logs.join("\n").contains("tool[finish]: read_file ok"),
      content="true",
    )
    let artifacts = ArtifactStore::new(store=engine.runtime.store())
    let result_artifact = engine.runtime
      .store()
      .list_artifacts(run_id="run-analysis-1")
      .filter(fn(artifact) { artifact.artifact_type == "analysis.result" })[0]
    let payload = artifacts.read_text(result_artifact.id).unwrap_or("")
    inspect(payload.contains("\"tool_call_journal\""), content="true")
    inspect(payload.contains("\"tool_call_journal_path\""), content="true")
    inspect(payload.contains("\"tool_call_journal_count\""), content="true")
    inspect(payload.contains("\"result\""), content="false")
  })
}

///|
async test "analysis_step_handler stamps running step with session journal before executor returns" {
  @fsx.with_temporary_directory("job-analysis-session-journal-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Start session journal before the executor completes.",
      cwd=Some(dir),
      policy=AnalysisPolicy::new(timeout_ms=Some(1234)),
      metadata={ "timeout_ms": 1234 },
    )
    let engine = analysis_test_engine(root, config)
    let observed_logs : Ref[String] = { val: "" }
    let observed_journal_path : Ref[String] = { val: "" }
    let observed_journal_exists : Ref[Bool] = { val: false }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=async fn(request) {
          observed_journal_path.val = analysis_tool_journal_path(request)
          observed_journal_exists.val = @fs.exists(observed_journal_path.val)
          let step = engine.runtime
            .store()
            .get_step_run("run-analysis-1", "analyze")
          observed_logs.val = match step {
            Some(step) => step.logs.join("\n")
            None => ""
          }
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content: "finished",
            conversation_id: Some("conv-session-journal"),
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
    inspect(observed_journal_exists.val, content="true")
    inspect(
      observed_logs.val.contains("analysis session journal: "),
      content="true",
    )
    inspect(observed_logs.val.contains("analysis cwd: \{dir}"), content="true")
    inspect(
      observed_logs.val.contains("analysis timeout_ms: 1234"),
      content="true",
    )
    let journal_text = @fs.read_file(observed_journal_path.val).text()
    inspect(journal_text.contains("\"phase\": \"session\""), content="true")
    inspect(journal_text.contains("\"event\": \"started\""), content="true")
  })
}

///|
async test "analysis_step_handler timeout points to tool journal path" {
  @fsx.with_temporary_directory("job-analysis-timeout-journal-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Time out after writing a tool journal.",
      cwd=Some(dir),
      policy=AnalysisPolicy::new(timeout_ms=Some(10)),
    )
    let engine = analysis_test_engine(root, config)
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=async fn(request) {
          ignore(request)
          @async.sleep(50)
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content: "late result",
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
        now=fn() { 1000 },
      ),
    )
    let error = match engine.execute_run("run-analysis-1", fn() { 1000 }) {
      Ok(_) => fail("expected timeout")
      Err(error) => error
    }
    inspect(error.contains("tool journal:"), content="true")
    inspect(error.contains(".moonclaw-tool-journal-"), content="true")
  })
}

///|
async test "analysis_step_handler parses structured presentation result payload when contract is declared" {
  @fsx.with_temporary_directory("job-analysis-presentation-result-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Generate a presentation plan.",
      metadata={
        "result_content_json_contract": presentation_contract_version(),
      },
      artifacts=AnalysisArtifactConfig::new(
        result_file_name=Some("presentation_plan.json"),
      ),
    )
    let engine = analysis_test_engine(root, config)
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          ignore(request)
          Ok(AnalysisExecution::{
            model_name: "codex/gpt-5.4",
            content: "{\"title\":\"Land acquisition deck\",\"objective\":\"Present screening estimate\",\"pages\":[{\"page_number\":1,\"page_type\":\"title\",\"headline\":\"Land acquisition estimate\",\"purpose\":\"Open the story\",\"key_message\":\"This is a screening estimate\",\"body_points\":[\"Estimate range\"],\"evidence\":[\"Internal model\"],\"visual_type\":\"title\",\"layout_instruction\":\"Large title with one KPI strip\",\"look_and_feel\":\"Board-clean executive style\"}],\"render_handoff\":{\"renderer_target\":\"slides-main\",\"theme\":\"board-clean\",\"delivery_notes\":\"Keep labels bilingual if needed\",\"asset_requests\":[\"site map\"]}}",
            conversation_id: Some("conv-presentation-1"),
            usage: None,
            metadata: {},
          })
        }),
        now=fn() { 1000 },
      ),
    )
    let result = match engine.execute_run("run-analysis-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    let artifacts = ArtifactStore::new(store=engine.runtime.store())
    let artifact = engine.runtime.store().list_artifacts()[1]
    let content = artifacts.read_text(artifact.id).unwrap_or("")
    inspect(artifact.artifact_type, content="analysis.result")
    inspect(content.contains("\"content_contract\""), content="true")
    inspect(
      content.contains("\"content_contract\":\"presentation_deck_spec.v1\""),
      content="true",
    )
    inspect(content.contains("\"parsed_content\""), content="true")
    inspect(
      content.contains("\"title\":\"Land acquisition deck\""),
      content="true",
    )
  })
}

///|
async test "analysis_step_handler parses structured presentation render payload when contract is declared" {
  @fsx.with_temporary_directory(
    "job-analysis-presentation-render-result-XXXXXX",
    dir => {
      let root = @pathx.join(dir, "jobs")
      let config = AnalysisStepConfig::new(
        prompt="Render a presentation package.",
        metadata={
          "result_content_json_contract": presentation_render_contract_version(),
        },
        artifacts=AnalysisArtifactConfig::new(
          result_file_name=Some("presentation_render_result.json"),
        ),
      )
      let engine = analysis_test_engine(root, config)
      engine.register_handler(
        analysis_step_handler(
          runtime=engine.runtime,
          executor=AnalysisExecutor::new(run=fn(request) {
            ignore(request)
            Ok(AnalysisExecution::{
              model_name: "codex/gpt-5.4",
              content: "{\"provider\":\"slides-vendor\",\"renderer_target\":\"slides-main\",\"theme\":\"board-clean\",\"source_plan_contract\":\"presentation_deck_spec.v1\",\"source_plan_artifact\":\"artifact://presentation-plan\",\"output_kind\":\"vendor_handoff\",\"produced_artifacts\":[{\"role\":\"deck_json\",\"path\":\"outputs/presentation/render.json\",\"description\":\"Renderer package\"}],\"handoff_summary\":\"Ready for vendor upload\",\"notes\":[\"Use brand template\"]}",
              conversation_id: Some("conv-presentation-render-1"),
              usage: None,
              metadata: {},
            })
          }),
          now=fn() { 1000 },
        ),
      )
      let result = match engine.execute_run("run-analysis-1", fn() { 1000 }) {
        Ok(result) => result
        Err(error) => fail(error)
      }
      inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
      let artifacts = ArtifactStore::new(store=engine.runtime.store())
      let artifact = engine.runtime.store().list_artifacts()[1]
      let content = artifacts.read_text(artifact.id).unwrap_or("")
      inspect(artifact.artifact_type, content="analysis.result")
      inspect(
        content.contains(
          "\"content_contract\":\"presentation_render_package.v1\"",
        ),
        content="true",
      )
      inspect(content.contains("\"parsed_content\""), content="true")
      inspect(
        content.contains("\"output_kind\":\"vendor_handoff\""),
        content="true",
      )
    },
  )
}

///|
async test "analysis_step_handler materializes outputs into run workspace" {
  @fsx.with_temporary_directory("job-analysis-workspace-output-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let run_workspace = @pathx.join(dir, "run-workspace")
    @fsx.make_directory(run_workspace, recursive=true)
    let config = AnalysisStepConfig::new(prompt="Produce a final report.")
    let engine = analysis_test_engine(
      root,
      config,
      workspace_dir=Some(run_workspace),
    )
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content: "A concise final report.",
            conversation_id: Some("conv-1"),
            usage: None,
            metadata: { "status": "completed" },
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
    inspect(
      @fsx.read_file(
        run_workspace
        |> @pathx.join("outputs")
        |> @pathx.join("step-analyze-analyze.md"),
      ),
      content="A concise final report.",
    )
    inspect(
      @fsx.read_file(run_workspace |> @pathx.join("report.md")),
      content="A concise final report.",
    )
    inspect(
      @fsx.read_file(run_workspace |> @pathx.join("result.json")).contains(
        "\"status\":\"completed\"",
      ),
      content="true",
    )
  })
}

///|
async test "analysis_step_handler honors nested disable_adaptive metadata" {
  @fsx.with_temporary_directory("job-analysis-disable-adaptive-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(prompt="Preprocess only.", metadata={
      "step_metadata": { "disable_adaptive": true },
    })
    let engine = analysis_test_engine(root, config)
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content: "{\"verdict\":\"needs_input\",\"summary\":\"Should stay as content\",\"missing_inputs\":[\"parcel size\"]}",
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
        now=fn() { 1000 },
      ),
    )
    let result = match engine.execute_run("run-analysis-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    inspect(
      result.outputs
      .get("analyze")
      .map(fn(output) {
        match output {
          { "content": String(text), .. } => text.contains("\"needs_input\"")
          _ => false
        }
      })
      .unwrap_or(false),
      content="true",
    )
  })
}

///|
test "analysis_tool_contract defaults from legacy booleans" {
  let enabled = analysis_tool_contract(
    AnalysisStepConfig::new(
      prompt="Analyze.",
      enable_tools=true,
      web_search=true,
    ),
  )
  inspect(enabled.shell.to_json().stringify(), content="true")
  inspect(enabled.glob_files.to_json().stringify(), content="true")
  inspect(enabled.list_resources.to_json().stringify(), content="true")
  inspect(enabled.read_resource.to_json().stringify(), content="true")
  inspect(enabled.delegate_run.to_json().stringify(), content="true")
  inspect(enabled.read_files.to_json().stringify(), content="true")
  inspect(enabled.patch_edit.to_json().stringify(), content="true")
  inspect(enabled.web_fetch.to_json().stringify(), content="true")
  inspect(enabled.web_search.to_json().stringify(), content="true")

  let disabled = analysis_tool_contract(
    AnalysisStepConfig::new(
      prompt="Analyze.",
      enable_tools=false,
      web_search=true,
    ),
  )
  inspect(disabled.shell.to_json().stringify(), content="false")
  inspect(disabled.glob_files.to_json().stringify(), content="false")
  inspect(disabled.list_resources.to_json().stringify(), content="false")
  inspect(disabled.read_resource.to_json().stringify(), content="false")
  inspect(disabled.delegate_run.to_json().stringify(), content="false")
  inspect(disabled.read_files.to_json().stringify(), content="false")
  inspect(disabled.patch_edit.to_json().stringify(), content="false")
  inspect(disabled.web_fetch.to_json().stringify(), content="false")
  inspect(disabled.web_search.to_json().stringify(), content="false")
}

///|
test "analysis_tool_contract prefers structured metadata contract" {
  let contract = analysis_tool_contract(
    AnalysisStepConfig::new(prompt="Analyze.", enable_tools=false, metadata={
      "tool_contract": {
        "shell": false,
        "list_files": true,
        "glob_files": true,
        "list_resources": true,
        "read_resource": true,
        "runtime_context": true,
        "list_worktrees": true,
        "delegate_run": true,
        "enter_worktree": false,
        "exit_worktree": false,
        "read_files": true,
        "search_files": false,
        "todo": false,
        "file_write": false,
        "patch_edit": true,
        "web_fetch": true,
        "web_search": true,
      },
    }),
  )
  inspect(contract.list_files.to_json().stringify(), content="true")
  inspect(contract.glob_files.to_json().stringify(), content="true")
  inspect(contract.list_resources.to_json().stringify(), content="true")
  inspect(contract.read_resource.to_json().stringify(), content="true")
  inspect(contract.runtime_context.to_json().stringify(), content="true")
  inspect(contract.list_worktrees.to_json().stringify(), content="true")
  inspect(contract.delegate_run.to_json().stringify(), content="true")
  inspect(contract.read_files.to_json().stringify(), content="true")
  inspect(contract.patch_edit.to_json().stringify(), content="true")
  inspect(contract.web_fetch.to_json().stringify(), content="true")
  inspect(contract.web_search.to_json().stringify(), content="true")
  inspect(contract.shell.to_json().stringify(), content="false")
}

///|
async test "analysis_step_handler honors nested skip_primary_workspace_output metadata" {
  @fsx.with_temporary_directory("job-analysis-skip-primary-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let run_workspace = @pathx.join(dir, "run-workspace")
    @fsx.make_directory(run_workspace, recursive=true)
    let config = AnalysisStepConfig::new(prompt="Write only step artifacts.", metadata={
      "step_metadata": { "skip_primary_workspace_output": true },
    })
    let engine = analysis_test_engine(
      root,
      config,
      workspace_dir=Some(run_workspace),
    )
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content: "Step artifact only.",
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
    inspect(
      @fsx.exists(
        run_workspace
        |> @pathx.join("outputs")
        |> @pathx.join("step-analyze-analyze.md"),
      ),
      content="true",
    )
    inspect(
      @fsx.exists(run_workspace |> @pathx.join("report.md")),
      content="false",
    )
    inspect(
      @fsx.exists(run_workspace |> @pathx.join("result.json")),
      content="false",
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
async test "default analysis runner launches acp target for cli execution" {
  @fsx.with_temporary_directory("job-analysis-acp-runner-XXXXXX", dir => {
    @fsx.write_to_file(
      dir |> @pathx.join("moonclaw.json"),
      (
        {
          "acp": {
            "targets": {
              "fake-acp": {
                "backend": "codex",
                "label": "Fake ACP",
                "command": "/bin/echo",
                "args": ["acp-executed"],
                "cwd": dir,
              },
            },
          },
        } : Json).stringify(indent=2),
    )
    let request = AnalysisRequest::{
      job_id: "job-1",
      run_id: "run-1",
      step_id: "step-1",
      source_prompt: "Run through ACP.",
      prompt: "Run through ACP.",
      model_name: "default",
      cwd: dir,
      home: Some(dir),
      execution_mode: Some("acp"),
      execution_target: Some("fake-acp"),
      system_prompt: "system",
      preferred_skills: [],
      enable_tools: false,
      web_search: false,
      tool_contract: AnalysisToolContract::new(
        shell=false,
        list_files=false,
        read_files=false,
        search_files=false,
        todo=false,
        file_write=false,
        web_search=false,
      ),
      step_metadata: {},
      execution_isolation: None,
      role_runtime_contract: None,
    }
    let execution = match run_default_analysis_runner(request) {
      Ok(execution) => execution
      Err(error) => fail(error)
    }
    inspect(execution.model_name, content="Fake ACP")
    inspect(execution.conversation_id.unwrap_or(""), content="acp-run-1-step-1")
    inspect(execution.content.contains("acp-executed"), content="true")
    inspect(execution.content.contains("Run through ACP."), content="true")
    let state = @fsx.read_file(
      dir |> @pathx.join(".moonclaw") |> @pathx.join("acp_sessions.json"),
    )
    inspect(state.contains("\"status\":\"completed\""), content="true")
  })
}

///|
async test "analysis_step_handler can trigger adaptive input verdict from followup model pass" {
  @fsx.with_temporary_directory("job-analysis-adaptive-judge-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Estimate land acquisition cost for an unknown parcel.",
      cwd=Some(dir),
    )
    let engine = analysis_test_engine(root, config)
    let calls : Ref[Int] = { val: 0 }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          calls.val = calls.val + 1
          let content = if calls.val == 2 {
            "{\"verdict\":\"needs_input\",\"summary\":\"Parcel facts missing\",\"missing_inputs\":[\"parcel location\",\"parcel size\"]}"
          } else {
            "This is a first-pass estimate with major missing assumptions."
          }
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content,
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
        now=fn() { 1000 },
      ),
    )

    let result = match engine.execute_run("run-analysis-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(calls.val, content="2")
    inspect(
      result.run.status.to_json().stringify(),
      content="\"WaitingForInput\"",
    )
    inspect(
      result.steps[0].status.to_json().stringify(),
      content="\"WaitingForInput\"",
    )
    inspect(
      result.run.summary.unwrap_or(""),
      content="Waiting for input on step analyze: parcel location; parcel size",
    )
  })
}

///|
async test "analysis_step_handler treats blocker-style prose as non-complete in followup judge" {
  @fsx.with_temporary_directory("job-analysis-adaptive-blocker-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Produce a decision-ready land acquisition estimate.",
      cwd=Some(dir),
    )
    let engine = analysis_test_engine(root, config)
    let calls : Ref[Int] = { val: 0 }
    let followup_prompt : Ref[String] = { val: "" }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          calls.val = calls.val + 1
          if calls.val == 2 {
            followup_prompt.val = request.prompt
            Ok(AnalysisExecution::{
              model_name: request.model_name,
              content: "{\"verdict\":\"needs_input\",\"summary\":\"Decision-grade estimate is blocked by missing parcel facts.\",\"missing_inputs\":[\"parcel location\",\"parcel size\",\"comparable sales\"]}",
              conversation_id: None,
              usage: None,
              metadata: {},
            })
          } else {
            Ok(AnalysisExecution::{
              model_name: request.model_name,
              content: [
                "**Decision-Ready Output**", "", "- No parcel-specific estimate can be produced yet.",
                "- Current status is screening only, not decision-grade underwriting.",
                "", "**Missing required inputs**", "- Parcel location", "- Parcel size",
                "- Comparable sales", "", "**Recommended next actions**", "1. Gather parcel facts.",
                "2. Build a comp set.",
              ].join("\n"),
              conversation_id: None,
              usage: None,
              metadata: {},
            })
          }
        }),
        now=fn() { 1000 },
      ),
    )

    let result = match engine.execute_run("run-analysis-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(calls.val, content="2")
    inspect(
      followup_prompt.val.contains(
        "If the current output mainly reports blockers, missing facts, provisional screening status, or next actions, it is not completed.",
      ),
      content="true",
    )
    inspect(
      result.run.status.to_json().stringify(),
      content="\"WaitingForInput\"",
    )
    inspect(
      result.steps[0].status.to_json().stringify(),
      content="\"WaitingForInput\"",
    )
    inspect(
      result.run.summary.unwrap_or(""),
      content="Waiting for input on step analyze: parcel location; parcel size; comparable sales",
    )
  })
}

///|
async test "analysis_step_handler loads analysis-adaptation skill into followup judge prompt" {
  @fsx.with_temporary_directory("job-analysis-adaptive-skill-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let skill_dir = dir
      |> @pathx.join("skills")
      |> @pathx.join("analysis-adaptation")
    @fsx.make_directory(skill_dir, recursive=true)
    @fsx.write_to_file(
      skill_dir |> @pathx.join("SKILL.md"),
      [
        "---", "name: analysis-adaptation", "description: test skill", "---", "",
        "Include the exact phrase ADAPTIVE_SKILL_MARKER.",
      ].join("\n"),
    )
    let config = AnalysisStepConfig::new(
      prompt="Produce a decision-ready land acquisition estimate.",
      cwd=Some(dir),
    )
    let engine = analysis_test_engine(root, config)
    let calls : Ref[Int] = { val: 0 }
    let followup_prompt : Ref[String] = { val: "" }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          calls.val = calls.val + 1
          if calls.val == 2 {
            followup_prompt.val = request.prompt
            Ok(AnalysisExecution::{
              model_name: request.model_name,
              content: "{\"verdict\":\"completed\",\"summary\":\"ok\"}",
              conversation_id: None,
              usage: None,
              metadata: {},
            })
          } else {
            Ok(AnalysisExecution::{
              model_name: request.model_name,
              content: "This is a first-pass estimate with major missing assumptions.",
              conversation_id: None,
              usage: None,
              metadata: {},
            })
          }
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
    inspect(calls.val, content="2")
    inspect(
      followup_prompt.val.contains("ADAPTIVE_SKILL_MARKER"),
      content="true",
    )
  })
}

///|
async test "analysis_step_handler degrades empty needs_subplan verdict into waiting for input" {
  @fsx.with_temporary_directory("job-analysis-empty-subplan-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Produce a decision-ready land acquisition estimate.",
      cwd=Some(dir),
    )
    let engine = analysis_test_engine(root, config)
    let calls : Ref[Int] = { val: 0 }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          calls.val = calls.val + 1
          let content = match calls.val {
            2 =>
              "{\"verdict\":\"needs_subplan\",\"summary\":\"Split this into narrower research tasks before estimating.\"}"
            _ =>
              "The estimate is too broad and under-specified to complete directly."
          }
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content,
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
        now=fn() { 1000 },
      ),
    )

    let result = match engine.execute_run("run-analysis-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(calls.val, content="3")
    inspect(
      result.run.status.to_json().stringify(),
      content="\"WaitingForInput\"",
    )
    inspect(
      result.run.summary.unwrap_or(""),
      content="Waiting for input on step analyze: Split this into narrower research tasks before estimating.",
    )
  })
}

///|
async test "analysis_step_handler preserves first-pass result on empty needs_subplan after resume guidance" {
  @fsx.with_temporary_directory("job-analysis-empty-subplan-resume-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Inspect the source material and report the usable findings.",
      cwd=Some(dir),
    )
    let engine = analysis_test_engine(root, config)
    let calls : Ref[Int] = { val: 0 }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          calls.val = calls.val + 1
          let content = match calls.val {
            2 =>
              "{\"verdict\":\"needs_subplan\",\"summary\":\"Adaptive subplan requested but no substeps were provided.\"}"
            _ =>
              "I inspected the available source material and produced a screening-level summary with explicit assumptions and risks."
          }
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content,
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
        now=fn() { 1000 },
      ),
    )

    let result = match
      engine.execute_run(
        "run-analysis-1",
        fn() { 1000 },
        initial_input=Some({ "resume_content": "guess missing input" }),
      ) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(calls.val, content="3")
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    inspect(
      result.outputs
      .get("analyze")
      .map(fn(output) { output.stringify().contains("screening-level summary") })
      .unwrap_or(false),
      content="true",
    )
  })
}

///|
async test "analysis_step_handler asks AI to fill explicit missing inputs for waiting message" {
  @fsx.with_temporary_directory("job-analysis-fill-missing-inputs-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Produce a decision-ready land acquisition estimate.",
      cwd=Some(dir),
    )
    let engine = analysis_test_engine(root, config)
    let calls : Ref[Int] = { val: 0 }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          calls.val = calls.val + 1
          let content = match calls.val {
            2 =>
              "{\"verdict\":\"needs_input\",\"summary\":\"More parcel facts are required before the estimate can proceed.\"}"
            3 =>
              "{\"verdict\":\"needs_input\",\"summary\":\"More parcel facts are required before the estimate can proceed.\",\"missing_inputs\":[\"parcel location\",\"parcel size\",\"comparable sales\"]}"
            _ => "This is only a screening view and cannot be finalized yet."
          }
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content,
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
        now=fn() { 1000 },
      ),
    )

    let result = match engine.execute_run("run-analysis-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(calls.val, content="3")
    inspect(
      result.run.status.to_json().stringify(),
      content="\"WaitingForInput\"",
    )
    inspect(
      result.run.summary.unwrap_or(""),
      content="Waiting for input on step analyze: parcel location; parcel size; comparable sales",
    )
  })
}

///|
async test "analysis_step_handler asks AI to synthesize missing substeps before executing subplan" {
  @fsx.with_temporary_directory("job-analysis-synth-subplan-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Produce a decision-ready land acquisition estimate.",
      cwd=Some(dir),
      model=Some("gpt-5.4"),
      system_prompt=Some("Stay source-grounded."),
      preferred_skills=["research", "estimation"],
      enable_tools=true,
      web_search=true,
    )
    let engine = analysis_test_engine(root, config)
    let calls : Ref[Int] = { val: 0 }
    let captured_child_proposal : Ref[JobProposal?] = { val: None }
    let compiler = ProposalCompiler::new(run=fn(proposal, now_ms, _cwd, _home) {
      captured_child_proposal.val = Some(proposal)
      let workflow = WorkflowDefinition::{
        id: "workflow.child.analysis",
        kind: "test.child",
        steps: [
          WorkflowStepDefinition::{
            id: "child-step",
            kind: "test.child",
            config: {},
            retry_policy: None,
          },
        ],
        output_bindings: ["child-step"],
      }
      let definition = JobDefinition::{
        id: "job.child.analysis",
        kind: "test.child",
        enabled: true,
        config: {},
        schedule: None,
        retry_policy: None,
        workflow_id: Some(workflow.id),
        created_at: now_ms,
        updated_at: now_ms,
        tags: ["child"],
      }
      ProposalCompilation::{
        family: "generic",
        definition,
        workflow,
        bindings: [],
      }
    })
    let child_engine_factory = fn() {
      let child_engine = WorkflowEngine::new(runtime=engine.runtime)
      child_engine.register_handler(
        WorkflowStepHandler::new(kind="test.child", run=fn(_context) {
          Ok(
            WorkflowStepResult::new(
              output={ "status": "completed", "note": "child complete" },
              summary=Some("child complete"),
            ),
          )
        }),
      )
      child_engine
    }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          calls.val = calls.val + 1
          let content = match calls.val {
            2 =>
              "{\"verdict\":\"needs_subplan\",\"summary\":\"Split this into narrower research tasks before estimating.\"}"
            3 =>
              "{\"verdict\":\"needs_subplan\",\"summary\":\"Split this into narrower research tasks before estimating.\",\"suggested_substeps\":[{\"title\":\"Patch valuation module\",\"prompt\":\"Update the valuation code file to support sensitivity ranges.\"},{\"title\":\"Prepare sensitivity template\",\"prompt\":\"Prepare a sensitivity template for land acquisition assumptions.\"}]}"
            _ =>
              "The estimate is too broad and under-specified to complete directly."
          }
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content,
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
        compiler=Some(compiler),
        engine_factory=Some(child_engine_factory),
        now=fn() { 1000 },
      ),
    )

    let result = match engine.execute_run("run-analysis-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(calls.val, content="3")
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    inspect(
      result.outputs
      .get("analyze")
      .map(fn(output) {
        output.stringify().contains("\"status\":\"subplanned\"")
      })
      .unwrap_or(false),
      content="true",
    )
    let parent_events = engine.runtime.store().list_run_events("run-analysis-1")
    inspect(
      parent_events
      .map(fn(event) { event.event_type })
      .contains("child_run.started"),
      content="true",
    )
    inspect(
      parent_events
      .map(fn(event) { event.event_type })
      .contains("child_run.succeeded"),
      content="true",
    )
    let child_proposal = match captured_child_proposal.val {
      Some(proposal) => proposal
      None => fail("missing child proposal")
    }
    inspect(
      child_proposal.steps[0].metadata.stringify().contains("git_worktree"),
      content="true",
    )
    inspect(
      child_proposal.steps[1].metadata.stringify().contains("git_worktree"),
      content="false",
    )
    inspect(
      child_proposal.steps[0].metadata
      .stringify()
      .contains("\"model\":\"gpt-5.4\""),
      content="true",
    )
    inspect(
      child_proposal.steps[0].metadata
      .stringify()
      .contains("\"system_prompt\":\"Stay source-grounded.\""),
      content="true",
    )
    inspect(
      child_proposal.steps[0].metadata
      .stringify()
      .contains("\"preferred_skills\":[\"research\",\"estimation\"]"),
      content="true",
    )
    inspect(
      child_proposal.steps[0].metadata
      .stringify()
      .contains("\"web_search\":true"),
      content="true",
    )
  })
}

///|
async test "analysis_step_handler treats keeper plan packet as completed output" {
  @fsx.with_temporary_directory("job-analysis-keeper-packet-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Inspect source and produce keeper plan packet.",
      cwd=Some(dir),
    )
    let engine = analysis_test_engine(root, config)
    let calls : Ref[Int] = { val: 0 }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          ignore(request)
          calls.val = calls.val + 1
          Ok(AnalysisExecution::{
            model_name: "gpt-5.4",
            content: "{\"packet_type\":\"keeper.plan.packet.v1\",\"status\":\"ok\",\"recommended_next_actions\":[\"Revise wiki/synthesis/claims.md\"]}",
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
        now=fn() { 1000 },
      ),
    )

    let result = match engine.execute_run("run-analysis-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(calls.val, content="1")
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    inspect(
      result.outputs
      .get("analyze")
      .map(fn(output) { output.stringify().contains("\"result_artifact_id\"") })
      .unwrap_or(false),
      content="true",
    )
  })
}

///|
async test "analysis_step_handler does not adaptive-subplan persisted provider completions" {
  @fsx.with_temporary_directory("job-analysis-provider-persisted-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Bootstrap gather for a wiki workspace.",
      cwd=Some(dir),
    )
    let engine = analysis_test_engine(root, config)
    let calls : Ref[Int] = { val: 0 }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          calls.val = calls.val + 1
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content: [
              "# Extension Task Result", "", "Completed bootstrap gather and prepared handoff into source_materialize.",
            ].join("\n"),
            conversation_id: Some("conv-provider-completed"),
            usage: None,
            metadata: {
              "execution_mode": "provider",
              "extension_task_id": "bootstrap_gather",
              "extension_result": {
                "task_id": "bootstrap_gather",
                "summary": "Completed bootstrap gather and wrote one packet.",
                "artifacts": ["raw/bootstrap/bootstrap.md"],
                "memory_candidates": [],
                "requires_review": true,
                "notify_town": false,
              },
            },
          })
        }),
        now=fn() { 1000 },
      ),
    )

    let result = match engine.execute_run("run-analysis-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(calls.val, content="1")
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    inspect(
      result.outputs
      .get("analyze")
      .map(fn(output) { output.stringify().contains("source_materialize") })
      .unwrap_or(false),
      content="true",
    )
  })
}

///|
async test "analysis_step_handler propagates missing-input policy into adaptive subplans" {
  @fsx.with_temporary_directory("job-analysis-adaptive-policy-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Estimate the parcel valuation.",
      cwd=Some(dir),
      metadata={
        "step_metadata": {
          "timeout_ms": 600000,
          "max_total_tokens": 24000,
          "disable_waiting_for_input": true,
          "best_effort_on_missing_input": true,
        },
      },
    )
    let engine = analysis_test_engine(root, config)
    let calls : Ref[Int] = { val: 0 }
    let captured_child_proposal : Ref[JobProposal?] = { val: None }
    let compiler = ProposalCompiler::new(run=fn(proposal, now_ms, _cwd, _home) {
      captured_child_proposal.val = Some(proposal)
      let workflow = WorkflowDefinition::{
        id: "workflow.child.analysis.policy",
        kind: "test.child",
        steps: [
          WorkflowStepDefinition::{
            id: "child-step",
            kind: "test.child",
            config: {},
            retry_policy: None,
          },
        ],
        output_bindings: ["child-step"],
      }
      let definition = JobDefinition::{
        id: "job.child.analysis.policy",
        kind: "test.child",
        enabled: true,
        config: {},
        schedule: None,
        retry_policy: None,
        workflow_id: Some(workflow.id),
        created_at: now_ms,
        updated_at: now_ms,
        tags: ["child"],
      }
      ProposalCompilation::{
        family: "generic",
        definition,
        workflow,
        bindings: [],
      }
    })
    let child_engine_factory = fn() {
      let child_engine = WorkflowEngine::new(runtime=engine.runtime)
      child_engine.register_handler(
        WorkflowStepHandler::new(kind="test.child", run=fn(_context) {
          Ok(
            WorkflowStepResult::new(
              output={ "status": "completed", "note": "child complete" },
              summary=Some("child complete"),
            ),
          )
        }),
      )
      child_engine
    }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          ignore(request)
          calls.val = calls.val + 1
          let content = match calls.val {
            2 =>
              "{\"verdict\":\"needs_subplan\",\"summary\":\"Split this into narrower research tasks before estimating.\",\"suggested_substeps\":[{\"title\":\"Collect evidence\",\"prompt\":\"Collect evidence for the valuation estimate.\"}]}"
            _ =>
              "The estimate is too broad and under-specified to complete directly."
          }
          Ok(AnalysisExecution::{
            model_name: "gpt-5.4",
            content,
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
        compiler=Some(compiler),
        engine_factory=Some(child_engine_factory),
        now=fn() { 1000 },
      ),
    )

    let result = match engine.execute_run("run-analysis-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    let child_proposal = match captured_child_proposal.val {
      Some(proposal) => proposal
      None => fail("missing child proposal")
    }
    inspect(
      child_proposal.profile_metadata
      .stringify()
      .contains("\"timeout_ms\":600000"),
      content="true",
    )
    inspect(
      child_proposal.profile_metadata
      .stringify()
      .contains("\"max_total_tokens\":24000"),
      content="true",
    )
    inspect(
      child_proposal.profile_metadata
      .stringify()
      .contains("\"disable_waiting_for_input\":true"),
      content="true",
    )
    inspect(
      child_proposal.profile_metadata
      .stringify()
      .contains("\"best_effort_on_missing_input\":true"),
      content="true",
    )
    inspect(
      child_proposal.steps[0].metadata
      .stringify()
      .contains("\"timeout_ms\":600000"),
      content="true",
    )
    inspect(
      child_proposal.steps[0].metadata
      .stringify()
      .contains("\"max_total_tokens\":24000"),
      content="true",
    )
    inspect(
      child_proposal.steps[0].metadata
      .stringify()
      .contains("\"disable_waiting_for_input\":true"),
      content="true",
    )
    inspect(
      child_proposal.steps[0].metadata
      .stringify()
      .contains("\"best_effort_on_missing_input\":true"),
      content="true",
    )
  })
}

///|
async test "analysis_step_handler treats keeper plan packet as completed output" {
  @fsx.with_temporary_directory("job-analysis-keeper-packet-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Inspect source and produce keeper plan packet.",
      cwd=Some(dir),
    )
    let engine = analysis_test_engine(root, config)
    let calls : Ref[Int] = { val: 0 }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          ignore(request)
          calls.val = calls.val + 1
          Ok(AnalysisExecution::{
            model_name: "gpt-5.4",
            content: "{\"packet_type\":\"keeper.plan.packet.v1\",\"status\":\"ok\",\"recommended_next_actions\":[\"Revise wiki/synthesis/claims.md\"]}",
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
        now=fn() { 1000 },
      ),
    )

    let result = match engine.execute_run("run-analysis-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(calls.val, content="1")
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    inspect(
      result.outputs
      .get("analyze")
      .map(fn(output) { output.stringify().contains("\"result_artifact_id\"") })
      .unwrap_or(false),
      content="true",
    )
  })
}

///|
async test "analysis_step_handler repairs invalid followup judge output" {
  @fsx.with_temporary_directory("job-analysis-adaptive-repair-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Produce a decision-ready land acquisition estimate.",
      cwd=Some(dir),
    )
    let engine = analysis_test_engine(root, config)
    let calls : Ref[Int] = { val: 0 }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          calls.val = calls.val + 1
          let content = match calls.val {
            1 =>
              [
                "I can’t produce a decision-ready estimate yet.", "The parcel location and comparable sales are missing.",
              ].join("\n")
            2 => "This is blocked because important facts are missing."
            _ =>
              "{\"verdict\":\"needs_input\",\"summary\":\"Decision-grade estimate is blocked by missing parcel facts.\",\"missing_inputs\":[\"parcel location\",\"comparable sales\"]}"
          }
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content,
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
        now=fn() { 1000 },
      ),
    )

    let result = match engine.execute_run("run-analysis-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(calls.val, content="3")
    inspect(
      result.run.status.to_json().stringify(),
      content="\"WaitingForInput\"",
    )
    inspect(
      result.run.summary.unwrap_or(""),
      content="Waiting for input on step analyze: parcel location; comparable sales",
    )
  })
}

///|
async test "analysis_step_handler honors adaptive max depth from moonclaw.json" {
  @fsx.with_temporary_directory("job-analysis-adaptive-depth-XXXXXX", dir => {
    @fsx.write_to_file(
      dir |> @pathx.join("moonclaw.json"),
      "{\n  \"jobs\": {\n    \"analysis\": {\n      \"adaptive\": {\n        \"max_depth\": 5\n      }\n    }\n  }\n}\n",
    )
    inspect(
      configured_adaptive_subplan_max_depth(dir, None).unwrap_or(0),
      content="5",
    )
  })
}

///|
async test "build_analysis_request turns resume guess instruction into explicit assumption guidance" {
  @fsx.with_temporary_directory("job-analysis-resume-guidance-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Estimate land acquisition value.",
      cwd=Some(dir),
    )
    let engine = analysis_test_engine(root, config)
    let captured_prompt : Ref[String] = { val: "" }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          if captured_prompt.val.is_blank() {
            captured_prompt.val = request.prompt
          }
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content: "A best-effort estimate with labeled assumptions.",
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
        now=fn() { 1000 },
      ),
    )

    ignore(
      match
        engine.execute_run(
          "run-analysis-1",
          fn() { 1000 },
          initial_input=Some({ "resume_content": "guess missing data" }),
        ) {
        Ok(result) => result
        Err(error) => fail(error)
      },
    )
    inspect(
      captured_prompt.val.contains(
        "Resume instruction from user:\nguess missing data",
      ),
      content="true",
    )
    inspect(
      captured_prompt.val.contains("authoritative operator guidance"),
      content="true",
    )
  })
}

///|
async test "build_analysis_request renders starter attachment artifacts" {
  @fsx.with_temporary_directory("job-analysis-starter-artifacts-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Review the starter materials and estimate the acquisition range.",
      cwd=Some(dir),
    )
    let engine = analysis_test_engine(root, config)
    let captured_prompt : Ref[String] = { val: "" }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          if captured_prompt.val.is_blank() {
            captured_prompt.val = request.prompt
          }
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content: "Used the starter artifacts.",
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
        now=fn() { 1000 },
      ),
    )

    ignore(
      match
        engine.execute_run(
          "run-analysis-1",
          fn() { 1000 },
          initial_input=Some({
            "starter_attachment_digest_excerpt": "# Starter Attachment Digest\n\nParcel overview",
            "starter_attachment_digest_path": "/tmp/ws/digest.md",
            "starter_attachment_digest_artifact_id": "artifact-run-1-starter-digest",
            "starter_attachment_artifacts": [
              {
                "id": "file-1",
                "filename": "parcel.pdf",
                "artifact_ids": [
                  "artifact-run-1-starter-file-1-text", "artifact-run-1-starter-file-1-summary",
                ],
              },
              {
                "kind": "manifest_markdown",
                "artifact_id": "artifact-run-1-starter-manifest-markdown",
              },
            ],
          }),
        ) {
        Ok(result) => result
        Err(error) => fail(error)
      },
    )
    inspect(
      captured_prompt.val.contains(
        "Starter attachment digest excerpt:\n# Starter Attachment Digest\n\nParcel overview",
      ),
      content="true",
    )
    inspect(
      captured_prompt.val.contains(
        "Aggregate starter attachment digest path: /tmp/ws/digest.md",
      ),
      content="true",
    )
    inspect(
      captured_prompt.val.contains(
        "Aggregate starter attachment digest artifact: artifact-run-1-starter-digest",
      ),
      content="true",
    )
    inspect(
      captured_prompt.val.contains("Starter attachment artifacts:"),
      content="true",
    )
    inspect(
      captured_prompt.val.contains(
        "Prefer `starter_attachment_digest_excerpt` first when present as the immediate compact starter-document overview.",
      ),
      content="true",
    )
    inspect(
      captured_prompt.val.contains(
        "Prefer `starter_attachment_digest_path` first when present as the directly readable aggregate starter-document overview.",
      ),
      content="true",
    )
    inspect(
      captured_prompt.val.contains(
        "Use `starter_attachment_digest_artifact_id` next when artifact-oriented tooling is available.",
      ),
      content="true",
    )
    inspect(
      captured_prompt.val.contains(
        "parcel.pdf: artifact-run-1-starter-file-1-summary, artifact-run-1-starter-file-1-text",
      ),
      content="true",
    )
    inspect(
      captured_prompt.val.contains(
        "Prefer `starter_attachment.summary` artifact ids first when available",
      ),
      content="true",
    )
    inspect(
      captured_prompt.val.contains(
        "manifest_markdown: artifact-run-1-starter-manifest-markdown",
      ),
      content="true",
    )
  })
}

///|
async test "analysis_step_handler keeps guessed deliverable completed after resume guidance" {
  @fsx.with_temporary_directory("job-analysis-resume-completed-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Estimate land acquisition value.",
      cwd=Some(dir),
    )
    let engine = analysis_test_engine(root, config)
    let calls : Ref[Int] = { val: 0 }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          calls.val = calls.val + 1
          let content = if calls.val == 1 {
            "Built a concrete screening-level land acquisition estimate despite missing parcel inputs by explicitly guessing the missing data.\n\n- Base-case estimate: RMB 50.9m\n- Assumptions are labeled and remaining risks are stated."
          } else {
            let sees_resume = request.prompt.contains(
                "Operator resume guidance:",
              ) &&
              request.prompt.contains("guess missing data")
            if sees_resume {
              "{\"verdict\":\"completed\",\"summary\":\"A usable assumption-based estimate was already delivered under operator guidance.\"}"
            } else {
              "{\"verdict\":\"needs_input\",\"summary\":\"Analysis requires additional inputs.\",\"missing_inputs\":[\"Analysis requires additional inputs.\"]}"
            }
          }
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content,
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
        now=fn() { 1000 },
      ),
    )
    let result = match
      engine.execute_run(
        "run-analysis-1",
        fn() { 1000 },
        initial_input=Some({ "resume_content": "guess missing data" }),
      ) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    inspect(calls.val, content="2")
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
async test "resolved_model_name uses configured primary model for default" {
  @fsx.with_temporary_directory("job-analysis-primary-model-XXXXXX", dir => {
    @fsx.write_to_file(
      dir |> @pathx.join("moonclaw.json"),
      { "agents": { "defaults": { "model": { "primary": "codex/gpt-5.4" } } } }
      .to_json()
      .stringify(indent=2),
    )
    let request = AnalysisRequest::{
      job_id: "job-1",
      run_id: "run-1",
      step_id: "step-1",
      source_prompt: "Plan the job.",
      prompt: "Plan the job.",
      model_name: "default",
      cwd: dir,
      home: None,
      execution_mode: None,
      execution_target: None,
      system_prompt: "system",
      preferred_skills: [],
      enable_tools: false,
      web_search: false,
      tool_contract: AnalysisToolContract::new(
        shell=false,
        list_files=false,
        read_files=false,
        search_files=false,
        todo=false,
        file_write=false,
        web_search=false,
      ),
      step_metadata: {},
      execution_isolation: None,
      role_runtime_contract: None,
    }
    inspect(resolved_model_name(request).unwrap_or(""), content="codex/gpt-5.4")
  })
}

///|
async test "build_analysis_request can isolate execution in a git worktree" {
  @fsx.with_temporary_directory("job-analysis-worktree-XXXXXX", dir => {
    @git.init_(dir)
    @fsx.write_to_file(dir |> @pathx.join("README.md"), "hello")
    @git.commit("init", ["README.md"], cwd=dir)
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Review the repository in isolation.",
      cwd=Some(dir),
      metadata={
        "execution_isolation": {
          "mode": "git_worktree",
          "task_key": "Review README",
        },
      },
    )
    let engine = analysis_test_engine(root, config, workspace_dir=Some(dir))
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
    inspect(captured.val.contains(".moonclaw-worktrees"), content="true")
    inspect(captured.val != dir, content="true")
    @worktree.remove_worktree_path(dir, captured.val)
  })
}

///|
async test "analysis_step_handler persists execution isolation metadata" {
  @fsx.with_temporary_directory("job-analysis-isolation-metadata-XXXXXX", dir => {
    @git.init_(dir)
    @fsx.write_to_file(dir |> @pathx.join("README.md"), "hello")
    @git.commit("init", ["README.md"], cwd=dir)
    let root = @pathx.join(dir, "jobs")
    let config = AnalysisStepConfig::new(
      prompt="Review the repository in isolation.",
      cwd=Some(dir),
      metadata={
        "execution_isolation": {
          "mode": "git_worktree",
          "task_key": "Inspect repo",
        },
      },
    )
    let engine = analysis_test_engine(root, config, workspace_dir=Some(dir))
    let captured_cwd : Ref[String] = { val: "" }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          captured_cwd.val = request.cwd
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content: "done",
            conversation_id: None,
            usage: None,
            metadata: { "execution_isolation": request.execution_isolation },
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
    let artifact = match
      engine.runtime
      .store()
      .list_artifacts(run_id="run-analysis-1")
      .filter(fn(artifact) { artifact.artifact_type == "analysis.result" })
      .get(0) {
      Some(artifact) => artifact
      None => fail("missing analysis result artifact")
    }
    inspect(
      artifact.metadata.stringify().contains("git_worktree"),
      content="true",
    )
    @worktree.remove_worktree_path(dir, captured_cwd.val)
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
      match timeout_engine.execute_run("run-analysis-1", fn() { 300 }) {
        Err(error) =>
          error.contains("Analysis step analyze timed out after 10ms")
        Ok(_) => false
      },
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
      match budget_engine.execute_run("run-analysis-1", fn() { 400 }) {
        Err(error) => error.contains("Analysis exceeded token budget: 70 > 50")
        Ok(_) => false
      },
      content="true",
    )
  })
}

///|
async test "analysis_step_handler bounds adaptive followup after persisted execution" {
  @fsx.with_temporary_directory("job-analysis-adaptive-timeout-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let engine = analysis_test_engine(
      root,
      AnalysisStepConfig::new(
        prompt="revise durable knowledge surfaces",
        policy=AnalysisPolicy::new(timeout_ms=Some(10)),
      ),
    )
    let requests : Ref[Int] = { val: 0 }
    engine.register_handler(
      analysis_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=async fn(_request) {
          requests.val = requests.val + 1
          if requests.val == 1 {
            Ok(AnalysisExecution::{
              model_name: "default",
              content: "Updated durable knowledge surfaces and wiki pages.",
              conversation_id: Some("conv-main"),
              usage: None,
              metadata: {},
            })
          } else {
            @async.sleep(50)
            Ok(AnalysisExecution::{
              model_name: "default",
              content: "{\"verdict\":\"completed\"}",
              conversation_id: Some("conv-followup"),
              usage: None,
              metadata: {},
            })
          }
        }),
        now=fn() { 500 },
      ),
    )

    let result = match engine.execute_run("run-analysis-1", fn() { 500 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(requests.val, content="2")
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    inspect(
      result.steps[0].status.to_json().stringify(),
      content="\"Succeeded\"",
    )
    inspect(result.steps[0].summary.unwrap_or(""), content="Analysis completed")
    inspect(
      engine.runtime.store().list_artifacts(run_id="run-analysis-1").length(),
      content="2",
    )
  })
}

///|
async test "configure_analysis_agent_tools registers execute_command tool" {
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
  configure_analysis_agent_tools(agent, "/tmp")
  inspect(agent.tools().contains("execute_command"), content="true")
  inspect(agent.tools().contains("glob_files"), content="true")
  inspect(agent.tools().contains("list_resources"), content="true")
  inspect(agent.tools().contains("read_resource"), content="true")
}

///|
async test "configure_analysis_agent_tools registers web_search tool when enabled" {
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
  configure_analysis_agent_tools(agent, "/tmp", web_search=true)
  inspect(agent.tools().contains("web_search"), content="true")
}

///|
async test "configure_analysis_agent_for_request registers runtime introspection tools" {
  let model = @model.Model::new(
    api_key="",
    base_url="https://example.invalid/v1",
    name="test-model",
    safe_zone_tokens=4096,
  )
  let agent = @agent.new(
    model,
    cwd="/tmp",
    logger=@pino.logger("job-analysis-test", @pino.Transport::console()),
  )
  let request = AnalysisRequest::{
    job_id: "job-1",
    run_id: "run-1",
    step_id: "step-1",
    source_prompt: "Inspect runtime.",
    prompt: "Inspect runtime.",
    model_name: "codex/gpt-5.4",
    cwd: "/tmp",
    home: Some("/tmp/home"),
    execution_mode: Some("vendor.presentation"),
    execution_target: Some("slides-main"),
    system_prompt: "system",
    preferred_skills: [],
    enable_tools: true,
    web_search: false,
    tool_contract: AnalysisToolContract::new(
      shell=false,
      list_files=false,
      glob_files=false,
      list_resources=false,
      read_resource=false,
      runtime_context=true,
      list_worktrees=true,
      delegate_run=true,
      enter_worktree=false,
      exit_worktree=false,
      read_files=false,
      search_files=false,
      todo=false,
      file_write=false,
      patch_edit=true,
      web_fetch=false,
      web_search=false,
    ),
    step_metadata: {},
    execution_isolation: Some({ "mode": "git_worktree" }),
    role_runtime_contract: None,
  }
  configure_analysis_agent_for_request(agent, request)
  inspect(agent.tools().contains("runtime_context"), content="true")
  inspect(agent.tools().contains("list_worktrees"), content="true")
  inspect(agent.tools().contains("delegate_run"), content="true")
  inspect(agent.tools().contains("patch_edit"), content="true")
}

///|
async test "configure_analysis_agent_for_request disables todo and delegate_run for provider execution" {
  let model = @model.Model::new(
    api_key="",
    base_url="https://example.invalid/v1",
    name="test-model",
    safe_zone_tokens=4096,
  )
  let agent = @agent.new(
    model,
    cwd="/tmp",
    logger=@pino.logger("job-analysis-test", @pino.Transport::console()),
  )
  let request = AnalysisRequest::{
    job_id: "job-1",
    run_id: "run-1",
    step_id: "step-1",
    source_prompt: "Provider task.",
    prompt: "Provider task.",
    model_name: "codex/gpt-5.4",
    cwd: "/tmp",
    home: Some("/tmp/home"),
    execution_mode: Some("provider"),
    execution_target: Some("moonbook"),
    system_prompt: "system",
    preferred_skills: [],
    enable_tools: true,
    web_search: false,
    tool_contract: AnalysisToolContract::new(
      shell=false,
      list_files=false,
      glob_files=false,
      list_resources=false,
      read_resource=false,
      runtime_context=true,
      list_worktrees=false,
      delegate_run=true,
      enter_worktree=false,
      exit_worktree=false,
      read_files=true,
      search_files=true,
      todo=true,
      file_write=false,
      patch_edit=true,
      web_fetch=false,
      web_search=false,
    ),
    step_metadata: {},
    execution_isolation: Some({ "mode": "git_worktree" }),
    role_runtime_contract: None,
  }
  configure_analysis_agent_for_request(agent, request)
  inspect(agent.tools().contains("runtime_context"), content="true")
  inspect(agent.tools().contains("execute_command"), content="false")
  inspect(agent.tools().contains("list_resources"), content="false")
  inspect(agent.tools().contains("read_resource"), content="false")
  inspect(agent.tools().contains("list_worktrees"), content="false")
  inspect(agent.tools().contains("todo"), content="false")
  inspect(agent.tools().contains("delegate_run"), content="false")
  inspect(agent.tools().contains("patch_edit"), content="true")
}

///|
async test "configure_analysis_agent_for_request disables todo and delegate_run for provider-derived adaptive subplans" {
  let model = @model.Model::new(
    api_key="",
    base_url="https://example.invalid/v1",
    name="test-model",
    safe_zone_tokens=4096,
  )
  let agent = @agent.new(
    model,
    cwd="/tmp",
    logger=@pino.logger("job-analysis-test", @pino.Transport::console()),
  )
  let request = AnalysisRequest::{
    job_id: "job-1",
    run_id: "run-1",
    step_id: "step-1",
    source_prompt: "Provider-derived child step.",
    prompt: "Provider-derived child step.",
    model_name: "codex/gpt-5.4",
    cwd: "/tmp",
    home: Some("/tmp/home"),
    execution_mode: None,
    execution_target: None,
    system_prompt: "system",
    preferred_skills: [],
    enable_tools: true,
    web_search: false,
    tool_contract: AnalysisToolContract::new(
      shell=false,
      list_files=false,
      glob_files=false,
      list_resources=false,
      read_resource=false,
      runtime_context=true,
      list_worktrees=false,
      delegate_run=true,
      enter_worktree=false,
      exit_worktree=false,
      read_files=true,
      search_files=true,
      todo=true,
      file_write=false,
      patch_edit=true,
      web_fetch=false,
      web_search=false,
    ),
    step_metadata: { "provider_subplan_execution": true },
    execution_isolation: Some({ "mode": "git_worktree" }),
    role_runtime_contract: None,
  }
  configure_analysis_agent_for_request(agent, request)
  inspect(agent.tools().contains("runtime_context"), content="true")
  inspect(agent.tools().contains("execute_command"), content="false")
  inspect(agent.tools().contains("list_resources"), content="false")
  inspect(agent.tools().contains("read_resource"), content="false")
  inspect(agent.tools().contains("list_worktrees"), content="false")
  inspect(agent.tools().contains("todo"), content="false")
  inspect(agent.tools().contains("delegate_run"), content="false")
  inspect(agent.tools().contains("patch_edit"), content="true")
}

///|
async test "configure_analysis_agent_for_request keeps explicit web tools for provider adaptive subplans" {
  let model = @model.Model::new(
    api_key="",
    base_url="https://example.invalid/v1",
    name="test-model",
    safe_zone_tokens=4096,
  )
  let agent = @agent.new(
    model,
    cwd="/tmp",
    logger=@pino.logger("job-analysis-test", @pino.Transport::console()),
  )
  let request = AnalysisRequest::{
    job_id: "job-1",
    run_id: "run-1",
    step_id: "step-1",
    source_prompt: "Provider-derived child step.",
    prompt: "Provider-derived child step.",
    model_name: "codex/gpt-5.4",
    cwd: "/tmp",
    home: Some("/tmp/home"),
    execution_mode: None,
    execution_target: None,
    system_prompt: "system",
    preferred_skills: [],
    enable_tools: true,
    web_search: true,
    tool_contract: AnalysisToolContract::new(web_fetch=true, web_search=true),
    step_metadata: { "provider_subplan_execution": true },
    execution_isolation: Some({ "mode": "git_worktree" }),
    role_runtime_contract: None,
  }
  configure_analysis_agent_for_request(agent, request)
  inspect(agent.tools().contains("web_search"), content="true")
  inspect(agent.tools().contains("web_fetch"), content="true")
  inspect(agent.tools().contains("execute_command"), content="false")
  inspect(agent.tools().contains("todo"), content="false")
}

///|
test "provider task single response routing applies to provider execution tasks" {
  let provider_request = AnalysisRequest::{
    job_id: "job-1",
    run_id: "run-1",
    step_id: "step-1",
    source_prompt: "Provider task.",
    prompt: "Provider task.",
    model_name: "codex/gpt-5.4",
    cwd: "/tmp",
    home: None,
    execution_mode: Some("provider"),
    execution_target: None,
    system_prompt: "system",
    preferred_skills: [],
    enable_tools: false,
    web_search: false,
    tool_contract: AnalysisToolContract::new(
      shell=false,
      list_files=false,
      glob_files=false,
      list_resources=false,
      read_resource=false,
      runtime_context=false,
      list_worktrees=false,
      delegate_run=false,
      enter_worktree=false,
      exit_worktree=false,
      read_files=false,
      search_files=false,
      todo=false,
      file_write=false,
      patch_edit=false,
      web_fetch=false,
      web_search=false,
    ),
    step_metadata: { "extension_task_id": "task-1" },
    execution_isolation: None,
    role_runtime_contract: None,
  }
  let normal_request = AnalysisRequest::{
    ..provider_request,
    execution_mode: None,
  }
  inspect(
    provider_task_single_response_requested(provider_request),
    content="true",
  )
  inspect(
    provider_task_single_response_requested(normal_request),
    content="false",
  )
}
