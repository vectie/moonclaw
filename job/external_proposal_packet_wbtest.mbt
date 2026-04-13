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
async test "parse_external_proposal_packet_json accepts keeper-style packet" {
  let packet = match
    parse_external_proposal_packet_json({
      "source_id": "keeper-1",
      "title": "Ingest source into wiki",
      "summary": "Review the source and update relevant pages.",
      "request": "Run the skill-driven wiki ingest revision pass.",
      "profile": "wiki_ingest_controller",
      "output_contract": "keeper.plan.packet.v1",
      "context_pages": ["wiki/index.md", "wiki/log.md"],
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
        context_pages: ["wiki/index.md"],
        skill_paths: ["skills/wiki-maintainer/SKILL.md"],
        notes: ["Prefer concise citations."],
        tags: ["keeper"],
        metadata: { "book": "research" },
      },
      "/tmp/keeper/jobs/ingest-1.json",
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
      .contains("\"source_path\":\"/tmp/keeper/jobs/ingest-1.json\""),
      content="true",
    )
    inspect(
      proposal_initial_input(imported.proposal)
      .map(fn(json) { json.stringify() })
      .unwrap_or("")
      .contains("\"context_pages\":[\"wiki/index.md\"]"),
      content="true",
    )
    inspect(
      imported.proposal.steps[0].metadata
      .stringify()
      .contains("\"preferred_skills\":[\"wiki-maintainer\"]"),
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
      app.runtime().store().get_job_proposal(imported.proposal.id) is Some(_),
      content="true",
    )
  })
}

///|
async test "GatewayJobApp imports and confirms external proposal packet" {
  @fsx.with_temporary_directory("job-external-confirm-XXXXXX", async fn(dir) {
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
        context_pages: ["wiki/index.md"],
        skill_paths: ["skills/wiki-maintainer/SKILL.md"],
        notes: ["Prefer concise citations."],
        tags: [],
        metadata: {},
      },
      "/tmp/keeper/jobs/ingest-2.json",
      confirm=true,
      analysis_executor=Some(
        AnalysisExecutor::new(run=fn(_request) {
          Ok(AnalysisExecution::{
            model_name: "mock",
            content: "Imported packet executed successfully.",
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
  })
}
