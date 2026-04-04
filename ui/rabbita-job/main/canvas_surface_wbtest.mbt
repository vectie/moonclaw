///|
fn test_ui_run() -> UiRun {
  UiRun::{
    id: "run-1",
    job_id: "job-1",
    status: "\"Running\"",
    workspace_dir: None,
    summary: None,
    error: None,
  }
}

///|
fn test_canvas_snapshot(nodes : Array[UiNode]) -> UiSnapshot {
  UiSnapshot::{
    run: test_ui_run(),
    workspace_dir: None,
    current_step_id: Some("step-a"),
    artifacts: [],
    memories: [],
    linked_remote: [],
    handoffs: [],
    nodes,
    timeline: [],
  }
}

///|
test "project_canvas_nodes places step outputs inline to the right of the step" {
  let snapshot = test_canvas_snapshot([
    UiNode::{
      id: "workflow:run-1",
      parent_id: None,
      kind: "Workflow",
      title: "generic",
      status: "\"Running\"",
      summary: None,
      detail: None,
      run_id: Some("run-1"),
      step_id: None,
      artifact_id: None,
      memory_id: None,
      metadata: {},
      provisional: false,
    },
    UiNode::{
      id: "step:run-1:step-a",
      parent_id: Some("workflow:run-1"),
      kind: "Step",
      title: "step-a",
      status: "\"Succeeded\"",
      summary: Some("analysis complete"),
      detail: Some("job.analysis"),
      run_id: Some("run-1"),
      step_id: Some("step-a"),
      artifact_id: None,
      memory_id: None,
      metadata: {},
      provisional: false,
    },
    UiNode::{
      id: "artifact:report",
      parent_id: Some("step:run-1:step-a"),
      kind: "Artifact",
      title: "report",
      status: "\"Active\"",
      summary: Some("/tmp/report.md"),
      detail: Some("analysis.report"),
      run_id: Some("run-1"),
      step_id: Some("step-a"),
      artifact_id: Some("artifact:report"),
      memory_id: None,
      metadata: {},
      provisional: false,
    },
    UiNode::{
      id: "artifact:result",
      parent_id: Some("step:run-1:step-a"),
      kind: "Artifact",
      title: "result",
      status: "\"Active\"",
      summary: Some("/tmp/result.json"),
      detail: Some("analysis.result"),
      run_id: Some("run-1"),
      step_id: Some("step-a"),
      artifact_id: Some("artifact:result"),
      memory_id: None,
      metadata: {},
      provisional: false,
    },
    UiNode::{
      id: "memory:report",
      parent_id: Some("step:run-1:step-a"),
      kind: "Memory",
      title: "Job report: run-1:step-a",
      status: "\"Active\"",
      summary: Some("memory copy"),
      detail: Some("job.report"),
      run_id: Some("run-1"),
      step_id: Some("step-a"),
      artifact_id: Some("artifact:report"),
      memory_id: Some("memory:report"),
      metadata: {},
      provisional: false,
    },
    UiNode::{
      id: "step:run-1:step-b",
      parent_id: Some("workflow:run-1"),
      kind: "Step",
      title: "step-b",
      status: "\"Pending\"",
      summary: None,
      detail: Some("job.analysis"),
      run_id: Some("run-1"),
      step_id: Some("step-b"),
      artifact_id: None,
      memory_id: None,
      metadata: {},
      provisional: false,
    },
  ])

  let layouts = project_canvas_nodes(snapshot)
  let workflow = canvas_layout_for_id(layouts, "workflow:run-1").unwrap()
  let step_a = canvas_layout_for_id(layouts, "step:run-1:step-a").unwrap()
  let report = canvas_layout_for_id(layouts, "artifact:report").unwrap()
  let result = canvas_layout_for_id(layouts, "artifact:result").unwrap()
  let report_memory = canvas_layout_for_id(layouts, "memory:report").unwrap()
  let step_b = canvas_layout_for_id(layouts, "step:run-1:step-b").unwrap()

  inspect(step_a.x > workflow.x, content="true")
  inspect(report.x > step_a.x, content="true")
  inspect(result.x == report.x, content="true")
  inspect(report_memory.x == report.x, content="true")
  inspect(report.y >= step_a.y, content="true")
  inspect(report.y < step_b.y, content="true")
  inspect(result.y > report.y, content="true")
  inspect(report_memory.y >= step_a.y, content="true")
  inspect(report_memory.y < step_b.y, content="true")
  inspect(step_b.y > report_memory.y, content="true")
}
