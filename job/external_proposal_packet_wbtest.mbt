///|
fn sample_external_profile_json() -> Json {
  {
    "jobs": {
      "profiles": {
        "wiki_ingest_controller": {
          "family": "wiki_ingest_controller",
          "role": "controller",
          "priority": 120,
          "tags": ["wiki", "ingest"],
          "steps": [
            {
              "id": "inspect",
              "title": "Inspect source",
              "kind": "job.analysis",
              "prompt_template": "Inspect packet for ${request}",
            },
          ],
          "metadata": { "domain": "wiki" },
        },
      },
    },
  }
}

///|
async fn write_external_packet_provider_fixture(
  workspace : String,
  script_path : String,
) -> Unit {
  @fsx.make_directory(
    workspace |> @pathx.join(".moonclaw"),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    workspace |> @pathx.join(".moonclaw") |> @pathx.join("providers.json"),
    (
      #|[
      #|  {
      #|    "name": "moonbook",
      #|    "title": "MoonBook Extension",
      #|    "description": "External packet provider fixture",
      #|    "kind": "extension",
      #|    "capabilities": ["provider.task"],
      #|    "metadata": {
      #|      "command": "sh",
      #|      "args": ["__SCRIPT__"],
      #|      "workspace_root": "__ROOT__"
      #|    }
      #|  }
      #|]
    )
    .replace(old="__SCRIPT__", new=script_path)
    .replace(old="__ROOT__", new=workspace),
  )
  @fsx.write_to_file(
    script_path,
    (
      #|#!/bin/sh
      #|set -eu
      #|subcommand="$3"
      #|root="$4"
      #|if [ "$subcommand" = "tasks" ]; then
      #|  cat <<EOF
      #|{
      #|  "goal_id": "goal-1",
      #|  "goal": "Imported packet goal",
      #|  "summary": "Imported packet extension task",
      #|  "tasks": [
      #|    {
      #|      "id": "task-1",
      #|      "title": "Extension ingest",
      #|      "kind": "wiki.update",
      #|      "prompt": "Apply the imported packet through the extension.",
      #|      "priority": 80,
      #|      "requires_review": false,
      #|      "target_pages": ["wiki/sources/demo.md"]
      #|    }
      #|  ]
      #|}
      #|EOF
      #|elif [ "$subcommand" = "context" ]; then
      #|  cat <<EOF
      #|{
      #|  "book_id": "book-1",
      #|  "workspace_root": "$root",
      #|  "task_id": "$7",
      #|  "prompt": "Use the imported packet context to update the workspace.",
      #|  "policy": ["Keep raw sources immutable"],
      #|  "routines": ["Revise durable pages"],
      #|  "skill_paths": ["skills/wiki-maintainer/SKILL.md"],
      #|  "context_pages": ["wiki/index.md"],
      #|  "active_memory": [],
      #|  "user_memory": [],
      #|  "working_memory": [],
      #|  "memory_summary": "",
      #|  "output_contract": ["Return strict JSON"]
      #|}
      #|EOF
      #|elif [ "$subcommand" = "persist" ]; then
      #|  cat <<EOF
      #|{
      #|  "log_path": "wiki/log.md",
      #|  "updated_pages": ["wiki/index.md", "wiki/sources/demo.md"],
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
async test "parse_external_proposal_packet_json accepts keeper-style packet" {
  let packet = match
    parse_external_proposal_packet_json({
      "source_id": "keeper-1",
      "title": "Ingest source into wiki",
      "summary": "Review the source and update relevant pages.",
      "request": "Run the skill-driven wiki ingest revision pass.",
      "profile": "wiki_ingest_controller",
      "output_contract": "keeper.plan.packet.v1",
      "source_path": "/tmp/moonbook-confirm-check/raw/confirm-demo.md",
      "source_page": "wiki/sources/confirm-demo.md",
      "context_pages": ["wiki/index.md", "wiki/log.md"],
      "related_pages": ["wiki/entities/demo.md"],
      "skill_paths": ["skills/wiki-maintainer/SKILL.md"],
      "notes": ["Prefer concise citations."],
      "metadata": { "book": "research" },
    }) {
    Ok(packet) => packet
    Err(error) => fail(error)
  }
  inspect(packet.profile, content="wiki_ingest_controller")
  inspect(
    packet.request_text,
    content="Run the skill-driven wiki ingest revision pass.",
  )
  inspect(packet.context_pages.join(","), content="wiki/index.md,wiki/log.md")
  inspect(packet.related_pages.join(","), content="wiki/entities/demo.md")
  inspect(
    packet.output_contract.map(fn(value) { value.stringify() }).unwrap_or(""),
    content="\"keeper.plan.packet.v1\"",
  )
}

///|
async test "parse_external_proposal_packet_json rejects missing packet contract fields" {
  let missing_context_error = match
    parse_external_proposal_packet_json({
      "request": "Ingest source into wiki",
      "profile": "wiki_ingest_controller",
      "skill_paths": ["skills/wiki-maintainer/SKILL.md"],
      "output_contract": "keeper.plan.packet.v1",
    }) {
    Ok(_) => ""
    Err(error) => error
  }
  inspect(
    missing_context_error.contains("missing context_pages"),
    content="true",
  )
  let empty_skill_error = match
    parse_external_proposal_packet_json({
      "request": "Ingest source into wiki",
      "profile": "wiki_ingest_controller",
      "context_pages": ["wiki/index.md"],
      "skill_paths": [],
      "output_contract": "keeper.plan.packet.v1",
    }) {
    Ok(_) => ""
    Err(error) => error
  }
  inspect(
    empty_skill_error.contains("skill_paths must not be empty"),
    content="true",
  )
  let blank_output_contract_error = match
    parse_external_proposal_packet_json({
      "request": "Ingest source into wiki",
      "profile": "wiki_ingest_controller",
      "context_pages": ["wiki/index.md"],
      "skill_paths": ["skills/wiki-maintainer/SKILL.md"],
      "output_contract": "   ",
    }) {
    Ok(_) => ""
    Err(error) => error
  }
  inspect(
    blank_output_contract_error.contains("output_contract must be non-blank"),
    content="true",
  )
}

///|
async test "GatewayJobApp imports external proposal packet into proposal store" {
  @fsx.with_temporary_directory("job-external-import-XXXXXX", async fn(dir) {
    @fsx.write_to_file(
      @pathx.join(dir, "moonclaw.jobs.json"),
      sample_external_profile_json().stringify(),
    )
    let workspace = @workspace.WorkspaceRuntime::new(home=dir, cwd=dir)
    let app = GatewayJobApp::new(
      root=@pathx.join(dir, "jobs"),
      cwd=dir,
      home=dir,
      workspace~,
      next_id=fn() { "packet-next" },
      now=fn() { 200 },
    )
    app.load()
    let result = app.import_external_proposal_packet(
      ExternalProposalPacket::{
        packet_id: Some("keeper-1"),
        title: Some("Ingest source into wiki"),
        summary: Some("Review the source and update relevant pages."),
        request_text: "Ingest source into wiki and revise the relevant pages.",
        profile: "wiki_ingest_controller",
        output_contract: Some({ "artifact": "wiki/report.md" }),
        source_path: Some("/tmp/book/raw/demo.md"),
        source_page: Some("wiki/sources/demo.md"),
        context_pages: ["wiki/index.md"],
        related_pages: ["wiki/entities/demo.md"],
        skill_paths: ["skills/wiki-maintainer/SKILL.md"],
        notes: ["Prefer concise citations."],
        tags: ["keeper"],
        metadata: {
          "book": "research",
          "disable_waiting_for_input": true,
          "best_effort_on_missing_input": true,
          "profile_metadata": {
            "disable_waiting_for_input": true,
            "best_effort_on_missing_input": true,
          },
          "step_metadata": {
            "disable_waiting_for_input": true,
            "best_effort_on_missing_input": true,
          },
        },
      },
      "/tmp/book/keeper/jobs/ingest-1.json",
    )
    let imported = match result {
      Ok(imported) => imported
      Err(error) => fail(error)
    }
    inspect(imported.proposal.status.to_json().stringify(), content="\"Draft\"")
    inspect(
      imported.proposal.profile_id.unwrap_or(""),
      content="wiki_ingest_controller",
    )
    inspect(
      imported.proposal.profile_metadata
      .stringify()
      .contains("\"workspace_root\":\"/tmp/book\""),
      content="true",
    )
    inspect(
      imported.proposal.profile_metadata
      .stringify()
      .contains("\"disable_waiting_for_input\":true"),
      content="true",
    )
    inspect(
      imported.proposal.profile_metadata
      .stringify()
      .contains("\"best_effort_on_missing_input\":true"),
      content="true",
    )
    inspect(
      proposal_initial_input(imported.proposal)
      .map(fn(json) { json.stringify() })
      .unwrap_or("")
      .contains("\"context_pages\":[\"/tmp/book/wiki/index.md\"]"),
      content="true",
    )
    inspect(
      imported.proposal.steps[0].metadata
      .stringify()
      .contains(
        "\"skill_paths\":[\"/tmp/book/skills/wiki-maintainer/SKILL.md\"]",
      ),
      content="true",
    )
    inspect(
      imported.proposal.steps[0].metadata
      .stringify()
      .contains(
        "\"external_output_contract\":{\"artifact\":\"wiki/report.md\"}",
      ),
      content="true",
    )
    inspect(
      imported.proposal.steps[0].metadata
      .stringify()
      .contains("\"disable_waiting_for_input\":true"),
      content="true",
    )
    inspect(
      imported.proposal.steps[0].metadata
      .stringify()
      .contains("\"best_effort_on_missing_input\":true"),
      content="true",
    )
    inspect(
      app.runtime().store().get_job_proposal(imported.proposal.id) is Some(_),
      content="true",
    )
  })
}

///|
async test "GatewayJobApp imports and confirms external proposal packet" {
  @fsx.with_temporary_directory("job-external-confirm-XXXXXX", async fn(dir) {
    let provider_script = @pathx.join(dir, "provider_task.sh")
    @fsx.write_to_file(
      @pathx.join(dir, "moonclaw.jobs.json"),
      sample_external_profile_json().stringify(),
    )
    write_external_packet_provider_fixture(dir, provider_script)
    let workspace = @workspace.WorkspaceRuntime::new(home=dir, cwd=dir)
    let app = GatewayJobApp::new(
      root=@pathx.join(dir, "jobs"),
      cwd=dir,
      home=dir,
      workspace~,
      next_id=fn() { "packet-confirm" },
      now=fn() { 300 },
    )
    app.load()
    let result = app.import_external_proposal_packet(
      ExternalProposalPacket::{
        packet_id: Some("keeper-2"),
        title: Some("Ingest source into wiki"),
        summary: Some("Review the source and update relevant pages."),
        request_text: "Ingest source into wiki and revise the relevant pages.",
        profile: "wiki_ingest_controller",
        output_contract: Some({ "artifact": "wiki/report.md" }),
        source_path: Some("/tmp/book/raw/demo.md"),
        source_page: Some("wiki/sources/demo.md"),
        context_pages: ["wiki/index.md"],
        related_pages: ["wiki/entities/demo.md"],
        skill_paths: ["skills/wiki-maintainer/SKILL.md"],
        notes: ["Prefer concise citations."],
        tags: [],
        metadata: {},
      },
      "/tmp/book/keeper/jobs/ingest-2.json",
      confirm=true,
      analysis_executor=Some(
        AnalysisExecutor::new(run=fn(_request) {
          Ok(AnalysisExecution::{
            model_name: "mock",
            content: (
              #|{
              #|  "task_id": "task-1",
              #|  "summary": "Imported packet executed successfully.",
              #|  "artifacts": ["wiki/report.md"],
              #|  "memory_candidates": [],
              #|  "requires_review": false,
              #|  "notify_town": false
              #|}
            ),
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
      ),
    )
    let imported = match result {
      Ok(imported) => imported
      Err(error) => fail(error)
    }
    inspect(imported.confirm_result is Some(_), content="true")
    inspect(
      imported.proposal.status.to_json().stringify(),
      content="\"Confirmed\"",
    )
    inspect(
      imported.confirm_result
      .map(fn(result) { result.run.status.to_json().stringify() })
      .unwrap_or(""),
      content="\"Succeeded\"",
    )
    inspect(
      imported.proposal.steps[0].metadata
      .stringify()
      .contains(
        "\"external_output_contract\":{\"artifact\":\"wiki/report.md\"}",
      ),
      content="true",
    )
    inspect(
      proposal_initial_input(imported.proposal)
      .map(fn(json) { json.stringify() })
      .unwrap_or("")
      .contains("\"external_workspace_root\":\"/tmp/book\""),
      content="true",
    )
  })
}

///|
async test "GatewayJobApp confirms external proposal packet with detached launch" {
  @fsx.with_temporary_directory("job-external-detached-confirm-XXXXXX", async fn(
    dir,
  ) {
    @fsx.write_to_file(
      @pathx.join(dir, "moonclaw.jobs.json"),
      sample_external_profile_json().stringify(),
    )
    let workspace = @workspace.WorkspaceRuntime::new(home=dir, cwd=dir)
    let app = GatewayJobApp::new(
      root=@pathx.join(dir, "jobs"),
      cwd=dir,
      home=dir,
      workspace~,
      next_id=fn() { "packet-detached" },
      now=fn() { 400 },
    )
    app.load()
    let imported = match
      app.import_external_proposal_packet(
        ExternalProposalPacket::{
          packet_id: Some("keeper-3"),
          title: Some("Ingest source into wiki"),
          summary: Some("Review the source and update relevant pages."),
          request_text: "Ingest source into wiki and revise the relevant pages.",
          profile: "wiki_ingest_controller",
          output_contract: Some({ "artifact": "wiki/report.md" }),
          source_path: Some("/tmp/book/raw/demo.md"),
          source_page: Some("wiki/sources/demo.md"),
          context_pages: ["wiki/index.md"],
          related_pages: ["wiki/entities/demo.md"],
          skill_paths: ["skills/wiki-maintainer/SKILL.md"],
          notes: ["Prefer concise citations."],
          tags: [],
          metadata: {},
        },
        "/tmp/book/keeper/jobs/ingest-3.json",
      ) {
      Ok(imported) => imported
      Err(error) => fail(error)
    }
    let captured_exec : Ref[String] = { val: "" }
    let captured_args : Ref[Array[String]] = { val: [] }
    let confirmed = match
      app.confirm_proposal_and_launch(imported.proposal, imported.proposal.id, spawn_runner=fn(
        exec_path,
        args,
      ) {
        captured_exec.val = exec_path
        captured_args.val = args
      }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(confirmed.run.status.to_json().stringify(), content="\"Pending\"")
    inspect(captured_exec.val.is_blank(), content="false")
    inspect(
      captured_args.val.join(" ").contains("proposal run \{confirmed.run.id}"),
      content="true",
    )
    inspect(captured_args.val.contains("--initial-input-file"), content="true")
    inspect(
      app
      .runtime()
      .store()
      .get_job_proposal(imported.proposal.id)
      .map(fn(saved) { saved.status.to_json().stringify() })
      .unwrap_or(""),
      content="\"Confirmed\"",
    )
  })
}

///|
async test "GatewayJobApp restores missing detached run definition from confirmed proposal" {
  @fsx.with_temporary_directory("job-external-run-restore-XXXXXX", async fn(
    dir,
  ) {
    @fsx.write_to_file(
      @pathx.join(dir, "moonclaw.jobs.json"),
      (
        {
          "jobs": {
            "profiles": {
              "simple_external": {
                "family": "simple_external",
                "role": "worker",
                "steps": [
                  {
                    "id": "execute",
                    "title": "Execute imported packet",
                    "kind": "job.analysis",
                    "prompt_template": "Execute ${request}",
                  },
                ],
              },
            },
          },
        } : Json).stringify(),
    )
    let workspace = @workspace.WorkspaceRuntime::new(home=dir, cwd=dir)
    let app = GatewayJobApp::new(
      root=@pathx.join(dir, "jobs"),
      cwd=dir,
      home=dir,
      workspace~,
      next_id=fn() { "packet-restore" },
      now=fn() { 500 },
    )
    app.load()
    let imported = match
      app.import_external_proposal_packet(
        ExternalProposalPacket::{
          packet_id: Some("keeper-restore"),
          title: Some("Ingest source into wiki"),
          summary: Some("Review the source and update relevant pages."),
          request_text: "Ingest source into wiki and revise the relevant pages.",
          profile: "simple_external",
          output_contract: Some({ "artifact": "wiki/report.md" }),
          source_path: Some("/tmp/book/raw/demo.md"),
          source_page: Some("wiki/sources/demo.md"),
          context_pages: ["wiki/index.md"],
          related_pages: ["wiki/entities/demo.md"],
          skill_paths: ["skills/wiki-maintainer/SKILL.md"],
          notes: ["Prefer concise citations."],
          tags: [],
          metadata: {},
        },
        "/tmp/book/keeper/jobs/ingest-restore.json",
      ) {
      Ok(imported) => imported
      Err(error) => fail(error)
    }
    let confirmed = match
      app.confirm_proposal_and_launch(imported.proposal, imported.proposal.id, spawn_runner=fn(
        _exec_path,
        _args,
      ) {
        ()
      }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    @fsx.write_to_file(
      @pathx.join(@pathx.join(dir, "jobs"), "definitions.json"),
      ({ "definitions": [], "workflows": [] } : Json).stringify(),
    )

    let reloaded = GatewayJobApp::new(
      root=@pathx.join(dir, "jobs"),
      cwd=dir,
      home=dir,
      workspace~,
      next_id=fn() { "packet-restore-reloaded" },
      now=fn() { 600 },
    )
    reloaded.load()
    inspect(
      reloaded
      .runtime()
      .store()
      .get_definition(confirmed.compilation.definition.id)
      is None,
      content="true",
    )
    let result = reloaded.execute_existing_run(
      confirmed.run.id,
      analysis_executor=Some(
        AnalysisExecutor::new(run=fn(_request) {
          Ok(AnalysisExecution::{
            model_name: "mock",
            content: "Restored definition executed.",
            conversation_id: None,
            usage: None,
            metadata: {},
          })
        }),
      ),
    )
    let run = match result {
      Ok(run) => run
      Err(error) => fail(error)
    }
    inspect(run.status.to_json().stringify(), content="\"Succeeded\"")
    inspect(
      reloaded
      .runtime()
      .store()
      .get_definition(confirmed.compilation.definition.id)
      is Some(_),
      content="true",
    )
  })
}
