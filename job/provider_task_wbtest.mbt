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
    let (_, batch) = match
      load_provider_task_task_batch(
        workspace,
        None,
        "wiki-main",
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
    let execution = match
      run_provider_task_analysis_runner(request, fn(inner_request) {
        captured_prompt.val = inner_request.prompt
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
    inspect(
      persisted_path.contains(".moonclaw-provider-result-run-1-step-1.json"),
      content="true",
    )
    let persisted_payload = @fsx.read_file(persisted_path.trim())
    inspect(
      persisted_payload.contains("\"summary\": \"Updated the wiki"),
      content="true",
    )
  })
}
