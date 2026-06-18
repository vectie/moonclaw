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
    let (command, batch) = match
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
      "Update the knowledge base", batch, command, config, 1000,
    )

    debug_inspect(proposal.suggested_family.unwrap_or(""), content="extension")
    debug_inspect(proposal.steps.length(), content="2")
    debug_inspect(proposal.steps[0].kind, content="job.analysis")
    debug_inspect(
      proposal.steps[0].execution_mode.unwrap_or(""),
      content="provider",
    )
    debug_inspect(
      proposal.steps[0].execution_target.unwrap_or(""),
      content="wiki-main",
    )
    debug_inspect(
      proposal.steps[0].metadata
      .stringify()
      .contains("\"bookapi_task_id\":\"task-1\""),
      content="true",
    )
    debug_inspect(
      proposal.steps[0].metadata.stringify().contains("\"timeout_ms\":600000"),
      content="true",
    )
    debug_inspect(
      proposal.steps[0].metadata
      .stringify()
      .contains("\"max_total_tokens\":24000"),
      content="true",
    )
    debug_inspect(
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
  let command = ProviderTaskCommand::{
    provider: @resource_providers.RegisteredResourceProvider::new(
      name="wiki-main",
      title="Wiki Main",
      kind="task-provider",
      capabilities=["provider.task"],
      metadata={
        "command": "moon",
        "args": ["run", "cmd/main", "--"],
        "cwd": "/tmp/provider-root",
        "workspace_root": "/tmp/provider-workspace",
      },
    ),
    command: "moon",
    args: ["run", "cmd/main", "--"],
    cwd: Some("/tmp/provider-root"),
    workspace_root: "/tmp/provider-workspace",
  }
  let proposal = provider_task_child_proposal(
    "Bootstrap ingest", batch, command, config, 1000,
  )
  debug_inspect(proposal.steps.length(), content="2")
  debug_inspect(
    proposal.steps[0].id.has_prefix("provider-task-"),
    content="true",
  )
  debug_inspect(
    proposal.steps[1].id.has_prefix("provider-task-"),
    content="true",
  )
  debug_inspect(
    proposal.profile_metadata.stringify().contains("\"task_count\":2"),
    content="true",
  )
  debug_inspect(
    proposal.profile_metadata.stringify().contains("\"deferred_task_count\":1"),
    content="true",
  )
}

///|
test "provider task child proposal enables web tools for web-first tasks" {
  let task = ProviderTaskSpec::{
    id: "bootstrap_gather",
    title: "Gather bootstrap materials",
    kind: "bootstrap_gather",
    prompt: "Run web_search first, then write raw/bootstrap/search-log.md.",
    priority: 100,
    requires_review: true,
    target_pages: ["raw/bootstrap/search-log.md"],
  }
  let command = ProviderTaskCommand::{
    provider: @resource_providers.RegisteredResourceProvider::new(
      name="wiki-main",
      title="Wiki Main",
      kind="task-provider",
      capabilities=["provider.task"],
      metadata={},
    ),
    command: "moon",
    args: [],
    cwd: None,
    workspace_root: "/tmp/provider-workspace",
  }
  let metadata = provider_task_step_metadata(
    "Use web-first research before local-only conclusions.", "goal-1", task, command,
  )
  let serialized = metadata.stringify()
  debug_inspect(serialized.contains("\"enable_tools\":true"), content="true")
  debug_inspect(serialized.contains("\"web_search\":true"), content="true")
  debug_inspect(serialized.contains("\"web_fetch\":true"), content="true")
}

///|
test "provider task child proposal enables web tools by default" {
  let task = ProviderTaskSpec::{
    id: "inspect",
    title: "Inspect source material",
    kind: "inspect",
    prompt: "Inspect the assigned source material.",
    priority: 100,
    requires_review: false,
    target_pages: ["raw/bootstrap/local-sources.md"],
  }
  let command = ProviderTaskCommand::{
    provider: @resource_providers.RegisteredResourceProvider::new(
      name="wiki-main",
      title="Wiki Main",
      kind="task-provider",
      capabilities=["provider.task"],
      metadata={},
    ),
    command: "moon",
    args: [],
    cwd: None,
    workspace_root: "/tmp/provider-workspace",
  }
  let metadata = provider_task_step_metadata(
    "Inspect source material", "goal-1", task, command,
  )
  let serialized = metadata.stringify()
  debug_inspect(serialized.contains("\"web_search\":true"), content="true")
  debug_inspect(serialized.contains("\"web_fetch\":true"), content="true")
}

///|
test "provider task child proposal keeps bootstrap execution bounded" {
  let batch = ProviderTaskBatch::{
    goal_id: "goal-1",
    goal: "Bootstrap ingest",
    summary: "Out-of-order execution batch",
    tasks: [
      ProviderTaskSpec::{
        id: "review",
        title: "Review pending book updates",
        kind: "review",
        prompt: "Review",
        priority: 100,
        requires_review: true,
        target_pages: ["wiki/reviews/pending.md"],
      },
      ProviderTaskSpec::{
        id: "knowledge_revise",
        title: "Revise knowledge pages",
        kind: "knowledge_revise",
        prompt: "Revise",
        priority: 90,
        requires_review: true,
        target_pages: ["wiki/concepts/demo.md"],
      },
      ProviderTaskSpec::{
        id: "bootstrap_gather",
        title: "Gather bootstrap materials",
        kind: "bootstrap_gather",
        prompt: "Gather",
        priority: 80,
        requires_review: true,
        target_pages: ["raw/bootstrap/demo.md"],
      },
      ProviderTaskSpec::{
        id: "source_materialize",
        title: "Materialize durable source pages",
        kind: "source_materialize",
        prompt: "Materialize",
        priority: 70,
        requires_review: true,
        target_pages: ["wiki/sources/demo.md"],
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
  let command = ProviderTaskCommand::{
    provider: @resource_providers.RegisteredResourceProvider::new(
      name="wiki-main",
      title="Wiki Main",
      kind="task-provider",
      capabilities=["provider.task"],
      metadata={
        "command": "moon",
        "args": ["run", "cmd/main", "--"],
        "cwd": "/tmp/provider-root",
        "workspace_root": "/tmp/provider-workspace",
      },
    ),
    command: "moon",
    args: ["run", "cmd/main", "--"],
    cwd: Some("/tmp/provider-root"),
    workspace_root: "/tmp/provider-workspace",
  }
  let proposal = provider_task_child_proposal(
    "Bootstrap ingest", batch, command, config, 1000,
  )
  debug_inspect(proposal.steps.length(), content="4")
  debug_inspect(
    proposal.steps[0].metadata
    .stringify()
    .contains("\"bookapi_task_kind\":\"bootstrap_gather\""),
    content="true",
  )
  debug_inspect(
    proposal.steps[1].metadata
    .stringify()
    .contains("\"bookapi_task_kind\":\"source_materialize\""),
    content="true",
  )
  debug_inspect(
    proposal.steps[2].metadata
    .stringify()
    .contains("\"bookapi_task_kind\":\"knowledge_revise\""),
    content="true",
  )
  debug_inspect(
    proposal.steps[3].metadata
    .stringify()
    .contains("\"bookapi_task_kind\":\"review\""),
    content="true",
  )
}

///|
test "provider task normalizes provider task kind and title from step metadata" {
  let task = ProviderTaskSpec::{
    id: "goal-demo-source_materialize",
    title: "Review pending book updates",
    kind: "review",
    prompt: "Review",
    priority: 10,
    requires_review: false,
    target_pages: ["reviews/pending.md"],
  }
  let normalized = normalize_provider_task_spec_from_metadata(
    {
      "extension_task_kind": "source_materialize",
      "extension_priority": 90,
      "extension_requires_review": true,
      "extension_target_pages": ["sources/", "index.md", "log.md"],
    },
    task,
  )
  debug_inspect(normalized.kind, content="source_materialize")
  debug_inspect(normalized.title, content="Materialize durable source pages")
  debug_inspect(normalized.priority.to_string(), content="90")
  debug_inspect(normalized.requires_review.to_string(), content="true")
  debug_inspect(
    normalized.target_pages.join(","),
    content="sources/,index.md,log.md",
  )
}

///|
test "provider task can pin full task spec in step metadata" {
  let task = ProviderTaskSpec::{
    id: "task-source",
    title: "Materialize durable source pages",
    kind: "source_materialize",
    prompt: "Materialize durable source pages from bootstrap packets.",
    priority: 90,
    requires_review: true,
    target_pages: ["wiki/sources/", "wiki/index.md", "wiki/log.md"],
  }
  let decoded = provider_task_spec_from_metadata({
    "extension_task_spec": task.to_json(),
  })
  debug_inspect(decoded is Some(_), content="true")
  debug_inspect(
    decoded.map(fn(value) { value.kind }).unwrap_or(""),
    content="source_materialize",
  )
  debug_inspect(
    decoded.map(fn(value) { value.target_pages.join(",") }).unwrap_or(""),
    content="wiki/sources/,wiki/index.md,wiki/log.md",
  )
}

///|
test "provider task reads pinned spec from nested step metadata" {
  let gather = ProviderTaskSpec::{
    id: "task-gather",
    title: "Gather bootstrap materials",
    kind: "bootstrap_gather",
    prompt: "Gather bootstrap packets.",
    priority: 100,
    requires_review: false,
    target_pages: ["raw/bootstrap/"],
  }
  let materialize = ProviderTaskSpec::{
    id: "task-materialize",
    title: "Materialize durable source pages",
    kind: "source_materialize",
    prompt: "Materialize durable source pages from bootstrap packets.",
    priority: 90,
    requires_review: true,
    target_pages: ["wiki/sources/", "wiki/index.md", "wiki/log.md"],
  }
  let nested_metadata : Json = {
    "proposal_step_id": "step_2",
    "step_metadata": {
      "extension_task_id": materialize.id,
      "extension_task_spec": materialize.to_json(),
      "extension_task_kind": materialize.kind,
      "extension_priority": materialize.priority,
      "extension_requires_review": materialize.requires_review,
      "extension_target_pages": materialize.target_pages,
    },
  }
  let decoded = provider_task_spec_from_metadata(nested_metadata).unwrap_or(
    gather,
  )
  let normalized = normalize_provider_task_spec_from_metadata(
    nested_metadata, decoded,
  )
  debug_inspect(normalized.id, content="task-materialize")
  debug_inspect(normalized.kind, content="source_materialize")
  debug_inspect(normalized.title, content="Materialize durable source pages")
  debug_inspect(
    normalized.target_pages.join(","),
    content="wiki/sources/,wiki/index.md,wiki/log.md",
  )
}

///|
async test "provider task runner reuses embedded provider command when manifest is unavailable" {
  @fsx.with_temporary_directory("job-book-harness-embedded-command-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let script_path = @pathx.join(dir, "provider_task.sh")
    let state_path = @pathx.join(dir, "persisted-path.txt")
    @fsx.make_directory(workspace, recursive=true, exists_ok=true)
    write_provider_task_fixture(workspace, script_path, state_path)
    let manifest_path = @pathx.join(workspace, ".moonclaw")
      |> @pathx.join("providers.json")
    @fsx.remove(manifest_path) catch {
      _ => ()
    }
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
        "provider_command": {
          "provider_name": "wiki-main",
          "command": "sh",
          "args": [script_path, state_path],
          "workspace_root": @pathx.join(workspace, "book-space"),
        },
      },
      cwd: workspace,
      home: None,
      model_name: "codex/gpt-5.4",
      enable_tools: false,
      web_search: false,
      tool_contract: AnalysisToolContract::new(),
      preferred_skills: [],
      job_id: "job-1",
      run_id: "run-1",
      step_id: "step-1",
      execution_isolation: None,
      role_runtime_contract: None,
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
            #|  "summary": "Updated the wiki and captured the contradiction.",
            #|  "artifacts": ["wiki/entity.md"],
            #|  "memory_candidates": [],
            #|  "requires_review": true,
            #|  "notify_town": false
            #|}
          ),
          conversation_id: Some("conv-provider-embedded"),
          usage: None,
          metadata: {},
        })
      }) {
      Ok(execution) => execution
      Err(error) => fail(error)
    }
    debug_inspect(
      execution.content.contains("# Extension Task Result"),
      content="true",
    )
    let persisted_path = @fsx.read_file(state_path)
    debug_inspect(
      persisted_path.contains(".moonclaw-provider-result-run-1-"),
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

    debug_inspect(
      captured_prompt.val.contains("Relevant Pages:"),
      content="true",
    )
    debug_inspect(
      captured_prompt.val.contains("wiki/entity.md"),
      content="true",
    )
    debug_inspect(
      captured_system_prompt.val.contains(
        "loaded `provider-task-execution` skill defines the execution method.",
      ),
      content="true",
    )
    debug_inspect(
      captured_prompt.val.contains("provider-task-execution"),
      content="true",
    )
    debug_inspect(
      captured_system_prompt.val.contains("Base system prompt."),
      content="true",
    )
    debug_inspect(
      captured_system_prompt.val.contains(
        "Read concrete candidate files directly before using broad repo-wide search tools.",
      ),
      content="true",
    )
    debug_inspect(
      captured_system_prompt.val.contains(".mooncakes"),
      content="true",
    )
    debug_inspect(
      captured_system_prompt.val.contains("raw/bootstrap/*"),
      content="true",
    )
    debug_inspect(captured_enable_tools.val, content="true")
    debug_inspect(captured_web_search.val, content="true")
    debug_inspect(captured_todo_enabled.val, content="false")
    debug_inspect(
      execution.content.contains("# Extension Task Result"),
      content="true",
    )
    debug_inspect(execution.content.contains("evidence-1"), content="true")
    debug_inspect(
      execution.metadata.stringify().contains("\"execution_mode\":\"provider\""),
      content="true",
    )
    debug_inspect(
      execution.metadata
      .stringify()
      .contains("\"extension_task_id\":\"task-1\""),
      content="true",
    )
    let persisted_path = @fsx.read_file(state_path)
    let persisted_step_key = safe_step_file_segment("step-1")
    debug_inspect(
      persisted_path.contains(
        ".moonclaw-provider-result-run-1-\{persisted_step_key}.json",
      ),
      content="true",
    )
    let persisted_payload = @fsx.read_file(persisted_path.trim())
    debug_inspect(
      persisted_payload.contains("\"summary\": \"Updated the wiki"),
      content="true",
    )
  })
}

///|
test "provider task tool-loop policy enables bounded local execution for provider phases" {
  debug_inspect(
    provider_task_requires_local_tool_loop(ProviderTaskSpec::{
      id: "task-gather",
      title: "Gather bootstrap materials",
      kind: "bootstrap_gather",
      prompt: "Inspect the source materials and write bootstrap packets.",
      priority: 90,
      requires_review: true,
      target_pages: ["raw/bootstrap/demo.md"],
    }),
    content="true",
  )
  debug_inspect(
    provider_task_requires_local_tool_loop(ProviderTaskSpec::{
      id: "task-review",
      title: "Review pending changes",
      kind: "review_finalize",
      prompt: "Review the pending changes and emit the final result.",
      priority: 40,
      requires_review: false,
      target_pages: ["wiki/review.md"],
    }),
    content="true",
  )
}

///|
async test "provider task precompiles source materialize substeps from bootstrap packets" {
  @fsx.with_temporary_directory("job-provider-precompiled-materialize-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let bootstrap_dir = @pathx.join(workspace, "raw")
      |> @pathx.join("bootstrap")
    @fsx.make_directory(bootstrap_dir, recursive=true, exists_ok=true)
    let bootstrap_content =
      #|# Demo Bootstrap
      #|
      #|## Candidate pages
      #|
      #|- `wiki/sources/demo-readme.md`
      #|- `wiki/sources/demo-architecture.md`
      #|- `wiki/entities/demo.md`
      #|
    @fsx.write_to_file(
      @pathx.join(bootstrap_dir, "demo-bootstrap.md"),
      bootstrap_content,
    )
    let context = ProviderTaskWorkerContext::{
      book_id: "demo",
      workspace_root: workspace,
      task_id: "task-source",
      prompt: "Materialize durable source pages.",
      policy: [],
      routines: [],
      skill_paths: [],
      context_pages: [],
      active_memory: [],
      user_memory: [],
      working_memory: [],
      memory_summary: "",
      output_contract: [],
    }
    let envelope = provider_task_precompiled_envelope(
      ProviderTaskSpec::{
        id: "task-source",
        title: "Materialize source pages",
        kind: "source_materialize",
        prompt: "Create durable source pages from bootstrap material.",
        priority: 90,
        requires_review: true,
        target_pages: ["wiki/sources/"],
      },
      context,
    )
    debug_inspect(envelope is Some(_), content="true")
    let substeps = envelope
      .map(fn(value) { adaptive_substeps(value) })
      .unwrap_or([])
    debug_inspect(substeps.length().to_string(), content="2")
    debug_inspect(substeps[0].title.contains("demo-readme"), content="true")
    debug_inspect(
      substeps[0].prompt.contains("raw/bootstrap/demo-bootstrap.md"),
      content="true",
    )
  })
}

///|
async test "provider task gates knowledge revise behind source materialization" {
  @fsx.with_temporary_directory("job-provider-phase-gate-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let bootstrap_dir = @pathx.join(workspace, "raw")
      |> @pathx.join("bootstrap")
    @fsx.make_directory(bootstrap_dir, recursive=true, exists_ok=true)
    @fsx.write_to_file(
      @pathx.join(bootstrap_dir, "demo-bootstrap.md"),
      (
        #|# Demo Bootstrap
        #|
        #|## Candidate pages
        #|
        #|- `wiki/sources/demo-readme.md`
        #|- `wiki/entities/demo.md`
        #|,
      ),
    )
    let context = ProviderTaskWorkerContext::{
      book_id: "demo",
      workspace_root: workspace,
      task_id: "task-revise",
      prompt: "Revise knowledge pages.",
      policy: [],
      routines: [],
      skill_paths: [],
      context_pages: [],
      active_memory: [],
      user_memory: [],
      working_memory: [],
      memory_summary: "",
      output_contract: [],
    }
    let envelope = provider_task_precompiled_envelope(
      ProviderTaskSpec::{
        id: "task-revise",
        title: "Revise knowledge surfaces",
        kind: "knowledge_revise",
        prompt: "Revise ontology and synthesis pages.",
        priority: 70,
        requires_review: true,
        target_pages: ["wiki/entities/", "wiki/concepts/"],
      },
      context,
    )
    debug_inspect(envelope is Some(_), content="true")
    let substeps = envelope
      .map(fn(value) { adaptive_substeps(value) })
      .unwrap_or([])
    debug_inspect(substeps.length().to_string(), content="1")
    debug_inspect(substeps[0].title.contains("demo-readme"), content="true")
    debug_inspect(
      substeps[0].prompt.contains(
        "Materialize or revise only this durable page",
      ),
      content="true",
    )
  })
}

///|
async test "provider task caps materialize fanout" {
  @fsx.with_temporary_directory("job-provider-materialize-cap-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let bootstrap_dir = @pathx.join(workspace, "raw")
      |> @pathx.join("bootstrap")
    @fsx.make_directory(bootstrap_dir, recursive=true, exists_ok=true)
    @fsx.write_to_file(
      @pathx.join(bootstrap_dir, "demo-bootstrap.md"),
      (
        #|# Demo Bootstrap
        #|
        #|## Candidate pages
        #|
        #|- `wiki/sources/one.md`
        #|- `wiki/sources/two.md`
        #|- `wiki/sources/three.md`
        #|- `wiki/sources/four.md`
        #|- `wiki/sources/five.md`
        #|,
      ),
    )
    let context = ProviderTaskWorkerContext::{
      book_id: "demo",
      workspace_root: workspace,
      task_id: "task-source",
      prompt: "Materialize durable source pages.",
      policy: [],
      routines: [],
      skill_paths: [],
      context_pages: [],
      active_memory: [],
      user_memory: [],
      working_memory: [],
      memory_summary: "",
      output_contract: [],
    }
    let envelope = provider_task_precompiled_envelope(
      ProviderTaskSpec::{
        id: "task-source",
        title: "Materialize source pages",
        kind: "source_materialize",
        prompt: "Create durable source pages from bootstrap material.",
        priority: 90,
        requires_review: true,
        target_pages: ["wiki/sources/"],
      },
      context,
    )
    let substeps = envelope
      .map(fn(value) { adaptive_substeps(value) })
      .unwrap_or([])
    debug_inspect(substeps.length().to_string(), content="2")
  })
}

///|
async test "provider task derives knowledge revision targets from source pages" {
  @fsx.with_temporary_directory(
    "job-provider-knowledge-source-targets-XXXXXX",
    async fn(dir) {
      let workspace = @pathx.join(dir, "workspace")
      let sources_dir = @pathx.join(workspace, "wiki") |> @pathx.join("sources")
      @fsx.make_directory(sources_dir, recursive=true, exists_ok=true)
      @fsx.write_to_file(@pathx.join(sources_dir, "alpha.md"), "# Alpha\n")
      @fsx.write_to_file(@pathx.join(sources_dir, "beta.md"), "# Beta\n")
      let context = ProviderTaskWorkerContext::{
        book_id: "demo",
        workspace_root: workspace,
        task_id: "task-revise",
        prompt: "Revise knowledge pages.",
        policy: [],
        routines: [],
        skill_paths: [],
        context_pages: [],
        active_memory: [],
        user_memory: [],
        working_memory: [],
        memory_summary: "",
        output_contract: [],
      }
      let envelope = provider_task_precompiled_envelope(
        ProviderTaskSpec::{
          id: "task-revise",
          title: "Revise knowledge surfaces",
          kind: "knowledge_revise",
          prompt: "Revise ontology and synthesis pages.",
          priority: 70,
          requires_review: true,
          target_pages: ["wiki/entities/", "wiki/concepts/"],
        },
        context,
      )
      debug_inspect(envelope is Some(_), content="true")
      let substeps = envelope
        .map(fn(value) { adaptive_substeps(value) })
        .unwrap_or([])
      debug_inspect(substeps.length().to_string(), content="4")
      let has_alpha = substeps
        .iter()
        .any(fn(step) { step.title.contains("alpha") })
      debug_inspect(has_alpha, content="true")
      let has_entity = substeps
        .iter()
        .any(fn(step) { step.prompt.contains("wiki/entities/demo.md") })
      debug_inspect(has_entity, content="true")
    },
  )
}

///|
async test "provider task precompiles review closeout when sources exist" {
  @fsx.with_temporary_directory("job-provider-review-closeout-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let sources_dir = @pathx.join(workspace, "wiki") |> @pathx.join("sources")
    @fsx.make_directory(sources_dir, recursive=true, exists_ok=true)
    @fsx.write_to_file(@pathx.join(sources_dir, "alpha.md"), "# Alpha\n")
    let context = ProviderTaskWorkerContext::{
      book_id: "demo",
      workspace_root: workspace,
      task_id: "task-review",
      prompt: "Finalize review.",
      policy: [],
      routines: [],
      skill_paths: [],
      context_pages: [],
      active_memory: [],
      user_memory: [],
      working_memory: [],
      memory_summary: "",
      output_contract: [],
    }
    let envelope = provider_task_precompiled_envelope(
      ProviderTaskSpec::{
        id: "task-review",
        title: "Review pending book updates",
        kind: "review",
        prompt: "Finalize the provider task.",
        priority: 20,
        requires_review: false,
        target_pages: ["wiki/reviews/pending.md"],
      },
      context,
    )
    debug_inspect(envelope is Some(_), content="true")
    let substeps = envelope
      .map(fn(value) { adaptive_substeps(value) })
      .unwrap_or([])
    debug_inspect(substeps.length().to_string(), content="1")
    debug_inspect(substeps[0].title, content="Finalize provider review")
    debug_inspect(
      substeps[0].prompt.contains("wiki/sources/alpha.md"),
      content="true",
    )
  })
}

///|
test "provider task can fast complete review from source inventory" {
  let knowledge = ProviderTaskSpec::{
    id: "knowledge",
    title: "Revise knowledge surfaces",
    kind: "knowledge_revise",
    prompt: "",
    priority: 10,
    requires_review: true,
    target_pages: [],
  }
  let review = ProviderTaskSpec::{
    id: "review",
    title: "Review pending updates",
    kind: "review_finalize",
    prompt: "",
    priority: 10,
    requires_review: false,
    target_pages: [],
  }
  let source = ProviderTaskSpec::{
    id: "source",
    title: "Materialize source pages",
    kind: "source_materialize",
    prompt: "",
    priority: 10,
    requires_review: true,
    target_pages: [],
  }
  debug_inspect(
    provider_task_can_complete_from_source_inventory(knowledge),
    content="false",
  )
  debug_inspect(
    provider_task_can_complete_from_source_inventory(review),
    content="true",
  )
  debug_inspect(
    provider_task_can_complete_from_source_inventory(source),
    content="false",
  )
  let result = provider_task_source_inventory_result(review, [
    "wiki/sources/alpha.md", "wiki/sources/beta.md",
  ])
  debug_inspect(result.requires_review, content="false")
  debug_inspect(result.artifacts.length().to_string(), content="2")
}

///|
test "provider task synthesized subplan result does not queue intermediate review" {
  let task = ProviderTaskSpec::{
    id: "gather",
    title: "Gather bootstrap materials",
    kind: "bootstrap_gather",
    prompt: "",
    priority: 90,
    requires_review: true,
    target_pages: [],
  }
  let result = provider_task_synthesized_subplan_result(
    task,
    AnalysisExecution::{
      model_name: "test",
      content: "{}",
      conversation_id: None,
      usage: None,
      metadata: {},
    },
    ["raw/bootstrap/demo.md"],
  )
  debug_inspect(result.requires_review, content="false")
}

///|
async test "provider task uses command workspace root when provider context root drifts" {
  @fsx.with_temporary_directory("job-provider-effective-root-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let wrong_root = @pathx.join(dir, "wrong-root")
    let bootstrap_dir = @pathx.join(workspace, "raw")
      |> @pathx.join("bootstrap")
    @fsx.make_directory(bootstrap_dir, recursive=true, exists_ok=true)
    @fsx.make_directory(wrong_root, recursive=true, exists_ok=true)
    @fsx.write_to_file(
      @pathx.join(bootstrap_dir, "demo-bootstrap.md"),
      (
        #|# Demo Bootstrap
        #|
        #|## Candidate pages
        #|
        #|- `wiki/sources/demo-readme.md`
        #|,
      ),
    )
    let effective_root = provider_task_effective_workspace_root(
      workspace,
      wrong_root,
      @pathx.join(dir, "request-cwd"),
    )
    let context = ProviderTaskWorkerContext::{
      book_id: "demo",
      workspace_root: effective_root,
      task_id: "task-source",
      prompt: "Materialize durable source pages.",
      policy: [],
      routines: [],
      skill_paths: [],
      context_pages: [],
      active_memory: [],
      user_memory: [],
      working_memory: [],
      memory_summary: "",
      output_contract: [],
    }
    let envelope = provider_task_precompiled_envelope(
      ProviderTaskSpec::{
        id: "task-source",
        title: "Materialize source pages",
        kind: "source_materialize",
        prompt: "Create durable source pages from bootstrap material.",
        priority: 90,
        requires_review: true,
        target_pages: ["wiki/sources/"],
      },
      context,
    )
    debug_inspect(effective_root == workspace, content="true")
    debug_inspect(envelope is Some(_), content="true")
    let substeps = envelope
      .map(fn(value) { adaptive_substeps(value) })
      .unwrap_or([])
    debug_inspect(substeps.length().to_string(), content="1")
    debug_inspect(substeps[0].title.contains("demo-readme"), content="true")
  })
}

///|
async test "provider task precompiles bootstrap gather lanes from source hints" {
  @fsx.with_temporary_directory("job-provider-precompiled-bootstrap-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let source_root = @pathx.join(dir, "demo")
    let bootstrap_dir = @pathx.join(workspace, "raw")
      |> @pathx.join("bootstrap")
    @fsx.make_directory(
      @pathx.join(source_root, "cmd") |> @pathx.join("main"),
      recursive=true,
      exists_ok=true,
    )
    @fsx.make_directory(
      @pathx.join(source_root, "roles"),
      recursive=true,
      exists_ok=true,
    )
    @fsx.make_directory(
      @pathx.join(source_root, "adapters"),
      recursive=true,
      exists_ok=true,
    )
    @fsx.write_to_file(@pathx.join(source_root, "README.md"), "# Demo\n")
    @fsx.write_to_file(@pathx.join(source_root, "AGENTS.md"), "# Agents\n")
    @fsx.write_to_file(@pathx.join(source_root, "moon.mod.json"), "{ }\n")
    @fsx.write_to_file(
      @pathx.join(source_root, "cmd")
      |> @pathx.join("main")
      |> @pathx.join("main.mbt"),
      "///|\n",
    )
    @fsx.write_to_file(
      @pathx.join(source_root, "roles") |> @pathx.join("mayor.mbt"),
      "///|\n",
    )
    @fsx.write_to_file(
      @pathx.join(source_root, "roles") |> @pathx.join("lead.mbt"),
      "///|\n",
    )
    @fsx.write_to_file(
      @pathx.join(source_root, "adapters") |> @pathx.join("moonbook.mbt"),
      "///|\n",
    )
    @fsx.write_to_file(
      @pathx.join(source_root, "adapters") |> @pathx.join("moonclaw.mbt"),
      "///|\n",
    )
    @fsx.write_to_file(
      @pathx.join(source_root, "README.mbt.md"),
      "# Demo API\n",
    )
    @fsx.make_directory(bootstrap_dir, recursive=true, exists_ok=true)
    let hints =
      #|# Source Hints
      #|
      #|## Local Repository Follow-Up
      #|
      #|- __SOURCE_ROOT__/README.md
      #|- __SOURCE_ROOT__/AGENTS.md
      #|- __SOURCE_ROOT__/moon.mod.json
      #|- __SOURCE_ROOT__/cmd/main/main.mbt
      #|- __SOURCE_ROOT__/roles/mayor.mbt
      #|- __SOURCE_ROOT__/roles/lead.mbt
      #|- __SOURCE_ROOT__/adapters/moonbook.mbt
      #|- __SOURCE_ROOT__/adapters/moonclaw.mbt
      #|- __SOURCE_ROOT__/README.mbt.md
      #|
    @fsx.write_to_file(
      @pathx.join(bootstrap_dir, "SOURCE_HINTS.md"),
      hints.replace(old="__SOURCE_ROOT__", new=source_root),
    )
    let context = ProviderTaskWorkerContext::{
      book_id: "demo",
      workspace_root: workspace,
      task_id: "task-bootstrap",
      prompt: "Gather bootstrap evidence.",
      policy: [],
      routines: [],
      skill_paths: [],
      context_pages: [],
      active_memory: [],
      user_memory: [],
      working_memory: [],
      memory_summary: "",
      output_contract: [],
    }
    let envelope = provider_task_precompiled_envelope(
      ProviderTaskSpec::{
        id: "task-bootstrap",
        title: "Gather bootstrap evidence",
        kind: "bootstrap_gather",
        prompt: "Inspect source hints and write bootstrap packets.",
        priority: 90,
        requires_review: true,
        target_pages: ["raw/bootstrap/"],
      },
      context,
    )
    debug_inspect(envelope is Some(_), content="true")
    let substeps = envelope
      .map(fn(value) { adaptive_substeps(value) })
      .unwrap_or([])
    debug_inspect(substeps.length().to_string(), content="2")
    debug_inspect(substeps[0].title, content="Gather bootstrap lane 1")
    debug_inspect(substeps[0].prompt.contains("raw/bootstrap/"), content="true")
    debug_inspect(
      substeps[0].prompt.contains("mounted-sources/"),
      content="true",
    )
    debug_inspect(substeps[0].prompt.contains(source_root), content="false")
  })
}

///|
async test "provider task precompiled substeps include loaded skill bodies" {
  @fsx.with_temporary_directory(
    "job-provider-precompiled-skill-bodies-XXXXXX",
    async fn(dir) {
      let workspace = @pathx.join(dir, "workspace")
      let source_root = @pathx.join(dir, "demo")
      let skill_dir = @pathx.join(workspace, "skills")
        |> @pathx.join("wiki-ingest")
      let bootstrap_dir = @pathx.join(workspace, "raw")
        |> @pathx.join("bootstrap")
      @fsx.make_directory(skill_dir, recursive=true, exists_ok=true)
      @fsx.make_directory(source_root, recursive=true, exists_ok=true)
      @fsx.make_directory(bootstrap_dir, recursive=true, exists_ok=true)
      @fsx.write_to_file(@pathx.join(source_root, "README.md"), "# Demo\n")
      @fsx.write_to_file(
        @pathx.join(skill_dir, "SKILL.md"),
        (
          #|# Wiki Ingest
          #|
          #|Write `raw/bootstrap/research-question.md` before claiming completion.
          #|Write `raw/bootstrap/evidence-matrix.md` before claiming completion.
        ),
      )
      @fsx.write_to_file(
        @pathx.join(bootstrap_dir, "SOURCE_HINTS.md"),
        "# Source Hints\n\n## Local Repository Follow-Up\n\n- \{source_root}/README.md\n",
      )
      let context = ProviderTaskWorkerContext::{
        book_id: "demo",
        workspace_root: workspace,
        task_id: "task-bootstrap",
        prompt: "Gather bootstrap evidence.",
        policy: [],
        routines: [],
        skill_paths: ["skills/wiki-ingest/SKILL.md"],
        context_pages: [],
        active_memory: [],
        user_memory: [],
        working_memory: [],
        memory_summary: "",
        output_contract: [
          "Create research-method bootstrap artifacts", "Required: raw/bootstrap/research-question.md and raw/bootstrap/evidence-matrix.md",
        ],
      }
      let envelope = provider_task_precompiled_envelope(
        ProviderTaskSpec::{
          id: "task-bootstrap",
          title: "Gather bootstrap evidence",
          kind: "bootstrap_gather",
          prompt: "Inspect source hints and write bootstrap packets.",
          priority: 90,
          requires_review: true,
          target_pages: ["raw/bootstrap/"],
        },
        context,
      )
      let substeps = envelope
        .map(fn(value) { adaptive_substeps(value) })
        .unwrap_or([])
      debug_inspect(substeps.length().to_string(), content="3")
      debug_inspect(substeps[0].title, content="Write research evidence packet")
      debug_inspect(substeps[1].title, content="Write deep research report")
      debug_inspect(substeps[2].title, content="Write marketing brief")
      debug_inspect(
        substeps[0].prompt.contains("Loaded provider skill bodies:"),
        content="true",
      )
      debug_inspect(
        substeps[0].prompt.contains("raw/bootstrap/research-question.md"),
        content="true",
      )
      debug_inspect(
        substeps[0].prompt.contains("raw/bootstrap/evidence-matrix.md"),
        content="true",
      )
      debug_inspect(
        substeps[0].prompt.contains("raw/bootstrap/synthesis-brief.md"),
        content="true",
      )
      debug_inspect(
        substeps[1].prompt.contains("raw/bootstrap/deep-report.md"),
        content="true",
      )
      debug_inspect(
        substeps[2].prompt.contains("raw/bootstrap/marketing-brief.md"),
        content="true",
      )
    },
  )
}

///|
async test "provider task research dossier stays raw envelope only" {
  @fsx.with_temporary_directory("job-provider-raw-research-envelope-XXXXXX", async fn(
    dir,
  ) {
    let workspace = @pathx.join(dir, "workspace")
    let bootstrap_dir = @pathx.join(workspace, "raw")
      |> @pathx.join("bootstrap")
    @fsx.make_directory(bootstrap_dir, recursive=true, exists_ok=true)
    @fsx.write_to_file(
      @pathx.join(bootstrap_dir, "RESEARCH_REQUEST.md"),
      "# Research Request\n\nResearch MoonClaw runtime boundaries.\n",
    )
    @fsx.write_to_file(
      @pathx.join(bootstrap_dir, "SOURCE_HINTS.md"),
      (
        #|# Source Hints
        #|
        #|## Web Search First
        #|
        #|- MoonClaw MoonBook Moontown architecture
        #|
        #|## High-Signal URLs
        #|
        #|- https://github.com/vectie/moonclaw
        #|
        #|## Materialization Target
        #|
        #|- MoonBook should materialize durable wiki pages from raw artifacts.
      ),
    )
    let context = ProviderTaskWorkerContext::{
      book_id: "research-moonclaw",
      workspace_root: workspace,
      task_id: "task-bootstrap",
      prompt: "Research MoonClaw.",
      policy: [],
      routines: [],
      skill_paths: ["skills/wiki-ingest/SKILL.md"],
      context_pages: [],
      active_memory: [],
      user_memory: [],
      working_memory: [],
      memory_summary: "",
      output_contract: [
        "Required raw/bootstrap/research-question.md", "Required raw/bootstrap/evidence-matrix.md",
        "Required raw/bootstrap/synthesis-brief.md", "Required raw/bootstrap/deep-report.md",
        "Required raw/bootstrap/marketing-brief.md",
      ],
    }
    let artifacts = provider_task_write_research_dossier_if_needed(
      ProviderTaskSpec::{
        id: "task-bootstrap",
        title: "Gather research envelope",
        kind: "bootstrap_gather",
        prompt: "Write raw/bootstrap research files.",
        priority: 90,
        requires_review: true,
        target_pages: ["raw/bootstrap/"],
      },
      context,
    )
    debug_inspect(artifacts.length().to_string(), content="6")
    debug_inspect(
      @fsx.exists(@pathx.join(bootstrap_dir, "research-question.md")).to_string(),
      content="true",
    )
    debug_inspect(
      @fsx.exists(@pathx.join(workspace, "wiki")).to_string(),
      content="false",
    )
    let brief = @fsx.read_file(@pathx.join(bootstrap_dir, "synthesis-brief.md"))
    debug_inspect(brief.contains("Provisional findings"), content="false")
    debug_inspect(
      @fsx.exists(@pathx.join(bootstrap_dir, "deep-report.md")).to_string(),
      content="false",
    )
    debug_inspect(
      @fsx.exists(@pathx.join(bootstrap_dir, "marketing-brief.md")).to_string(),
      content="false",
    )
    let search = @fsx.read_file(@pathx.join(bootstrap_dir, "search-log.md"))
    debug_inspect(search.contains("may enrich it later"), content="false")
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

    debug_inspect(outcome.evidence_id, content="evidence-1")
    let persisted_path = @fsx.read_file(state_path).trim().to_owned()
    debug_inspect(
      persisted_path.contains("book-space/.moonclaw/provider-task/"),
      content="true",
    )
    debug_inspect(
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
  debug_inspect(result.task_id, content="task-1")
  debug_inspect(result.requires_review, content="true")
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
  debug_inspect(outcome.log_path, content="wiki/log.md")
  debug_inspect(outcome.review_queued, content="true")
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

    debug_inspect(call_count.val, content="1")
    let envelope = match parse_adaptive_analysis_envelope(execution.content) {
      Some(envelope) => envelope
      None => fail("expected adaptive split envelope: \{execution.content}")
    }
    debug_inspect(envelope.verdict, content="needs_subplan")
    debug_inspect(adaptive_substeps(envelope).length(), content="2")
    debug_inspect(
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

    debug_inspect(
      error.contains("too broad to execute directly"),
      content="true",
    )
    debug_inspect(error.contains("no executable substeps"), content="true")
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
    debug_inspect(envelope.verdict, content="needs_subplan")
    debug_inspect(substeps.length(), content="1")
    debug_inspect(substeps[0].title, content="Queue follow-up review")
    debug_inspect(
      substeps[0].prompt.contains("task_id: task-2"),
      content="true",
    )
    debug_inspect(substeps[0].prompt.contains("wiki/review.md"), content="true")
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

    debug_inspect(artifacts.length(), content="2")
    debug_inspect(
      artifacts.contains("wiki/entities/moonclaw.md"),
      content="true",
    )
    debug_inspect(artifacts.contains("wiki/synthesis/map.md"), content="true")
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

    debug_inspect(
      finalized.content.contains("# Extension Task Result"),
      content="true",
    )
    debug_inspect(
      finalized.metadata.stringify().contains("\"extension_persist_outcome\""),
      content="true",
    )
    let persisted_path = @fsx.read_file(state_path).trim().to_owned()
    let persisted_payload = @fsx.read_file(persisted_path)
    debug_inspect(
      persisted_payload.contains("\"task_id\": \"task-1\""),
      content="true",
    )
    debug_inspect(
      persisted_payload.contains(
        "\"summary\": \"Materialized durable wiki outputs after bootstrap gather.\"",
      ),
      content="true",
    )
    debug_inspect(
      persisted_payload.contains("\"wiki/sources/demo.md\""),
      content="true",
    )
    debug_inspect(
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
    debug_inspect(call_count.val, content="1")
    debug_inspect(
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

    debug_inspect(call_count.val, content="2")
    debug_inspect(
      execution.metadata
      .stringify()
      .contains("\"extension_task_id\":\"task-1\""),
      content="true",
    )
    debug_inspect(
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

    debug_inspect(
      error.contains("Provider task analysis must return a JSON object"),
      content="true",
    )
    let step_key = safe_step_file_segment("step-1")
    let debug_file = ".moonclaw-provider-failure-run-1-\{step_key}.json"
    debug_inspect(error.contains(debug_file), content="true")
    let debug_path = match
      provider_task_failure_debug_path(
        request,
        @pathx.join(workspace, "book-space"),
      ) {
      Ok(path) => path
      Err(path_error) => fail(path_error)
    }
    debug_inspect(@fsx.exists(debug_path), content="true")
    let debug_payload = @fsx.read_file(debug_path)
    debug_inspect(
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

    debug_inspect(
      execution.content.contains("Blocked provider task"),
      content="true",
    )
    let persisted_path = @fsx.read_file(state_path).trim().to_owned()
    let persisted_payload = @fsx.read_file(persisted_path)
    debug_inspect(
      persisted_payload.contains(
        "\"summary\": \"Blocked provider task Extract durable updates:",
      ),
      content="true",
    )
    debug_inspect(
      persisted_payload.contains("\"kind\": \"blocker\""),
      content="true",
    )
    debug_inspect(
      persisted_payload.contains("\"kind\": \"next_step\""),
      content="true",
    )
    debug_inspect(
      persisted_payload.contains("\"durable\": false"),
      content="true",
    )
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

    debug_inspect(
      execution.content.contains("Updated the wiki"),
      content="true",
    )
    let persisted_path = @fsx.read_file(state_path).trim().to_owned()
    let persisted_payload = @fsx.read_file(persisted_path)
    debug_inspect(
      persisted_payload.contains("\"task_id\": \"task-1\""),
      content="true",
    )
    debug_inspect(
      persisted_payload.contains("\"wiki/entity.md\""),
      content="true",
    )
    debug_inspect(
      persisted_payload.contains("\"raw/bootstrap/packet.md\""),
      content="true",
    )
    debug_inspect(persisted_payload.contains("\"gpt-5.4\""), content="false")
    debug_inspect(
      persisted_payload.contains("\"skills/wiki-ingest/SKILL.md\""),
      content="false",
    )
    debug_inspect(
      persisted_payload.contains("\"moon.mod.json\""),
      content="false",
    )
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

    debug_inspect(command.provider.name, content="wiki-main")
    debug_inspect(batch.tasks.length().to_string(), content="2")
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

    debug_inspect(
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

    debug_inspect(command.provider.name, content="coding-main")
    debug_inspect(batch.tasks.length().to_string(), content="1")
  })
}
