///|
async fn write_provider_task_fixture(
  workspace : String,
  script_path : String,
  state_path : String,
) -> Unit {
  @fsx.make_directory(
    workspace |> @pathx.join(".moonclaw"),
    recursive=true,
    exists_ok=true,
  )
  @fsx.make_directory(
    workspace |> @pathx.join("book-space"),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    workspace |> @pathx.join(".moonclaw") |> @pathx.join("providers.json"),
    (
      #|[
      #|  {
      #|    "name": "wiki-main",
      #|    "title": "Wiki Main",
      #|    "description": "Provider task fixture",
      #|    "kind": "extension",
      #|    "capabilities": ["provider.task"],
      #|    "metadata": {
      #|      "command": "sh",
      #|      "args": [
      #|        "__SCRIPT__",
      #|        "__STATE__"
      #|      ],
      #|      "workspace_root": "__ROOT__"
      #|    }
      #|  }
      #|]
    )
    .replace(old="__SCRIPT__", new=script_path)
    .replace(old="__STATE__", new=state_path)
    .replace(old="__ROOT__", new=workspace |> @pathx.join("book-space")),
  )
  @fsx.write_to_file(
    script_path,
    (
      #|#!/bin/sh
      #|set -eu
      #|state="$1"
      #|subcommand="$4"
      #|root="$5"
      #|if [ "$subcommand" = "tasks" ]; then
      #|  cat <<EOF
      #|{
      #|  "goal_id": "goal-1",
      #|  "goal": "$6",
      #|  "summary": "Provider task tasks for $6",
      #|  "tasks": [
      #|    {
      #|      "id": "task-1",
      #|      "title": "Extract durable updates",
      #|      "kind": "wiki.update",
      #|      "prompt": "Read the source and update the durable wiki state.",
      #|      "priority": 90,
      #|      "requires_review": true,
      #|      "target_pages": ["wiki/entity.md", "wiki/index.md"]
      #|    },
      #|    {
      #|      "id": "task-2",
      #|      "title": "Queue follow-up review",
      #|      "kind": "wiki.review",
      #|      "prompt": "Review the candidate changes and note open questions.",
      #|      "priority": 40,
      #|      "requires_review": false,
      #|      "target_pages": ["wiki/review.md"]
      #|    }
      #|  ]
      #|}
      #|EOF
      #|elif [ "$subcommand" = "context" ]; then
      #|  cat <<EOF
      #|{
      #|  "book_id": "book-1",
      #|  "workspace_root": "$root",
      #|  "task_id": "$8",
      #|  "prompt": "Use the source evidence to revise the wiki carefully.",
      #|  "policy": ["Keep raw sources immutable", "Prefer durable wiki updates"],
      #|  "routines": ["Update entity pages", "Append to the log when evidence changes"],
      #|  "skill_paths": ["skills/wiki-maintainer/SKILL.md"],
      #|  "context_pages": ["wiki/index.md", "wiki/entity.md"],
      #|  "active_memory": ["Entity already exists"],
      #|  "user_memory": ["User prefers precise sourcing"],
      #|  "working_memory": ["Need to reconcile source contradiction"],
      #|  "memory_summary": "Current book state has one unresolved contradiction.",
      #|  "output_contract": ["Return strict JSON", "List durable artifacts only"]
      #|}
      #|EOF
      #|elif [ "$subcommand" = "persist" ]; then
      #|  printf "%s\n" "$6" > "$state"
      #|  cat <<EOF
      #|{
      #|  "log_path": "wiki/log.md",
      #|  "updated_pages": ["wiki/entity.md", "wiki/index.md"],
      #|  "review_queued": true,
      #|  "notify_town": false,
      #|  "evidence_id": "evidence-1"
      #|}
      #|EOF
      #|else
      #|  exit 7
      #|fi
    ),
    create=0o755,
  )
}

///|
async fn write_multi_provider_task_fixture(
  workspace : String,
  script_path : String,
  state_path : String,
) -> Unit {
  let coding_root = workspace |> @pathx.join("books") |> @pathx.join("coding")
  let finance_root = workspace |> @pathx.join("books") |> @pathx.join("finance")
  @fsx.make_directory(
    workspace |> @pathx.join(".moonclaw"),
    recursive=true,
    exists_ok=true,
  )
  @fsx.make_directory(coding_root, recursive=true, exists_ok=true)
  @fsx.make_directory(finance_root, recursive=true, exists_ok=true)
  @fsx.write_to_file(
    workspace |> @pathx.join(".moonclaw") |> @pathx.join("providers.json"),
    (
      #|[
      #|  {
      #|    "name": "coding-main",
      #|    "title": "Coding Main",
      #|    "description": "Coding provider task fixture",
      #|    "kind": "extension",
      #|    "capabilities": ["provider.task"],
      #|    "metadata": {
      #|      "command": "sh",
      #|      "args": [
      #|        "__SCRIPT__",
      #|        "__STATE__"
      #|      ],
      #|      "workspace_root": "__CODING__"
      #|    }
      #|  },
      #|  {
      #|    "name": "finance-main",
      #|    "title": "Finance Main",
      #|    "description": "Finance provider task fixture",
      #|    "kind": "extension",
      #|    "capabilities": ["provider.task"],
      #|    "metadata": {
      #|      "command": "sh",
      #|      "args": [
      #|        "__SCRIPT__",
      #|        "__STATE__"
      #|      ],
      #|      "workspace_root": "__FINANCE__"
      #|    }
      #|  }
      #|]
    )
    .replace(old="__SCRIPT__", new=script_path)
    .replace(old="__STATE__", new=state_path)
    .replace(old="__CODING__", new=coding_root)
    .replace(old="__FINANCE__", new=finance_root),
  )
  @fsx.write_to_file(
    script_path,
    (
      #|#!/bin/sh
      #|set -eu
      #|state="$1"
      #|subcommand="$4"
      #|root="$5"
      #|if [ "$subcommand" = "tasks" ]; then
      #|  cat <<EOF
      #|{
      #|  "goal_id": "goal-1",
      #|  "goal": "Workspace affinity goal",
      #|  "summary": "Provider task tasks for workspace affinity",
      #|  "tasks": [
      #|    {
      #|      "id": "task-1",
      #|      "title": "Extract durable updates",
      #|      "kind": "wiki.update",
      #|      "prompt": "Read the source and update the durable wiki state.",
      #|      "priority": 90,
      #|      "requires_review": true,
      #|      "target_pages": ["wiki/entity.md", "wiki/index.md"]
      #|    }
      #|  ]
      #|}
      #|EOF
      #|elif [ "$subcommand" = "context" ]; then
      #|  cat <<EOF
      #|{
      #|  "book_id": "book-1",
      #|  "workspace_root": "$root",
      #|  "task_id": "$8",
      #|  "prompt": "Use the source evidence to revise the wiki carefully.",
      #|  "policy": ["Keep raw sources immutable"],
      #|  "routines": ["Update entity pages"],
      #|  "skill_paths": ["skills/wiki-maintainer/SKILL.md"],
      #|  "context_pages": ["wiki/index.md", "wiki/entity.md"],
      #|  "active_memory": [],
      #|  "user_memory": [],
      #|  "working_memory": [],
      #|  "memory_summary": "",
      #|  "output_contract": ["Return strict JSON"]
      #|}
      #|EOF
      #|elif [ "$subcommand" = "persist" ]; then
      #|  printf "%s\n" "$6" > "$state"
      #|  cat <<EOF
      #|{
      #|  "log_path": "wiki/log.md",
      #|  "updated_pages": ["wiki/entity.md", "wiki/index.md"],
      #|  "review_queued": false,
      #|  "notify_town": false,
      #|  "evidence_id": "evidence-1"
      #|}
      #|EOF
      #|else
      #|  exit 7
      #|fi
    ),
    create=0o755,
  )
}

///|
async test "provider task batch maps provider-backed extension tasks into a child proposal" {
  @fsx.with_temporary_directory("job-book-harness-proposal-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let script_path = @pathx.join(dir, "provider_task.sh")
    let state_path = @pathx.join(dir, "persisted-path.txt")
    @fsx.make_directory(workspace, recursive=true, exists_ok=true)
    write_provider_task_fixture(workspace, script_path, state_path)

    let config = SubjobStepConfig::new(
      request_text="unused",
      child_profile=Some("wiki_worker"),
      include_parent_outputs=true,
      max_depth=4,
      execution_mode=Some("provider"),
      execution_target=Some("wiki-main"),
    )
    let target_id : String? = Some("wiki-main")
    let (_, batch) = match
      load_provider_task_task_batch(
        workspace,
        None,
        target_id,
        "Update the knowledge base",
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    let proposal = provider_task_child_proposal(
      "Update the knowledge base", batch, config, 1000,
    )

    inspect(proposal.suggested_family.unwrap_or(""), content="extension")
    inspect(proposal.steps.length(), content="2")
    inspect(proposal.steps[0].kind, content="job.analysis")
    inspect(proposal.steps[0].execution_mode.unwrap_or(""), content="provider")
    inspect(
      proposal.steps[0].execution_target.unwrap_or(""),
      content="wiki-main",
    )
    inspect(
      proposal.steps[0].metadata
      .stringify()
      .contains("\"bookapi_task_id\":\"task-1\""),
      content="true",
    )
    inspect(
      proposal.steps[0].metadata.stringify().contains("\"timeout_ms\":600000"),
      content="true",
    )
    inspect(
      proposal.steps[0].metadata
      .stringify()
      .contains("\"max_total_tokens\":24000"),
      content="true",
    )
    inspect(
      proposal.profile_metadata.stringify().contains("\"task_count\":2"),
      content="true",
    )
  })
}

///|
test "provider task child proposal skips deferred planning task when executable tasks exist" {
  let batch = ProviderTaskBatch::{
    goal_id: "goal-1",
    goal: "Bootstrap ingest",
    summary: "Mixed execution and planning batch",
    tasks: [
      ProviderTaskSpec::{
        id: "bootstrap_gather",
        title: "Gather bootstrap materials",
        kind: "bootstrap_gather",
        prompt: "Gather",
        priority: 100,
        requires_review: true,
        target_pages: ["raw/bootstrap/demo.md"],
      },
      ProviderTaskSpec::{
        id: "source_materialize",
        title: "Materialize durable source pages",
        kind: "source_materialize",
        prompt: "Materialize",
        priority: 95,
        requires_review: true,
        target_pages: ["wiki/sources/demo.md"],
      },
      ProviderTaskSpec::{
        id: "planning",
        title: "Refresh local planning surfaces",
        kind: "planning",
        prompt: "Plan next local revisions",
        priority: 90,
        requires_review: true,
        target_pages: ["wiki/synthesis/maintenance-plan.md"],
      },
    ],
  }
  let config = SubjobStepConfig::new(
    request_text="unused",
    child_profile=None,
    include_parent_outputs=true,
    max_depth=4,
    execution_mode=Some("provider"),
    execution_target=Some("wiki-main"),
  )
  let proposal = provider_task_child_proposal(
    "Bootstrap ingest", batch, config, 1000,
  )
  inspect(proposal.steps.length(), content="2")
  inspect(proposal.steps[0].id, content="bootstrap_gather")
  inspect(proposal.steps[1].id, content="source_materialize")
  inspect(
    proposal.profile_metadata.stringify().contains("\"task_count\":2"),
    content="true",
  )
  inspect(
    proposal.profile_metadata.stringify().contains("\"deferred_task_count\":1"),
    content="true",
  )
}

///|
async test "provider task analysis runner hydrates context and persists structured result" {
  @fsx.with_temporary_directory("job-book-harness-runner-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let script_path = @pathx.join(dir, "provider_task.sh")
    let state_path = @pathx.join(dir, "persisted-path.txt")
    @fsx.make_directory(workspace, recursive=true, exists_ok=true)
    write_provider_task_fixture(workspace, script_path, state_path)
    @fsx.make_directory(
      @pathx.join(workspace, "book-space") |> @pathx.join("wiki"),
      recursive=true,
      exists_ok=true,
    )
    @fsx.write_to_file(
      @pathx.join(workspace, "book-space")
      |> @pathx.join("wiki")
      |> @pathx.join("entity.md"),
      "# entity\n",
    )

    let request = AnalysisRequest::{
      prompt: "Please update the wiki from the current evidence.",
      system_prompt: "Base system prompt.",
      source_prompt: "Update the knowledge base",
      step_metadata: {
        "extension_goal": "Update the knowledge base",
        "extension_goal_id": "goal-1",
        "extension_task_id": "task-1",
      },
      cwd: workspace,
      home: None,
      model_name: "codex/gpt-5.4",
      enable_tools: true,
      web_search: true,
      tool_contract: AnalysisToolContract::new(),
      preferred_skills: ["wiki-maintainer"],
      job_id: "job-1",
      run_id: "run-1",
      step_id: "step-1",
      execution_isolation: None,
      role_runtime_contract: Some(
        RoleRuntimeContract::new(role_id="wiki_worker"),
      ),
      execution_mode: Some("provider"),
      execution_target: Some("wiki-main"),
    }
    let captured_prompt : Ref[String] = { val: "" }
    let captured_system_prompt : Ref[String] = { val: "" }
    let captured_enable_tools : Ref[Bool] = { val: true }
    let captured_web_search : Ref[Bool] = { val: false }
    let captured_todo_enabled : Ref[Bool] = { val: true }
    let execution = match
      run_provider_task_analysis_runner(request, fn(inner_request) {
        captured_prompt.val = inner_request.prompt
        captured_system_prompt.val = inner_request.system_prompt
        captured_enable_tools.val = inner_request.enable_tools
        captured_web_search.val = inner_request.web_search
        captured_todo_enabled.val = inner_request.tool_contract.todo
        Ok(AnalysisExecution::{
          model_name: inner_request.model_name,
          content: (
            #|{
            #|  "task_id": "task-1",
            #|  "summary": "Updated the wiki and captured the contradiction.",
            #|  "artifacts": ["wiki/entity.md"],
            #|  "memory_candidates": [
            #|    {
            #|      "kind": "fact",
            #|      "title": "Entity contradiction",
            #|      "detail": "Two sources disagree on the reported valuation.",
            #|      "durable": true,
            #|      "target_page": "wiki/entity.md"
            #|    }
            #|  ],
            #|  "requires_review": true,
            #|  "notify_town": false
            #|}
          ),
          conversation_id: Some("conv-provider-1"),
          usage: None,
          metadata: {
            "job_id": inner_request.job_id,
            "run_id": inner_request.run_id,
            "step_id": inner_request.step_id,
          },
        })
      }) {
      Ok(execution) => execution
      Err(error) => fail(error)
    }

    inspect(captured_prompt.val.contains("Relevant Pages:"), content="true")
    inspect(captured_prompt.val.contains("wiki/entity.md"), content="true")
    inspect(
      captured_system_prompt.val.contains(
        "loaded `provider-task-execution` skill defines the execution method.",
      ),
      content="true",
    )
    inspect(
      captured_prompt.val.contains("provider-task-execution"),
      content="true",
    )
    inspect(
      captured_system_prompt.val.contains("Base system prompt."),
      content="true",
    )
    inspect(
      captured_system_prompt.val.contains(
        "Read concrete candidate files directly before using broad repo-wide search tools.",
      ),
      content="true",
    )
    inspect(captured_system_prompt.val.contains(".mooncakes"), content="true")
    inspect(
      captured_system_prompt.val.contains("raw/bootstrap/*"),
      content="true",
    )
    inspect(captured_enable_tools.val, content="true")
    inspect(captured_web_search.val, content="true")
    inspect(captured_todo_enabled.val, content="false")
    inspect(
      execution.content.contains("# Extension Task Result"),
      content="true",
    )
    inspect(execution.content.contains("evidence-1"), content="true")
    inspect(
      execution.metadata.stringify().contains("\"execution_mode\":\"provider\""),
      content="true",
    )
    inspect(
      execution.metadata
      .stringify()
      .contains("\"extension_task_id\":\"task-1\""),
      content="true",
    )
    let persisted_path = @fsx.read_file(state_path)
    let persisted_step_key = safe_step_file_segment("step-1")
    inspect(
      persisted_path.contains(
        ".moonclaw-provider-result-run-1-\{persisted_step_key}.json",
      ),
      content="true",
    )
    let persisted_payload = @fsx.read_file(persisted_path.trim())
    inspect(
      persisted_payload.contains("\"summary\": \"Updated the wiki"),
      content="true",
    )
  })
}

///|
async test "provider task result persistence falls back to provider workspace when request cwd is gone" {
  @fsx.with_temporary_directory("job-book-harness-persist-fallback-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let script_path = @pathx.join(dir, "provider_task.sh")
    let state_path = @pathx.join(dir, "persisted-path.txt")
    write_provider_task_fixture(workspace, script_path, state_path)

    let command = match
      resolve_provider_task_command(workspace, None, Some("wiki-main")) {
      Ok(command) => command
      Err(error) => fail(error)
    }
    let request = AnalysisRequest::{
      prompt: "Please update the wiki from the current evidence.",
      system_prompt: "Base system prompt.",
      source_prompt: "Update the knowledge base",
      step_metadata: {
        "extension_goal": "Update the knowledge base",
        "extension_goal_id": "goal-1",
        "extension_task_id": "task-1",
      },
      cwd: @pathx.join(workspace, "missing-worktree"),
      home: None,
      model_name: "codex/gpt-5.4",
      enable_tools: true,
      web_search: true,
      tool_contract: AnalysisToolContract::new(),
      preferred_skills: ["wiki-maintainer"],
      job_id: "job-1",
      run_id: "run-1",
      step_id: "step-1",
      execution_isolation: None,
      role_runtime_contract: Some(
        RoleRuntimeContract::new(role_id="wiki_worker"),
      ),
      execution_mode: Some("provider"),
      execution_target: Some("wiki-main"),
    }
    let outcome = match
      persist_provider_task_result(
        command,
        request,
        ProviderTaskSpec::{
          id: "task-1",
          title: "Extract durable updates",
          kind: "wiki.update",
          prompt: "Read the source and update the durable wiki state.",
          priority: 90,
          requires_review: true,
          target_pages: ["wiki/entity.md", "wiki/index.md"],
        },
        ProviderTaskResult::{
          task_id: "task-1",
          summary: "Updated the wiki from durable evidence.",
          artifacts: ["wiki/entity.md"],
          memory_candidates: [],
          requires_review: true,
          notify_town: false,
        },
      ) {
      Ok(outcome) => outcome
      Err(error) => fail(error)
    }

    inspect(outcome.evidence_id, content="evidence-1")
    let persisted_path = @fsx.read_file(state_path).trim().to_string()
    inspect(
      persisted_path.contains("book-space/.moonclaw/provider-task/"),
      content="true",
    )
    inspect(
      @fsx.read_file(persisted_path).contains(
        "\"summary\": \"Updated the wiki from durable evidence.\"",
      ),
      content="true",
    )
  })
}

///|
test "parse_provider_task_result accepts fenced or prefixed JSON object output" {
  let content =
    #|Here is the structured result.
    #|```json
    #|{
    #|  "task_id": "task-1",
    #|  "summary": "Updated the wiki and captured the contradiction.",
    #|  "artifacts": ["wiki/entity.md"],
    #|  "memory_candidates": [],
    #|  "requires_review": true,
    #|  "notify_town": false
    #|}
    #|```
  let result = match parse_provider_task_result(content) {
    Ok(result) => result
    Err(error) => fail(error)
  }
  inspect(result.task_id, content="task-1")
  inspect(result.requires_review, content="true")
}

///|
test "parse_provider_task_persist_outcome_json accepts prefixed stdout" {
  let outcome = match
    parse_provider_task_persist_outcome_json(
      "moonbook wiki book persist completed\n{\"log_path\":\"wiki/log.md\",\"updated_pages\":[\"wiki/index.md\"],\"review_queued\":true,\"notify_town\":false,\"evidence_id\":\"evidence-1\"}",
      "persist",
    ) {
    Ok(outcome) => outcome
    Err(error) => fail(error)
  }
  inspect(outcome.log_path, content="wiki/log.md")
  inspect(outcome.review_queued, content="true")
}

///|
async test "provider task analysis runner converts planner-shaped output into adaptive split" {
  @fsx.with_temporary_directory("job-book-harness-repair-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let script_path = @pathx.join(dir, "provider_task.sh")
    let state_path = @pathx.join(dir, "persisted-path.txt")
    @fsx.make_directory(workspace, recursive=true, exists_ok=true)
    write_provider_task_fixture(workspace, script_path, state_path)
    @fsx.make_directory(
      @pathx.join(workspace, "book-space") |> @pathx.join("wiki"),
      recursive=true,
      exists_ok=true,
    )
    @fsx.write_to_file(
      @pathx.join(workspace, "book-space")
      |> @pathx.join("wiki")
      |> @pathx.join("entity.md"),
      "# entity\n",
    )

    let request = AnalysisRequest::{
      prompt: "Please update the wiki from the current evidence.",
      system_prompt: "Base system prompt.",
      source_prompt: "Update the knowledge base",
      step_metadata: {
        "extension_goal": "Update the knowledge base",
        "extension_goal_id": "goal-1",
        "extension_task_id": "task-1",
      },
      cwd: workspace,
      home: None,
      model_name: "codex/gpt-5.4",
      enable_tools: true,
      web_search: true,
      tool_contract: AnalysisToolContract::new(),
      preferred_skills: ["wiki-maintainer"],
      job_id: "job-1",
      run_id: "run-1",
      step_id: "step-1",
      execution_isolation: None,
      role_runtime_contract: Some(
        RoleRuntimeContract::new(role_id="wiki_worker"),
      ),
      execution_mode: Some("provider"),
      execution_target: Some("wiki-main"),
    }
    let call_count : Ref[Int] = { val: 0 }
    let execution = match
      run_provider_task_analysis_runner(request, fn(inner_request) {
        call_count.val = call_count.val + 1
        Ok(AnalysisExecution::{
          model_name: inner_request.model_name,
          content: "{\"plan\":[{\"step\":1,\"title\":\"Inspect sources\",\"prompt\":\"Inspect the relevant source materials.\"},{\"step\":2,\"title\":\"Materialize durable updates\",\"prompt\":\"Write the durable wiki pages from the inspected evidence.\"}]}",
          conversation_id: Some("conv-provider-plan"),
          usage: None,
          metadata: {},
        })
      }) {
      Ok(execution) => execution
      Err(error) => fail(error)
    }

    inspect(call_count.val, content="1")
    let envelope = match parse_adaptive_analysis_envelope(execution.content) {
      Some(envelope) => envelope
      None => fail("expected adaptive split envelope: \{execution.content}")
    }
    inspect(envelope.verdict, content="needs_subplan")
    inspect(adaptive_substeps(envelope).length(), content="2")
    inspect(
      execution.metadata
      .stringify()
      .contains("\"extension_task_id\":\"task-1\""),
      content="true",
    )
  })
}

///|
async test "provider task analysis runner rejects over-broad task without executable substeps" {
  @fsx.with_temporary_directory("job-book-harness-guardrail-reject-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let script_path = @pathx.join(dir, "provider_task.sh")
    let state_path = @pathx.join(dir, "persisted-path.txt")
    @fsx.make_directory(workspace, recursive=true, exists_ok=true)
    write_provider_task_fixture(workspace, script_path, state_path)

    let request = AnalysisRequest::{
      prompt: "Please update the wiki from the current evidence.",
      system_prompt: "Base system prompt.",
      source_prompt: "Update the knowledge base",
      step_metadata: {
        "extension_goal": "Update the knowledge base",
        "extension_goal_id": "goal-1",
        "extension_task_id": "task-2",
      },
      cwd: workspace,
      home: None,
      model_name: "codex/gpt-5.4",
      enable_tools: true,
      web_search: true,
      tool_contract: AnalysisToolContract::new(),
      preferred_skills: ["wiki-maintainer"],
      job_id: "job-1",
      run_id: "run-1",
      step_id: "step-1",
      execution_isolation: None,
      role_runtime_contract: Some(
        RoleRuntimeContract::new(role_id="wiki_worker"),
      ),
      execution_mode: Some("provider"),
      execution_target: Some("wiki-main"),
    }
    let error = match
      run_provider_task_analysis_runner(request, fn(inner_request) {
        Ok(AnalysisExecution::{
          model_name: inner_request.model_name,
          content: "{\"verdict\":\"needs_subplan\",\"summary\":\"The task is too broad and should be decomposed before useful execution.\"}",
          conversation_id: Some("conv-provider-broad"),
          usage: None,
          metadata: {},
        })
      }) {
      Ok(_) => fail("expected breadth guardrail rejection")
      Err(error) => error
    }

    inspect(error.contains("too broad to execute directly"), content="true")
    inspect(error.contains("no executable substeps"), content="true")
  })
}

///|
async test "provider task analysis runner derives deterministic followup substeps from provider task batch" {
  @fsx.with_temporary_directory("job-book-harness-followup-substeps-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let script_path = @pathx.join(dir, "provider_task.sh")
    let state_path = @pathx.join(dir, "persisted-path.txt")
    write_provider_task_fixture(workspace, script_path, state_path)

    let request = AnalysisRequest::{
      prompt: "Please update the wiki from the current evidence.",
      system_prompt: "Base system prompt.",
      source_prompt: "Update the knowledge base",
      step_metadata: {
        "extension_goal": "Update the knowledge base",
        "extension_goal_id": "goal-1",
        "extension_task_id": "task-1",
      },
      cwd: workspace,
      home: None,
      model_name: "codex/gpt-5.4",
      enable_tools: true,
      web_search: true,
      tool_contract: AnalysisToolContract::new(),
      preferred_skills: ["wiki-maintainer"],
      job_id: "job-1",
      run_id: "run-1",
      step_id: "step-1",
      execution_isolation: None,
      role_runtime_contract: Some(
        RoleRuntimeContract::new(role_id="wiki_worker"),
      ),
      execution_mode: Some("provider"),
      execution_target: Some("wiki-main"),
    }
    let execution = match
      run_provider_task_analysis_runner(request, fn(inner_request) {
        Ok(AnalysisExecution::{
          model_name: inner_request.model_name,
          content: "{\"verdict\":\"needs_subplan\",\"summary\":\"Completed bootstrap_gather and prepared durable targets for source materialization.\"}",
          conversation_id: Some("conv-provider-bootstrap"),
          usage: None,
          metadata: {},
        })
      }) {
      Ok(execution) => execution
      Err(error) => fail(error)
    }

    let envelope = match parse_adaptive_analysis_envelope(execution.content) {
      Some(envelope) => envelope
      None => fail("expected adaptive split envelope: \{execution.content}")
    }
    let substeps = adaptive_substeps(envelope)
    inspect(envelope.verdict, content="needs_subplan")
    inspect(substeps.length(), content="1")
    inspect(substeps[0].title, content="Queue follow-up review")
    inspect(substeps[0].prompt.contains("task_id: task-2"), content="true")
    inspect(substeps[0].prompt.contains("wiki/review.md"), content="true")
  })
}

///|
async test "provider task target artifacts resolve durable pages from provider workspace root" {
  @fsx.with_temporary_directory("job-book-harness-target-artifacts-XXXXXX", async fn(
    dir,
  ) {
    let workspace_root = @pathx.join(dir, "book-space")
    @fsx.make_directory(
      @pathx.join(workspace_root, "wiki/entities"),
      recursive=true,
      exists_ok=true,
    )
    @fsx.make_directory(
      @pathx.join(workspace_root, "wiki/synthesis"),
      recursive=true,
      exists_ok=true,
    )
    @fsx.write_to_file(
      @pathx.join(workspace_root, "wiki/entities/moonclaw.md"),
      "# MoonClaw\n",
    )
    @fsx.write_to_file(
      @pathx.join(workspace_root, "wiki/synthesis/map.md"),
      "# Map\n",
    )

    let artifacts = provider_task_target_artifacts(workspace_root, ProviderTaskSpec::{
      id: "task-1",
      title: "Materialize durable updates",
      kind: "source_materialize",
      prompt: "Materialize",
      priority: 90,
      requires_review: true,
      target_pages: ["wiki/entities/moonclaw.md", "wiki/synthesis/map.md"],
    })

    inspect(artifacts.length(), content="2")
    inspect(artifacts.contains("wiki/entities/moonclaw.md"), content="true")
    inspect(artifacts.contains("wiki/synthesis/map.md"), content="true")
  })
}

///|
async test "provider task subplan finalizer persists durable artifacts back through provider contract" {
  @fsx.with_temporary_directory("job-book-harness-subplan-finalize-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let script_path = @pathx.join(dir, "provider_task.sh")
    let state_path = @pathx.join(dir, "persisted-path.txt")
    let provider_root = @pathx.join(workspace, "book-space")
    @fsx.make_directory(
      @pathx.join(provider_root, "wiki"),
      recursive=true,
      exists_ok=true,
    )
    @fsx.make_directory(
      @pathx.join(provider_root, "raw/bootstrap"),
      recursive=true,
      exists_ok=true,
    )
    write_provider_task_fixture(workspace, script_path, state_path)
    @fsx.write_to_file(@pathx.join(provider_root, "wiki/index.md"), "# Index\n")
    @fsx.make_directory(
      @pathx.join(provider_root, "wiki/sources"),
      recursive=true,
      exists_ok=true,
    )
    @fsx.write_to_file(
      @pathx.join(provider_root, "wiki/sources/demo.md"),
      "# Source\n",
    )
    @fsx.write_to_file(
      @pathx.join(provider_root, "raw/bootstrap/demo.md"),
      "# Bootstrap\n",
    )

    let request = AnalysisRequest::{
      prompt: "Please update the wiki from the current evidence.",
      system_prompt: "Base system prompt.",
      source_prompt: "Update the knowledge base",
      step_metadata: {
        "extension_goal": "Update the knowledge base",
        "extension_goal_id": "goal-1",
        "extension_task_id": "task-1",
      },
      cwd: workspace,
      home: None,
      model_name: "codex/gpt-5.4",
      enable_tools: true,
      web_search: true,
      tool_contract: AnalysisToolContract::new(),
      preferred_skills: ["wiki-maintainer"],
      job_id: "job-1",
      run_id: "run-1",
      step_id: "step-1",
      execution_isolation: None,
      role_runtime_contract: Some(
        RoleRuntimeContract::new(role_id="wiki_worker"),
      ),
      execution_mode: Some("provider"),
      execution_target: Some("wiki-main"),
    }
    let execution = AnalysisExecution::{
      model_name: request.model_name,
      content: "Child subplan completed durable materialization.",
      conversation_id: Some("conv-provider-subplan-finalized"),
      usage: None,
      metadata: {
        "job_id": request.job_id,
        "run_id": request.run_id,
        "step_id": request.step_id,
        "extension_guardrail_summary": "Materialized durable wiki outputs after bootstrap gather.",
      },
    }
    let child_outputs = {
      "step_1": {
        "content": "Wrote `raw/bootstrap/demo.md` and `wiki/sources/demo.md` during child materialization.",
      },
    }

    let finalized = match
      finalize_provider_task_subplan_execution(
        request,
        execution,
        child_outputs.to_json(),
      ) {
      Some(Ok(finalized)) => finalized
      Some(Err(error)) => fail(error)
      None => fail("expected provider subplan finalizer to persist result")
    }

    inspect(
      finalized.content.contains("# Extension Task Result"),
      content="true",
    )
    inspect(
      finalized.metadata.stringify().contains("\"extension_persist_outcome\""),
      content="true",
    )
    let persisted_path = @fsx.read_file(state_path).trim().to_string()
    let persisted_payload = @fsx.read_file(persisted_path)
    inspect(
      persisted_payload.contains("\"task_id\": \"task-1\""),
      content="true",
    )
    inspect(
      persisted_payload.contains(
        "\"summary\": \"Materialized durable wiki outputs after bootstrap gather.\"",
      ),
      content="true",
    )
    inspect(
      persisted_payload.contains("\"wiki/sources/demo.md\""),
      content="true",
    )
    inspect(
      persisted_payload.contains("\"raw/bootstrap/demo.md\""),
      content="true",
    )
  })
}

///|
async test "provider task repair loads repo provider-task-repair skill" {
  @fsx.with_temporary_directory("job-book-harness-repair-skill-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let script_path = @pathx.join(dir, "provider_task.sh")
    let state_path = @pathx.join(dir, "persisted-path.txt")
    let skill_dir = workspace
      |> @pathx.join("skills")
      |> @pathx.join("provider-task-repair")
    @fsx.make_directory(workspace, recursive=true, exists_ok=true)
    @fsx.make_directory(skill_dir, recursive=true, exists_ok=true)
    @fsx.write_to_file(
      skill_dir |> @pathx.join("SKILL.md"),
      [
        "---", "name: provider-task-repair", "description: test skill", "---", "",
        "Include the exact phrase PROVIDER_REPAIR_SKILL_MARKER.",
      ].join("\n"),
    )
    write_provider_task_fixture(workspace, script_path, state_path)

    let request = AnalysisRequest::{
      prompt: "Please update the wiki from the current evidence.",
      system_prompt: "Base system prompt.",
      source_prompt: "Update the knowledge base",
      step_metadata: {
        "extension_goal": "Update the knowledge base",
        "extension_goal_id": "goal-1",
        "extension_task_id": "task-1",
      },
      cwd: workspace,
      home: None,
      model_name: "codex/gpt-5.4",
      enable_tools: true,
      web_search: true,
      tool_contract: AnalysisToolContract::new(),
      preferred_skills: ["wiki-maintainer"],
      job_id: "job-1",
      run_id: "run-1",
      step_id: "step-1",
      execution_isolation: None,
      role_runtime_contract: Some(
        RoleRuntimeContract::new(role_id="wiki_worker"),
      ),
      execution_mode: Some("provider"),
      execution_target: Some("wiki-main"),
    }
    let call_count : Ref[Int] = { val: 0 }
    let repair_prompt : Ref[String] = { val: "" }
    ignore(
      match
        run_provider_task_analysis_runner(request, fn(inner_request) {
          call_count.val = call_count.val + 1
          if call_count.val == 1 {
            Ok(AnalysisExecution::{
              model_name: inner_request.model_name,
              content: "{\"plan\":[{\"step\":1,\"title\":\"Inspect sources\"}]}",
              conversation_id: Some("conv-provider-plan"),
              usage: None,
              metadata: {},
            })
          } else {
            repair_prompt.val = inner_request.prompt
            Ok(AnalysisExecution::{
              model_name: inner_request.model_name,
              content: (
                #|{
                #|  "task_id": "task-1",
                #|  "summary": "Updated the wiki from the source evidence.",
                #|  "artifacts": ["wiki/entity.md"],
                #|  "memory_candidates": [],
                #|  "requires_review": false,
                #|  "notify_town": false
                #|}
              ),
              conversation_id: Some("conv-provider-repair"),
              usage: None,
              metadata: {},
            })
          }
        }) {
        Ok(execution) => execution
        Err(error) => fail(error)
      },
    )
    inspect(call_count.val, content="1")
    inspect(
      repair_prompt.val.contains("PROVIDER_REPAIR_SKILL_MARKER"),
      content="false",
    )
  })
}

///|
async test "provider task analysis runner normalizes repaired json missing summary" {
  @fsx.with_temporary_directory("job-book-harness-normalize-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let script_path = @pathx.join(dir, "provider_task.sh")
    let state_path = @pathx.join(dir, "persisted-path.txt")
    @fsx.make_directory(workspace, recursive=true, exists_ok=true)
    write_provider_task_fixture(workspace, script_path, state_path)

    let request = AnalysisRequest::{
      prompt: "Please update the wiki from the current evidence.",
      system_prompt: "Base system prompt.",
      source_prompt: "Update the knowledge base",
      step_metadata: {
        "extension_goal": "Update the knowledge base",
        "extension_goal_id": "goal-1",
        "extension_task_id": "task-1",
      },
      cwd: workspace,
      home: None,
      model_name: "codex/gpt-5.4",
      enable_tools: true,
      web_search: true,
      tool_contract: AnalysisToolContract::new(),
      preferred_skills: ["wiki-maintainer"],
      job_id: "job-1",
      run_id: "run-1",
      step_id: "step-1",
      execution_isolation: None,
      role_runtime_contract: Some(
        RoleRuntimeContract::new(role_id="wiki_worker"),
      ),
      execution_mode: Some("provider"),
      execution_target: Some("wiki-main"),
    }
    let call_count : Ref[Int] = { val: 0 }
    let execution = match
      run_provider_task_analysis_runner(request, fn(inner_request) {
        call_count.val = call_count.val + 1
        if call_count.val == 1 {
          Ok(AnalysisExecution::{
            model_name: inner_request.model_name,
            content: "I will inspect the wiki first.\nPlan:\n1. Inspect sources\n2. Update pages",
            conversation_id: Some("conv-provider-plan-prose"),
            usage: None,
            metadata: {},
          })
        } else {
          Ok(AnalysisExecution::{
            model_name: inner_request.model_name,
            content: "{\"artifacts\":[\"wiki/entity.md\"],\"requires_review\":false,\"notify_town\":false}",
            conversation_id: Some("conv-provider-normalize"),
            usage: None,
            metadata: {},
          })
        }
      }) {
      Ok(execution) => execution
      Err(error) => fail(error)
    }

    inspect(call_count.val, content="2")
    inspect(
      execution.metadata
      .stringify()
      .contains("\"extension_task_id\":\"task-1\""),
      content="true",
    )
    inspect(
      execution.content.contains("# Extension Task Result"),
      content="true",
    )
  })
}

///|
async test "provider task analysis runner persists raw response on parse failure" {
  @fsx.with_temporary_directory("job-book-harness-failure-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let script_path = @pathx.join(dir, "provider_task.sh")
    let state_path = @pathx.join(dir, "persisted-path.txt")
    @fsx.make_directory(workspace, recursive=true, exists_ok=true)
    write_provider_task_fixture(workspace, script_path, state_path)

    let request = AnalysisRequest::{
      prompt: "Please update the wiki from the current evidence.",
      system_prompt: "Base system prompt.",
      source_prompt: "Update the knowledge base",
      step_metadata: {
        "extension_goal": "Update the knowledge base",
        "extension_goal_id": "goal-1",
        "extension_task_id": "task-1",
      },
      cwd: workspace,
      home: None,
      model_name: "codex/gpt-5.4",
      enable_tools: true,
      web_search: true,
      tool_contract: AnalysisToolContract::new(),
      preferred_skills: ["wiki-maintainer"],
      job_id: "job-1",
      run_id: "run-1",
      step_id: "step-1",
      execution_isolation: None,
      role_runtime_contract: Some(
        RoleRuntimeContract::new(role_id="wiki_worker"),
      ),
      execution_mode: Some("provider"),
      execution_target: Some("wiki-main"),
    }
    let error = match
      run_provider_task_analysis_runner(request, fn(inner_request) {
        Ok(AnalysisExecution::{
          model_name: inner_request.model_name,
          content: "not valid provider json",
          conversation_id: Some("conv-provider-failure"),
          usage: None,
          metadata: {
            "job_id": inner_request.job_id,
            "run_id": inner_request.run_id,
            "step_id": inner_request.step_id,
          },
        })
      }) {
      Ok(_) => fail("expected provider parse failure")
      Err(error) => error
    }

    inspect(
      error.contains("Provider task analysis must return a JSON object"),
      content="true",
    )
    let step_key = safe_step_file_segment("step-1")
    let debug_file = ".moonclaw-provider-failure-run-1-\{step_key}.json"
    inspect(error.contains(debug_file), content="true")
    let debug_path = match
      provider_task_failure_debug_path(
        request,
        @pathx.join(workspace, "book-space"),
      ) {
      Ok(path) => path
      Err(path_error) => fail(path_error)
    }
    inspect(@fsx.exists(debug_path), content="true")
    let debug_payload = @fsx.read_file(debug_path)
    inspect(
      debug_payload.contains("\"raw_content\": \"not valid provider json\""),
      content="true",
    )
  })
}

///|
async test "provider task analysis runner converts empty generic completion into blocker" {
  @fsx.with_temporary_directory("job-book-harness-empty-success-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let script_path = @pathx.join(dir, "provider_task.sh")
    let state_path = @pathx.join(dir, "persisted-path.txt")
    @fsx.make_directory(workspace, recursive=true, exists_ok=true)
    write_provider_task_fixture(workspace, script_path, state_path)

    let request = AnalysisRequest::{
      prompt: "Please update the wiki from the current evidence.",
      system_prompt: "Base system prompt.",
      source_prompt: "Update the knowledge base",
      step_metadata: {
        "extension_goal": "Update the knowledge base",
        "extension_goal_id": "goal-1",
        "extension_task_id": "task-1",
      },
      cwd: workspace,
      home: None,
      model_name: "codex/gpt-5.4",
      enable_tools: true,
      web_search: true,
      tool_contract: AnalysisToolContract::new(),
      preferred_skills: ["wiki-maintainer"],
      job_id: "job-1",
      run_id: "run-1",
      step_id: "step-1",
      execution_isolation: None,
      role_runtime_contract: Some(
        RoleRuntimeContract::new(role_id="wiki_worker"),
      ),
      execution_mode: Some("provider"),
      execution_target: Some("wiki-main"),
    }
    let execution = match
      run_provider_task_analysis_runner(request, fn(inner_request) {
        Ok(AnalysisExecution::{
          model_name: inner_request.model_name,
          content: (
            #|{
            #|  "task_id": "task-1",
            #|  "summary": "Completed provider task Bootstrap ingest and population.",
            #|  "artifacts": [],
            #|  "memory_candidates": [],
            #|  "requires_review": true,
            #|  "notify_town": false
            #|}
          ),
          conversation_id: Some("conv-provider-empty-success"),
          usage: None,
          metadata: {},
        })
      }) {
      Ok(execution) => execution
      Err(error) => fail(error)
    }

    inspect(execution.content.contains("Blocked provider task"), content="true")
    let persisted_path = @fsx.read_file(state_path).trim().to_string()
    let persisted_payload = @fsx.read_file(persisted_path)
    inspect(
      persisted_payload.contains(
        "\"summary\": \"Blocked provider task Extract durable updates:",
      ),
      content="true",
    )
    inspect(persisted_payload.contains("\"kind\": \"blocker\""), content="true")
    inspect(
      persisted_payload.contains("\"kind\": \"next_step\""),
      content="true",
    )
    inspect(persisted_payload.contains("\"durable\": false"), content="true")
  })
}

///|
async test "provider task analysis runner aligns task id and filters junk artifacts" {
  @fsx.with_temporary_directory("job-book-harness-artifact-align-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let script_path = @pathx.join(dir, "provider_task.sh")
    let state_path = @pathx.join(dir, "persisted-path.txt")
    @fsx.make_directory(workspace, recursive=true, exists_ok=true)
    write_provider_task_fixture(workspace, script_path, state_path)
    let provider_root = @pathx.join(workspace, "book-space")
    @fsx.make_directory(
      @pathx.join(provider_root, "wiki"),
      recursive=true,
      exists_ok=true,
    )
    @fsx.make_directory(
      @pathx.join(provider_root, "raw") |> @pathx.join("bootstrap"),
      recursive=true,
      exists_ok=true,
    )
    @fsx.write_to_file(
      @pathx.join(provider_root, "wiki") |> @pathx.join("entity.md"),
      "# entity\n",
    )
    @fsx.write_to_file(
      @pathx.join(provider_root, "raw")
      |> @pathx.join("bootstrap")
      |> @pathx.join("packet.md"),
      "# packet\n",
    )

    let request = AnalysisRequest::{
      prompt: "Please update the wiki from the current evidence.",
      system_prompt: "Base system prompt.",
      source_prompt: "Update the knowledge base",
      step_metadata: {
        "extension_goal": "Update the knowledge base",
        "extension_goal_id": "goal-1",
        "extension_task_id": "task-1",
      },
      cwd: workspace,
      home: None,
      model_name: "codex/gpt-5.4",
      enable_tools: true,
      web_search: true,
      tool_contract: AnalysisToolContract::new(),
      preferred_skills: ["wiki-maintainer"],
      job_id: "job-1",
      run_id: "run-1",
      step_id: "step-1",
      execution_isolation: None,
      role_runtime_contract: Some(
        RoleRuntimeContract::new(role_id="wiki_worker"),
      ),
      execution_mode: Some("provider"),
      execution_target: Some("wiki-main"),
    }
    let execution = match
      run_provider_task_analysis_runner(request, fn(inner_request) {
        Ok(AnalysisExecution::{
          model_name: inner_request.model_name,
          content: (
            #|{
            #|  "task_id": "wrong-task",
            #|  "summary": "Updated the wiki and captured the contradiction.",
            #|  "artifacts": [
            #|    "gpt-5.4",
            #|    "skills/wiki-ingest/SKILL.md",
            #|    "moon.mod.json",
            #|    "wiki/entity.md",
            #|    "raw/bootstrap/packet.md"
            #|  ],
            #|  "memory_candidates": [],
            #|  "requires_review": false,
            #|  "notify_town": false
            #|}
          ),
          conversation_id: Some("conv-provider-artifacts"),
          usage: None,
          metadata: {},
        })
      }) {
      Ok(execution) => execution
      Err(error) => fail(error)
    }

    inspect(execution.content.contains("Updated the wiki"), content="true")
    let persisted_path = @fsx.read_file(state_path).trim().to_string()
    let persisted_payload = @fsx.read_file(persisted_path)
    inspect(
      persisted_payload.contains("\"task_id\": \"task-1\""),
      content="true",
    )
    inspect(persisted_payload.contains("\"wiki/entity.md\""), content="true")
    inspect(
      persisted_payload.contains("\"raw/bootstrap/packet.md\""),
      content="true",
    )
    inspect(persisted_payload.contains("\"gpt-5.4\""), content="false")
    inspect(
      persisted_payload.contains("\"skills/wiki-ingest/SKILL.md\""),
      content="false",
    )
    inspect(persisted_payload.contains("\"moon.mod.json\""), content="false")
  })
}

///|
async test "provider task batch resolves a single registered provider when target is omitted" {
  @fsx.with_temporary_directory("job-book-harness-default-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let script_path = @pathx.join(dir, "provider_task.sh")
    let state_path = @pathx.join(dir, "persisted-path.txt")
    @fsx.make_directory(workspace, recursive=true, exists_ok=true)
    write_provider_task_fixture(workspace, script_path, state_path)

    let (command, batch) = match
      load_provider_task_task_batch(
        workspace,
        None,
        None,
        "Update the knowledge base",
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }

    inspect(command.provider.name, content="wiki-main")
    inspect(batch.tasks.length().to_string(), content="2")
  })
}

///|
async test "provider task analysis runner resolves a single registered provider when target is omitted" {
  @fsx.with_temporary_directory("job-book-harness-default-runner-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let script_path = @pathx.join(dir, "provider_task.sh")
    let state_path = @pathx.join(dir, "persisted-path.txt")
    @fsx.make_directory(workspace, recursive=true, exists_ok=true)
    write_provider_task_fixture(workspace, script_path, state_path)

    let request = AnalysisRequest::{
      prompt: "Please update the wiki from the current evidence.",
      system_prompt: "Base system prompt.",
      source_prompt: "Update the knowledge base",
      step_metadata: {
        "extension_goal": "Update the knowledge base",
        "extension_goal_id": "goal-1",
        "extension_task_id": "task-1",
      },
      cwd: workspace,
      home: None,
      model_name: "codex/gpt-5.4",
      enable_tools: true,
      web_search: true,
      tool_contract: AnalysisToolContract::new(),
      preferred_skills: ["wiki-maintainer"],
      job_id: "job-1",
      run_id: "run-1",
      step_id: "step-1",
      execution_isolation: None,
      role_runtime_contract: Some(
        RoleRuntimeContract::new(role_id="wiki_worker"),
      ),
      execution_mode: Some("provider"),
      execution_target: None,
    }
    let execution = match
      run_provider_task_analysis_runner(request, fn(inner_request) {
        Ok(AnalysisExecution::{
          model_name: inner_request.model_name,
          content: (
            #|{
            #|  "task_id": "task-1",
            #|  "summary": "Updated the wiki and captured the contradiction.",
            #|  "artifacts": ["wiki/entity.md"],
            #|  "memory_candidates": [],
            #|  "requires_review": false,
            #|  "notify_town": false
            #|}
          ),
          conversation_id: Some("conv-provider-implicit"),
          usage: None,
          metadata: {},
        })
      }) {
      Ok(execution) => execution
      Err(error) => fail(error)
    }

    inspect(
      execution.metadata
      .stringify()
      .contains("\"execution_target\":\"wiki-main\""),
      content="true",
    )
  })
}

///|
async test "provider task resolves workspace-affine provider when multiple targets are registered" {
  @fsx.with_temporary_directory("job-book-harness-affinity-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let script_path = @pathx.join(dir, "provider_task.sh")
    let state_path = @pathx.join(dir, "persisted-path.txt")
    let run_cwd = workspace
      |> @pathx.join("books")
      |> @pathx.join("coding")
      |> @pathx.join("moonclaw-jobs")
      |> @pathx.join("run-1")
    @fsx.make_directory(run_cwd, recursive=true, exists_ok=true)
    write_multi_provider_task_fixture(workspace, script_path, state_path)

    let (command, batch) = match
      load_provider_task_task_batch(
        run_cwd,
        None,
        None,
        "Update the knowledge base",
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }

    inspect(command.provider.name, content="coding-main")
    inspect(batch.tasks.length().to_string(), content="1")
  })
}
