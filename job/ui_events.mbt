///|
pub fn event_as_ui_timeline_entry(
  event : JobRunEvent,
  index : Int,
) -> JobUiTimelineEntry {
  JobUiTimelineEntry::{
    id: "\{event.run_id}:event:\{index}",
    run_id: event.run_id,
    event_type: event.event_type,
    title: match event.step_id {
      Some(step_id) => "\{event.event_type} (\{step_id})"
      None => event.event_type
    },
    detail: event.message,
    timestamp: event.timestamp,
    step_id: event.step_id,
    status: event.status.map(fn(status) { status.to_json().stringify() }),
    data: event.data,
  }
}

///|
pub fn run_events_as_timeline(
  events : Array[JobRunEvent],
) -> Array[JobUiTimelineEntry] {
  let sorted = events.copy()
  sorted.sort_by(fn(left, right) { left.timestamp.compare(right.timestamp) })
  let timeline : Array[JobUiTimelineEntry] = []
  for index in 0..<sorted.length() {
    timeline.push(event_as_ui_timeline_entry(sorted[index], index))
  }
  timeline
}

///|
pub async fn load_run_ui_timeline(
  store : SystemStore,
  run_id : String,
) -> Array[JobUiTimelineEntry] {
  run_events_as_timeline(store.list_run_events(run_id))
}
