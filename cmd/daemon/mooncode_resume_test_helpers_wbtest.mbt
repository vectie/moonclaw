///|
fn mooncode_runtime_continuation_is_active(checkpoint : Json) -> Bool {
  mooncode_runtime_resume_point(checkpoint) is Some(ResumeTools(_))
}

///|
fn mooncode_runtime_planner_continuation_is_active(checkpoint : Json) -> Bool {
  mooncode_runtime_resume_point(checkpoint) is Some(ResumePlanner(_))
}

///|
fn mooncode_runtime_planner_transport_continuation_is_active(
  checkpoint : Json,
) -> Bool {
  mooncode_runtime_resume_point(checkpoint) is Some(ResumeTransport(_, _))
}

///|
fn mooncode_runtime_planner_replan_continuation_is_active(
  checkpoint : Json,
) -> Bool {
  mooncode_runtime_resume_point(checkpoint) is Some(ResumeReplan(_))
}
