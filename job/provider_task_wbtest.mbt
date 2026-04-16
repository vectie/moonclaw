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
      proposal.profile_metadata.stringify().contains("\"task_count\":2"),
      content="true",
    )
  })
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
    let execution = match
      run_provider_task_analysis_runner(request, fn(inner_request) {
        captured_prompt.val = inner_request.prompt
        captured_system_prompt.val = inner_request.system_prompt
        captured_enable_tools.val = inner_request.enable_tools
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
        "Do not return plans, outlines, or commentary.",
      ),
      content="true",
    )
    inspect(
      captured_system_prompt.val.contains("Base system prompt."),
      content="false",
    )
    inspect(captured_enable_tools.val, content="false")
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
async test "provider task analysis runner repairs planner-shaped output once" {
  @fsx.with_temporary_directory("job-book-harness-repair-XXXXXX", async fn(
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
            content: "{\"plan\":[{\"step\":1,\"title\":\"Inspect sources\"}]}",
            conversation_id: Some("conv-provider-plan"),
            usage: None,
            metadata: {},
          })
        } else {
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
    }

    inspect(call_count.val, content="2")
    inspect(
      execution.metadata
      .stringify()
      .contains("\"extension_task_id\":\"task-1\""),
      content="true",
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
      execution.content.contains("Completed provider task"),
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
    let debug_path = provider_task_failure_debug_path(request)
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
