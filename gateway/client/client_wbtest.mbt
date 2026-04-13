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
        memory_hits: [],
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
    parent_run_id: None,
    parent_step_id: None,
    depth: 0,
    workspace_dir: None,
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
  let job_ui_snapshot_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-job-ui",
    ok: true,
    payload: Some({
      "snapshot": @job.JobUiSnapshot::{
        run: job_run,
        definition: job,
        workflow: None,
        proposal: None,
        workspace_dir: Some("/tmp/workspace"),
        current_step_id: Some("step-a"),
        child_runs: [],
        artifacts: [],
        memories: [],
        linked_remote: [],
        handoffs: [],
        nodes: [
          @job.JobUiNode::{
            id: "workflow:job-run-1",
            parent_id: None,
            kind: @job.JobUiNodeKind::Workflow,
            title: "analysis",
            status: "\"Running\"",
            summary: None,
            detail: None,
            run_id: Some("job-run-1"),
            step_id: None,
            artifact_id: None,
            memory_id: None,
            created_at: Some(10),
            updated_at: Some(10),
            provisional: false,
            metadata: {},
          },
        ],
        timeline: [],
      }.to_json(),
    }),
    error: None,
  })
  let job_ui_events_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-job-ui-events",
    ok: true,
    payload: Some({
      "timeline": [
        @job.JobUiTimelineEntry::{
          id: "job-run-1:event:0",
          run_id: "job-run-1",
          event_type: "step.started",
          title: "step.started (step-a)",
          detail: "started",
          timestamp: 11,
          step_id: Some("step-a"),
          status: Some("\"Running\""),
          data: {},
        }.to_json(),
      ],
    }),
    error: None,
  })
  let memory = @job.MemoryRecord::{
    id: "memory-1",
    kind: "note",
    title: Some("workspace note"),
    content: "Track VLA papers daily.",
    metadata: {},
    tags: ["research"],
    scope: ["workspace:main", "research"],
    workspace: Some("/tmp/workspace"),
    agent_id: Some("main"),
    channel_id: Some("feishu"),
    account_id: Some("default"),
    recipient: Some("chat-1"),
    thread_id: None,
    source_artifact_id: None,
    status: @job.MemoryStatus::Active,
    created_at: 1,
    updated_at: 1,
    archived_at: None,
  }
  let memory_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-memory",
    ok: true,
    payload: Some(memory.to_json()),
    error: None,
  })
  let memory_search_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-memory-search",
    ok: true,
    payload: Some({
      "hits": [
        @job.MemorySearchHit::{
          memory_id: "memory-1",
          kind: "note",
          title: Some("workspace note"),
          score: 2,
          snippet: "Track VLA papers daily.",
          tags: ["research"],
          scope: ["workspace:main", "research"],
          workspace: Some("/tmp/workspace"),
          channel_id: Some("feishu"),
          account_id: Some("default"),
          recipient: Some("chat-1"),
          thread_id: None,
        }.to_json(),
      ],
    }),
    error: None,
  })
  let workspace_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-workspace",
    ok: true,
    payload: Some({
      "workspace": {
        "root": "/tmp/workspace",
        "configured_from": "/tmp/moonclaw.json",
        "files": [],
        "prompt_context": "Workspace context",
      },
    }),
    error: None,
  })
  let plugins_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-plugins",
    ok: true,
    payload: Some({
      "plugins": [
        {
          "id": "feishu",
          "enabled": true,
          "status": "enabled",
          "source": "npm",
          "spec": "@openclaw/feishu",
          "version": "1.0.0",
          "install_path": "/tmp/plugin",
          "metadata": {},
        },
      ],
    }),
    error: None,
  })
  let acp_target : Json = {
    "id": "codex-main",
    "backend": "codex",
    "label": "Main Codex",
    "cwd": "/tmp/workspace",
    "workspace": "/tmp/workspace",
    "command": "codex",
    "args": ["exec"],
    "model": "gpt-5",
    "status": "ready",
    "metadata": {},
  }
  let acp_session : Json = {
    "id": "acp-session-1",
    "target_id": "codex-main",
    "session_key": "channel:feishu:chat-1",
    "status": "attached",
    "cwd": "/tmp/workspace",
    "workspace": "/tmp/workspace",
    "created_at": 1,
    "updated_at": 2,
    "metadata": {},
  }
  let acp_run : Json = {
    "id": "run-acp-1",
    "session_id": "acp-session-1",
    "session_key": "channel:feishu:chat-1",
    "target_id": "codex-main",
    "backend": "codex",
    "status": "running",
    "created_at": 3,
    "updated_at": 3,
    "request": { "message": "Review repo" },
    "plan": { "command": "codex" },
    "result": null,
    "error": "",
  }
  let acp_targets_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-acp-targets",
    ok: true,
    payload: Some({ "targets": [acp_target] }),
    error: None,
  })
  let acp_target_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-acp-target",
    ok: true,
    payload: Some({ "target": acp_target }),
    error: None,
  })
  let acp_sessions_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-acp-sessions",
    ok: true,
    payload: Some({ "sessions": [acp_session] }),
    error: None,
  })
  let acp_session_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-acp-session",
    ok: true,
    payload: Some({ "session": acp_session }),
    error: None,
  })
  let acp_session_mutation_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-acp-session-mutation",
    ok: true,
    payload: Some({ "status": "attached", "session": acp_session }),
    error: None,
  })
  let acp_session_run_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-acp-session-run",
    ok: true,
    payload: Some({
      "status": "accepted",
      "session": {
        "id": "acp-session-1",
        "target_id": "codex-main",
        "session_key": "channel:feishu:chat-1",
        "status": "running",
        "cwd": "/tmp/workspace",
        "workspace": "/tmp/workspace",
        "created_at": 1,
        "updated_at": 3,
        "metadata": {},
      },
      "run": acp_run,
      "accepted": {
        "run_id": "run-acp-1",
        "status": "accepted",
        "accepted_at": 3,
      },
      "target": acp_target,
      "plan": {
        "backend": "codex",
        "target_id": "codex-main",
        "session_id": "acp-session-1",
        "session_key": "channel:feishu:chat-1",
        "cwd": "/tmp/workspace",
        "workspace": "/tmp/workspace",
        "command": "codex",
        "args": ["exec"],
        "model": "gpt-5",
        "env": {
          "ACP_TARGET_ID": "codex-main",
          "ACP_SESSION_ID": "acp-session-1",
          "ACP_SESSION_KEY": "channel:feishu:chat-1",
          "ACP_BACKEND": "codex",
          "ACP_WORKSPACE": "/tmp/workspace",
          "ACP_MODEL": "gpt-5",
        },
        "metadata": {},
      },
    }),
    error: None,
  })
  let acp_runs_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-acp-runs",
    ok: true,
    payload: Some({ "runs": [acp_run] }),
    error: None,
  })
  let acp_run_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-acp-run",
    ok: true,
    payload: Some({ "run": acp_run }),
    error: None,
  })
  let acp_ui_snapshot_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-acp-ui",
    ok: true,
    payload: Some({
      "snapshot": {
        "targets": [acp_target],
        "sessions": [acp_session],
        "runs": [acp_run],
        "nodes": [
          {
            "id": "target:codex-main",
            "parent_id": "",
            "kind": "Target",
            "title": "Main Codex",
            "status": "ready",
            "summary": "codex",
            "detail": "/tmp/workspace",
            "target_id": "codex-main",
            "session_id": "",
            "run_id": "",
            "created_at": 0,
            "updated_at": 0,
            "metadata": {},
          },
        ],
        "timeline": [
          {
            "id": "run:run-acp-1",
            "event_type": "run.running",
            "title": "Run running",
            "detail": "Review repo",
            "timestamp": 3,
            "target_id": "codex-main",
            "session_id": "acp-session-1",
            "run_id": "run-acp-1",
            "status": "running",
            "data": {},
          },
        ],
      },
    }),
    error: None,
  })
  let acp_ui_events_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-acp-ui-events",
    ok: true,
    payload: Some({
      "timeline": [
        {
          "id": "run:run-acp-1",
          "event_type": "run.running",
          "title": "Run running",
          "detail": "Review repo",
          "timestamp": 3,
          "target_id": "codex-main",
          "session_id": "acp-session-1",
          "run_id": "run-acp-1",
          "status": "running",
          "data": {},
        },
      ],
    }),
    error: None,
  })
  let acp_run_cancel_response : Result[@protocol.Response, String] = Ok(@protocol.Response::{
    id: "req-acp-run-cancel",
    ok: true,
    payload: Some({
      "status": "cancelling",
      "run": {
        "id": "run-acp-1",
        "session_id": "acp-session-1",
        "session_key": "channel:feishu:chat-1",
        "target_id": "codex-main",
        "backend": "codex",
        "status": "cancelling",
        "created_at": 3,
        "updated_at": 4,
        "request": { "message": "Review repo" },
        "plan": { "command": "codex" },
        "result": null,
        "error": "ACP run cancellation requested.",
      },
    }),
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
  let memory_result : Result[@job.MemoryRecord, String] = decode_ok_payload(
    memory_response, "default", "missing", "parse failed",
  )
  let job_ui_snapshot_result : Result[JobUiSnapshotPayload, String] = decode_ok_payload(
    job_ui_snapshot_response, "default", "missing", "parse failed",
  )
  let job_ui_events_result : Result[JobUiEventsPayload, String] = decode_ok_payload(
    job_ui_events_response, "default", "missing", "parse failed",
  )
  let memory_search_result : Result[MemorySearchPayload, String] = decode_ok_payload(
    memory_search_response, "default", "missing", "parse failed",
  )
  let workspace_result : Result[WorkspacePayload, String] = decode_ok_payload(
    workspace_response, "default", "missing", "parse failed",
  )
  let plugins_result : Result[PluginsListPayload, String] = decode_ok_payload(
    plugins_response, "default", "missing", "parse failed",
  )
  let acp_targets_result : Result[AcpTargetsPayload, String] = decode_ok_payload(
    acp_targets_response, "default", "missing", "parse failed",
  )
  let acp_target_result : Result[AcpTargetPayload, String] = decode_ok_payload(
    acp_target_response, "default", "missing", "parse failed",
  )
  let acp_sessions_result : Result[AcpSessionsPayload, String] = decode_ok_payload(
    acp_sessions_response, "default", "missing", "parse failed",
  )
  let acp_session_result : Result[AcpSessionPayload, String] = decode_ok_payload(
    acp_session_response, "default", "missing", "parse failed",
  )
  let acp_session_mutation_result : Result[AcpSessionMutationPayload, String] = decode_ok_payload(
    acp_session_mutation_response, "default", "missing", "parse failed",
  )
  let acp_session_run_result : Result[AcpSessionRunPayload, String] = decode_ok_payload(
    acp_session_run_response, "default", "missing", "parse failed",
  )
  let acp_runs_result : Result[AcpRunsPayload, String] = decode_ok_payload(
    acp_runs_response, "default", "missing", "parse failed",
  )
  let acp_run_result : Result[AcpRunPayload, String] = decode_ok_payload(
    acp_run_response, "default", "missing", "parse failed",
  )
  let acp_run_cancel_result : Result[AcpRunMutationPayload, String] = decode_ok_payload(
    acp_run_cancel_response, "default", "missing", "parse failed",
  )
  let acp_ui_snapshot_result : Result[AcpUiSnapshotPayload, String] = decode_ok_payload(
    acp_ui_snapshot_response, "default", "missing", "parse failed",
  )
  let acp_ui_events_result : Result[AcpUiEventsPayload, String] = decode_ok_payload(
    acp_ui_events_response, "default", "missing", "parse failed",
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
  let memory_payload : @job.MemoryRecord = match memory_result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let job_ui_snapshot_payload : JobUiSnapshotPayload = match
    job_ui_snapshot_result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let job_ui_events_payload : JobUiEventsPayload = match job_ui_events_result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let memory_search_payload : MemorySearchPayload = match memory_search_result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let workspace_payload : WorkspacePayload = match workspace_result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let plugins_payload : PluginsListPayload = match plugins_result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let acp_targets_payload : AcpTargetsPayload = match acp_targets_result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let acp_target_payload : AcpTargetPayload = match acp_target_result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let acp_sessions_payload : AcpSessionsPayload = match acp_sessions_result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let acp_session_payload : AcpSessionPayload = match acp_session_result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let acp_session_mutation_payload : AcpSessionMutationPayload = match
    acp_session_mutation_result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let acp_session_run_payload : AcpSessionRunPayload = match
    acp_session_run_result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let acp_runs_payload : AcpRunsPayload = match acp_runs_result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let acp_run_payload : AcpRunPayload = match acp_run_result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let acp_run_cancel_payload : AcpRunMutationPayload = match
    acp_run_cancel_result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let acp_ui_snapshot_payload : AcpUiSnapshotPayload = match
    acp_ui_snapshot_result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let acp_ui_events_payload : AcpUiEventsPayload = match acp_ui_events_result {
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
  inspect(
    job_ui_snapshot_payload.snapshot.current_step_id.unwrap_or(""),
    content="step-a",
  )
  inspect(job_ui_events_payload.timeline[0].event_type, content="step.started")
  inspect(memory_payload.id, content="memory-1")
  inspect(memory_search_payload.hits[0].memory_id, content="memory-1")
  inspect(workspace_payload.workspace.root, content="/tmp/workspace")
  inspect(plugins_payload.plugins[0].id, content="feishu")
  inspect(acp_targets_payload.targets[0].id, content="codex-main")
  inspect(acp_target_payload.target.backend, content="codex")
  inspect(
    acp_sessions_payload.sessions[0].session_key,
    content="channel:feishu:chat-1",
  )
  inspect(acp_session_payload.session.id, content="acp-session-1")
  inspect(acp_session_mutation_payload.status, content="attached")
  inspect(acp_session_run_payload.accepted.run_id, content="run-acp-1")
  inspect(acp_session_run_payload.run.id, content="run-acp-1")
  inspect(acp_session_run_payload.session.status, content="running")
  inspect(acp_session_run_payload.plan.command.unwrap_or(""), content="codex")
  inspect(acp_runs_payload.runs[0].id, content="run-acp-1")
  inspect(acp_run_payload.run.backend, content="codex")
  inspect(acp_run_cancel_payload.status, content="cancelling")
  inspect(acp_run_cancel_payload.run.status, content="cancelling")
  inspect(
    acp_ui_snapshot_payload.snapshot.nodes[0].id,
    content="target:codex-main",
  )
  inspect(acp_ui_events_payload.timeline[0].event_type, content="run.running")
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
