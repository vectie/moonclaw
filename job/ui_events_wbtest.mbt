///|
test "run_events_as_timeline sorts and maps events" {
  let timeline = run_events_as_timeline([
    JobRunEvent::{
      run_id: "run-1",
      job_id: "job-1",
      event_type: "job.completed",
      timestamp: 200,
      step_id: None,
      status: Some(Succeeded),
      message: "done",
      data: {},
    },
    JobRunEvent::{
      run_id: "run-1",
      job_id: "job-1",
      event_type: "step.started",
      timestamp: 100,
      step_id: Some("step-a"),
      status: Some(Running),
      message: "started",
      data: {},
    },
  ])
  json_inspect(timeline.map(fn(item) { item.title }), content=[
    "step.started (step-a)", "job.completed",
  ])
}
