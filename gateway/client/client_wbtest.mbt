///|
test "decode_ok_payload parses run and channel payloads" {
  let runs_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-runs",
    ok: true,
    payload: Some({
      "runs": [
        {
          "run_id": "run-1",
          "session_key": "direct:default",
          "status": "completed",
          "created_at": 1,
          "completed_at": 2,
          "result": { "content": "done" },
          "error": {
            "code": "none",
            "message": "",
            "details": {},
            "retryable": false,
            "retry_after_ms": 0,
          },
        },
      ],
    }),
    error: None,
  })
  let channel_dock = @channel.ChannelDock::{
    id: "feishu",
    meta: @channel.ChannelMeta::{
      id: "feishu",
      label: "Feishu",
      selection_label: "Feishu/Lark",
      docs_path: "/channels/feishu",
      docs_label: Some("feishu"),
      blurb: "Feishu/Lark",
      order: Some(70),
      aliases: ["lark"],
    },
    capabilities: @channel.default_capabilities(),
    is_configured: true,
    is_running: true,
    account_ids: ["default"],
    outbound: None,
    streaming: None,
  }
  let channels_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-channels",
    ok: true,
    payload: Some({ "channels": [channel_dock.to_json()] }),
    error: None,
  })
  let ask_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-ask",
    ok: true,
    payload: Some(
      @job.ChatAnswer::{
        binding_id: Some("binding-paper"),
        question: "What changed?",
        answer: "Found 1 relevant artifact(s) for: What changed?",
        citations: [
          @job.ChatCitation::{
            artifact_id: "artifact-1",
            artifact_type: "paper.summary",
            logical_key: Some("paper:1"),
            snippet: "Diffusion transformers improve planning.",
            path: "/tmp/artifact-1.md",
            scope: ["research", "paper:1"],
          },
        ],
        hits: [
          @job.RetrievalHit::{
            artifact_id: "artifact-1",
            artifact_type: "paper.summary",
            logical_key: Some("paper:1"),
            score: 2,
            snippet: "Diffusion transformers improve planning.",
            path: "/tmp/artifact-1.md",
            scope: ["research", "paper:1"],
          },
        ],
      }.to_json(),
    ),
    error: None,
  })
  let job = @job.JobDefinition::{
    id: "job-1",
    kind: "analysis",
    enabled: true,
    config: {},
    schedule: None,
    retry_policy: None,
    workflow_id: Some("workflow-1"),
    created_at: 1,
    updated_at: 2,
    tags: ["research"],
  }
  let job_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-job",
    ok: true,
    payload: Some({ "job": job.to_json() }),
    error: None,
  })
  let job_run = @job.JobRun::{
    id: "job-run-1",
    job_id: "job-1",
    trigger: @job.TriggerSource::Manual,
    status: @job.RunStatus::Running,
    attempt: 1,
    retry_of: None,
    started_at: Some(10),
    completed_at: None,
    summary: None,
    error: None,
  }
  let job_run_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-job-run",
    ok: true,
    payload: Some({ "run": job_run.to_json(), "steps": [], "artifacts": [] }),
    error: None,
  })

  let runs_result : Result[RunsListPayload, String] = decode_ok_payload(
    runs_response, "default", "missing", "parse failed",
  )
  let runs : RunsListPayload = match runs_result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let channels_result : Result[ChannelsListPayload, String] = decode_ok_payload(
    channels_response, "default", "missing", "parse failed",
  )
  let channels : ChannelsListPayload = match channels_result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let ask_result : Result[@job.ChatAnswer, String] = decode_ok_payload(
    ask_response, "default", "missing", "parse failed",
  )
  let job_result : Result[JobPayload, String] = decode_ok_payload(
    job_response, "default", "missing", "parse failed",
  )
  let job_run_result : Result[JobRunDetails, String] = decode_ok_payload(
    job_run_response, "default", "missing", "parse failed",
  )
  let ask : @job.ChatAnswer = match ask_result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let job_payload : JobPayload = match job_result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let job_run_payload : JobRunDetails = match job_run_result {
    Ok(value) => value
    Err(error) => fail(error)
  }

  inspect(runs.runs.length(), content="1")
  inspect(runs.runs[0].run_id, content="run-1")
  inspect(channels.channels.length(), content="1")
  inspect(channels.channels[0].id, content="feishu")
  inspect(ask.binding_id.unwrap_or(""), content="binding-paper")
  inspect(ask.citations.length(), content="1")
  inspect(job_payload.job.id, content="job-1")
  inspect(job_run_payload.run.id, content="job-run-1")
}

///|
test "decode_ok_payload returns protocol and parsing errors" {
  let protocol_error : Result[@protocol.HealthPayload, String] = decode_ok_payload(
    Ok(@protocol.Response::{
      id: "req-health",
      ok: false,
      payload: None,
      error: Some(@protocol.ErrorShape::{
        code: "unauthorized",
        message: "Invalid token",
        details: None,
        retryable: None,
        retry_after_ms: None,
      }),
    }),
    "default",
    "missing",
    "parse failed",
  )
  let parse_error : Result[@protocol.HealthPayload, String] = decode_ok_payload(
    Ok(@protocol.Response::{
      id: "req-health",
      ok: true,
      payload: Some({ "status": "ok" }),
      error: None,
    }),
    "default",
    "missing",
    "parse failed",
  )

  inspect(
    match protocol_error {
      Err(error) => error
      Ok(_) => "unexpected-ok"
    },
    content="Invalid token",
  )
  inspect(
    match parse_error {
      Err(error) => error.contains("parse failed")
      Ok(_) => false
    },
    content="true",
  )
}
