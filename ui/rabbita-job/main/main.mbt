///|
using @html {
  article,
  button,
  div,
  h1,
  h2,
  h3,
  header,
  input,
  main_,
  nothing,
  p,
  section,
  span,
  textarea,
}

///|
using @rabbita {type Cmd, type Dispatch, type Html, batch}

///|

///|
fn status_class(status : String) -> String {
  let normalized = normalize_status(status)
  if normalized.contains("Running") {
    "status-badge running"
  } else if normalized.contains("Failed") {
    "status-badge failed"
  } else if normalized.contains("Pending") {
    "status-badge pending"
  } else {
    "status-badge"
  }
}

///|
fn run_status_is_live(status : String) -> Bool {
  let normalized = normalize_status(status)
  normalized.contains("Running") || normalized.contains("Pending")
}

///|
fn normalize_status(status : String) -> String {
  status.trim().replace(old="\"", new="").to_string()
}

///|
fn last_update_label(model : Model) -> String {
  match route_surface(model.route) {
    SurfaceJobs =>
      if model.timeline.is_empty() {
        "No events yet"
      } else {
        let entry = model.timeline[model.timeline.length() - 1]
        "Last event: \{entry.timestamp}"
      }
    SurfaceCowork =>
      match model.cowork_detail {
        Some(detail) =>
          match detail.messages {
            [.., last] => "Last message: \{last.timestamp}"
            _ => "Conversation ready"
          }
        None =>
          if model.cowork_sessions_loading {
            "Loading conversations"
          } else {
            "Conversation-first cowork surface"
          }
      }
    SurfaceAcp =>
      if model.acp_timeline.is_empty() {
        "No events yet"
      } else {
        let entry = model.acp_timeline[model.acp_timeline.length() - 1]
        "Last event: \{entry.timestamp}"
      }
    SurfaceOverview => "Local + remote operator view"
  }
}

///|
fn acp_status_is_live(status : String) -> Bool {
  let normalized = normalize_status(status)
  normalized.contains("Running") ||
  normalized.contains("Pending") ||
  normalized.contains("Cancelling") ||
  normalized.contains("Resetting") ||
  normalized.contains("Detaching")
}

///|
fn acp_snapshot_is_live(snapshot : AcpUiSnapshot) -> Bool {
  snapshot.nodes.any(fn(node) { acp_status_is_live(node.status) })
}

///|
fn render_live_chip(model : Model) -> Html {
  match route_surface(model.route) {
    SurfaceJobs =>
      match model.snapshot {
        Some(snapshot) =>
          if model.detail_loading && run_status_is_live(snapshot.run.status) {
            span(class="status-badge pending", "Refreshing")
          } else if run_status_is_live(snapshot.run.status) {
            span(class="status-badge running", "Live")
          } else {
            span(class="status-badge", "Static")
          }
        None =>
          if model.runs_loading {
            span(class="status-badge pending", "Loading")
          } else {
            span(class="status-badge", "Idle")
          }
      }
    SurfaceCowork =>
      match model.cowork_detail {
        Some(detail) =>
          if detail.session.has_plan_mode {
            span(class="status-badge pending", "Plan Mode")
          } else if detail.linked_run is Some(_) {
            span(class="status-badge running", "Linked Run")
          } else {
            span(class="status-badge", "Chat")
          }
        None =>
          if model.cowork_sessions_loading || model.cowork_detail_loading {
            span(class="status-badge pending", "Loading")
          } else {
            span(class="status-badge", "Cowork")
          }
      }
    SurfaceAcp =>
      match model.acp_snapshot {
        Some(snapshot) =>
          if model.acp_loading && acp_snapshot_is_live(snapshot) {
            span(class="status-badge pending", "Refreshing")
          } else if acp_snapshot_is_live(snapshot) {
            span(class="status-badge running", "Live")
          } else {
            span(class="status-badge", "Static")
          }
        None =>
          if model.acp_loading {
            span(class="status-badge pending", "Loading")
          } else {
            span(class="status-badge", "Idle")
          }
      }
    SurfaceOverview =>
      if model.runs_loading || model.acp_loading {
        span(class="status-badge pending", "Loading")
      } else {
        span(class="status-badge", "Overview")
      }
  }
}

///|

///|
fn contains_id(ids : Array[String], target : String) -> Bool {
  for id in ids {
    if id == target {
      return true
    }
  }
  false
}

///|
fn[T] fresh_ids_from(
  current : Array[T],
  previous_ids : Array[String],
  id_of : (T) -> String,
) -> Array[String] {
  let fresh : Array[String] = []
  for item in current {
    let id = id_of(item)
    if !contains_id(previous_ids, id) {
      fresh.push(id)
    }
  }
  fresh
}

///|
fn node_state_class(
  model : Model,
  snapshot : UiSnapshot,
  node : UiNode,
) -> String {
  let mut classes = "tree-node"
  if node.kind == "ChildRun" {
    classes = classes + " delegated"
  }
  if node.provisional {
    classes = classes + " provisional"
  }
  if snapshot.current_step_id == node.step_id {
    classes = classes + " active"
  }
  if normalize_status(node.status).contains("Failed") {
    classes = classes + " failed"
  }
  if contains_id(model.fresh_node_ids, node.id) {
    classes = classes + " fresh"
  }
  if model.focused_node_id == Some(node.id) {
    classes = classes + " focused"
  }
  classes
}

///|
fn render_status_badge(status : String) -> Html {
  span(class=status_class(status), normalize_status(status))
}

///|
fn render_meta_chip(label : String, value : String) -> Html {
  span(class="meta-chip", "\{label}: \{value}")
}

///|
fn render_action_chip(label : String, on_click : Cmd) -> Html {
  button(class="meta-chip meta-chip-button", on_click~, label)
}

///|
fn timeline_data_badges(entry : UiTimelineEntry) -> Array[Html] {
  let badges : Array[Html] = []
  match entry.data {
    { "attempt": Number(attempt, ..), .. } =>
      badges.push(render_meta_chip("attempt", attempt.to_string()))
    _ => ()
  }
  match entry.data {
    { "step_kind": String(step_kind), .. } =>
      badges.push(render_meta_chip("kind", step_kind))
    _ => ()
  }
  match entry.data {
    { "workflow_kind": String(workflow_kind), .. } =>
      badges.push(render_meta_chip("workflow", workflow_kind))
    _ => ()
  }
  match entry.data {
    { "step_count": Number(step_count, ..), .. } =>
      badges.push(render_meta_chip("steps", step_count.to_string()))
    _ => ()
  }
  match entry.data {
    { "metrics": Object(metrics), .. } if !metrics.is_empty() =>
      badges.push(render_meta_chip("metrics", metrics.length().to_string()))
    _ => ()
  }
  if entry.event_type.contains("artifact") {
    badges.push(render_meta_chip("output", "artifact"))
  }
  if entry.event_type.contains("memory") {
    badges.push(render_meta_chip("output", "memory"))
  }
  if entry.event_type.contains("workspace") {
    badges.push(render_meta_chip("output", "workspace"))
  }
  if entry.detail.contains("spawned") || entry.detail.contains("child run") {
    badges.push(render_meta_chip("branch", "child-run"))
  }
  badges
}

///|
fn preview_text(text : String, limit : Int) -> String {
  if text.length() <= limit {
    text
  } else {
    text[:limit].to_string() + "..."
  }
}

///|
fn panel_for_node(model : Model, node : UiNode) -> RightPanel {
  if node.artifact_id is Some(_) {
    Artifacts
  } else if node.memory_id is Some(_) {
    Memory
  } else {
    model.right_panel
  }
}

///|
fn node_title_for_step(snapshot : UiSnapshot, step_id : String) -> String {
  for node in snapshot.nodes {
    if node.step_id == Some(step_id) {
      return node.title
    }
  }
  step_id
}

///|
fn node_for_id(snapshot : UiSnapshot, node_id : String) -> UiNode? {
  for node in snapshot.nodes {
    if node.id == node_id {
      return Some(node)
    }
  }
  None
}

///|
fn node_id_for_entry(snapshot : UiSnapshot, entry : UiTimelineEntry) -> String? {
  match entry.step_id {
    Some(step_id) => {
      for node in snapshot.nodes {
        if node.step_id == Some(step_id) {
          return Some(node.id)
        }
      }
      None
    }
    None => {
      for node in snapshot.nodes {
        if node.run_id == Some(entry.run_id) && node.kind == "ChildRun" {
          return Some(node.id)
        }
      }
      for node in snapshot.nodes {
        if node.run_id == Some(entry.run_id) && node.kind == "Workflow" {
          return Some(node.id)
        }
      }
      None
    }
  }
}

///|
fn remote_linked_node_id(link : UiRemoteLink) -> String? {
  match link.metadata {
    { "linkage": { "linked_job_node_id": String(node_id), .. }, .. } =>
      Some(node_id)
    _ => None
  }
}

///|
fn remote_linked_step_id(link : UiRemoteLink) -> String? {
  match link.metadata {
    { "linkage": { "linked_job_step_id": String(step_id), .. }, .. } =>
      Some(step_id)
    _ => None
  }
}

///|
fn snapshot_handoff_for_node(
  snapshot : UiSnapshot,
  node : UiNode,
) -> UiHandoff? {
  for handoff in snapshot.handoffs {
    if handoff.node_id == node.id {
      return Some(handoff)
    }
  }
  None
}

///|
fn exact_remote_links_for_node(
  snapshot : UiSnapshot,
  node : UiNode,
) -> Array[UiRemoteLink] {
  match snapshot_handoff_for_node(snapshot, node) {
    Some(handoff) => return handoff.remote
    None => ()
  }
  snapshot.linked_remote.filter(fn(link) {
    if remote_linked_node_id(link) == Some(node.id) {
      true
    } else {
      match node.step_id {
        Some(step_id) => remote_linked_step_id(link) == Some(step_id)
        None => false
      }
    }
  })
}

///|
fn timeline_remote_badges(
  snapshot : UiSnapshot?,
  entry : UiTimelineEntry,
) -> Array[Html] {
  match snapshot {
    Some(snapshot) =>
      match node_id_for_entry(snapshot, entry) {
        Some(node_id) =>
          match node_for_id(snapshot, node_id) {
            Some(node) => {
              let exact_links = exact_remote_links_for_node(snapshot, node)
              if !exact_links.is_empty() {
                [render_meta_chip("handoff", exact_links.length().to_string())]
              } else if entry.run_id == snapshot.run.id &&
                !snapshot.linked_remote.is_empty() {
                [
                  render_meta_chip(
                    "remote",
                    snapshot.linked_remote.length().to_string(),
                  ),
                ]
              } else {
                []
              }
            }
            None => []
          }
        None =>
          if entry.run_id == snapshot.run.id &&
            !snapshot.linked_remote.is_empty() {
            [
              render_meta_chip(
                "remote",
                snapshot.linked_remote.length().to_string(),
              ),
            ]
          } else {
            []
          }
      }
    None => []
  }
}

///|
fn current_step_title(snapshot : UiSnapshot) -> String {
  match snapshot.current_step_id {
    Some(step_id) => node_title_for_step(snapshot, step_id)
    None => "pending"
  }
}

///|
fn latest_fresh_title(
  snapshot : UiSnapshot,
  timeline : Array[UiTimelineEntry],
  fresh_ids : Array[String],
) -> String? {
  for i = timeline.length() - 1; i >= 0; i = i - 1 {
    let entry = timeline[i]
    if contains_id(fresh_ids, entry.id) {
      return Some(entry.title)
    }
  }
  for node in snapshot.nodes {
    if contains_id(fresh_ids, node.id) {
      return Some(node.title)
    }
  }
  None
}

///|
fn fallback_focus_node_id(snapshot : UiSnapshot) -> String? {
  match snapshot.current_step_id {
    Some(step_id) => {
      for node in snapshot.nodes {
        if node.step_id == Some(step_id) {
          return Some(node.id)
        }
      }
      None
    }
    None => {
      for node in snapshot.nodes {
        if node.kind == "Workflow" {
          return Some(node.id)
        }
      }
      snapshot.nodes.get(0).map(fn(node) { node.id })
    }
  }
}

///|
fn resolved_focus_node_id(model : Model, snapshot : UiSnapshot) -> String? {
  match model.focused_node_id {
    Some(node_id) =>
      match node_for_id(snapshot, node_id) {
        Some(_) => Some(node_id)
        None => fallback_focus_node_id(snapshot)
      }
    None => fallback_focus_node_id(snapshot)
  }
}

///|
fn group_title_for(entry : UiTimelineEntry) -> String {
  match entry.step_id {
    Some(step_id) => "Step · \{step_id}"
    None => "Run · \{entry.run_id}"
  }
}

///|
fn group_id_for(entry : UiTimelineEntry) -> String {
  match entry.step_id {
    Some(step_id) => "step:\{step_id}"
    None => "run:\{entry.run_id}"
  }
}

///|
fn timeline_groups(timeline : Array[UiTimelineEntry]) -> Array[TimelineGroup] {
  let groups : Array[TimelineGroup] = []
  for entry in timeline {
    let group_id = group_id_for(entry)
    let mut matched = false
    for i = 0; i < groups.length(); i = i + 1 {
      if groups[i].id == group_id {
        groups[i] = { ..groups[i], entries: groups[i].entries + [entry] }
        matched = true
        break
      }
    }
    if !matched {
      groups.push({
        id: group_id,
        title: group_title_for(entry),
        entries: [entry],
      })
    }
  }
  groups
}

///|
fn timeline_entry_class(
  model : Model,
  snapshot : UiSnapshot?,
  entry : UiTimelineEntry,
) -> String {
  let mut classes = "timeline-entry"
  if entry.event_type == "remote.handoff" {
    classes = classes + " remote-handoff"
  }
  if contains_id(model.fresh_timeline_ids, entry.id) {
    classes = classes + " fresh"
  }
  match snapshot {
    Some(snapshot) =>
      match model.focused_node_id {
        Some(focused_node_id) =>
          match node_id_for_entry(snapshot, entry) {
            Some(node_id) =>
              if node_id == focused_node_id {
                classes = classes + " focused"
              }
            None => ()
          }
        None => ()
      }
    None => ()
  }
  classes
}

///|
fn remote_focus_id_for_timeline_entry(entry : UiTimelineEntry) -> String? {
  match entry.data {
    { "remote_id": String(remote_id), "remote_kind": String("acp_run"), .. } =>
      match remote_id.split_once(":") {
        Some((_, suffix)) => Some("run:\{suffix}")
        None => Some("run:\{remote_id}")
      }
    { "remote_id": String(remote_id), "remote_kind": String("acp_session"), .. } =>
      match remote_id.split_once(":") {
        Some((_, suffix)) => Some("session:\{suffix}")
        None => Some("session:\{remote_id}")
      }
    _ => None
  }
}

///|
fn timeline_entry_action(
  dispatch : Dispatch[Msg],
  entry : UiTimelineEntry,
) -> Cmd {
  if entry.event_type == "remote.handoff" {
    match remote_focus_id_for_timeline_entry(entry) {
      Some(focus_id) => @nav.push_url(acp_url(selected_node_id=Some(focus_id)))
      None => dispatch(FocusTimeline(entry.id))
    }
  } else {
    dispatch(FocusTimeline(entry.id))
  }
}

///|
fn view_run_card(
  dispatch : Dispatch[Msg],
  selected_run_id : String?,
  run : RunSummary,
) -> Html {
  let active = selected_run_id == Some(run.id)
  let card_class = if active { "run-card active" } else { "run-card" }
  button(class=card_class, on_click=dispatch(SelectRun(run.id)), [
    p(class="run-title", "\{run.job_id}"),
    div([render_status_badge(run.status)]),
    p(class="run-meta", "Run \{run.id} · depth \{run.depth}"),
    match run.summary {
      Some(summary) => p(class="run-meta", summary)
      None => nothing
    },
  ])
}

///|
fn filtered_runs(model : Model) -> Array[RunSummary] {
  let filtered = match model.runs_status_filter {
    Some(status) =>
      model.runs.filter(fn(run) {
        normalize_status(run.status).contains(status)
      })
    None => model.runs
  }
  let queried = if normalized_runs_query(model.runs_query) == "" {
    filtered
  } else {
    let query = normalized_runs_query(model.runs_query).to_lower()
    filtered.filter(fn(run) {
      run.id.to_lower().contains(query) ||
      run.job_id.to_lower().contains(query) ||
      run.status.to_lower().contains(query) ||
      run.summary.unwrap_or("").to_lower().contains(query)
    })
  }
  let sorted = queried.copy()
  match model.runs_sort {
    Newest =>
      sorted.sort_by(fn(left, right) {
        right.started_at.unwrap_or(0).compare(left.started_at.unwrap_or(0))
      })
    Oldest =>
      sorted.sort_by(fn(left, right) {
        left.started_at.unwrap_or(0).compare(right.started_at.unwrap_or(0))
      })
    Depth => sorted.sort_by(fn(left, right) { right.depth.compare(left.depth) })
  }
  sorted
}

///|
fn clamped_runs_page(model : Model, total_runs : Int) -> Int {
  if total_runs <= 0 {
    0
  } else {
    let last_page = (total_runs - 1) / runs_page_size()
    if model.runs_page < 0 {
      0
    } else if model.runs_page > last_page {
      last_page
    } else {
      model.runs_page
    }
  }
}

///|
fn paged_runs(model : Model, runs : Array[RunSummary]) -> Array[RunSummary] {
  let page = clamped_runs_page(model, runs.length())
  let start = page * runs_page_size()
  let page_runs : Array[RunSummary] = []
  for i = start; i < runs.length() && i < start + runs_page_size(); i = i + 1 {
    page_runs.push(runs[i])
  }
  page_runs
}

///|
fn render_runs_panel(dispatch : Dispatch[Msg], model : Model) -> Html {
  let runs = filtered_runs(model)
  let page = clamped_runs_page(model, runs.length())
  let visible_runs = paged_runs(model, runs)
  let total_pages = if runs.is_empty() {
    1
  } else {
    (runs.length() - 1) / runs_page_size() + 1
  }
  let status_button = fn(label : String, value : String?) {
    let active = model.runs_status_filter == value
    let cls = if active {
      "tree-control-button active-filter"
    } else {
      "tree-control-button"
    }
    button(class=cls, on_click=dispatch(SelectRunsStatus(value)), label)
  }
  let sort_button = fn(label : String, value : RunSort) {
    let active = model.runs_sort == value
    let cls = if active {
      "tree-control-button active-filter"
    } else {
      "tree-control-button"
    }
    button(class=cls, on_click=dispatch(SelectRunsSort(value)), label)
  }
  let operator_hint = article(class="operator-hint", [
    h3(class="section-title", "Planning"),
    p(
      class="muted",
      "Feishu plan mode now has a lightweight thread-local path before durable job execution.",
    ),
    p(class="mono", "/plan <request>"),
    p(class="muted", "Start or reset plan mode in the current Feishu thread."),
    p(class="mono", "/preview [guidance]"),
    p(
      class="muted",
      "Inspect the current plan candidate or refresh it without promoting.",
    ),
    p(class="mono", "/promote [guidance]"),
    p(
      class="muted",
      "Turn the current plan candidate into a normal draft proposal.",
    ),
    p(class="mono", "/plan-job <request>"),
    p(class="muted", "Create a durable proposal directly."),
    p(class="mono", "/e2e <request>"),
    p(class="muted", "Create the augmented preprocess and postprocess flow."),
  ])
  section(class="panel", [
    header(class="panel-header", [h2(class="panel-title", "Runs")]),
    div(class="panel-body", [
      div(class="runs-controls", [
        div(class="tree-controls", [
          status_button("All", None),
          status_button("Running", Some("Running")),
          status_button("Pending", Some("Pending")),
          status_button("Failed", Some("Failed")),
          status_button("Completed", Some("Completed")),
        ]),
        div(class="runs-search-row", [
          input(
            class="runs-search-input",
            placeholder="Search run id, job id, or summary",
            value=model.runs_query,
            on_input=value => dispatch(SetRunsQuery(value)),
          ),
        ]),
        div(class="tree-controls", [
          sort_button("Newest", Newest),
          sort_button("Oldest", Oldest),
          sort_button("Depth", Depth),
        ]),
      ]),
      if model.runs_loading {
        p(class="empty", "Loading runs...")
      } else if model.runs_error is Some(error) {
        p(class="empty", error)
      } else if runs.is_empty() {
        div([p(class="empty", "No job runs available yet."), operator_hint])
      } else {
        div([
          div(
            class="runs-list",
            visible_runs.map(fn(run) {
              view_run_card(dispatch, model.selected_run_id, run)
            }),
          ),
          operator_hint,
          div(class="runs-pagination", [
            span(class="muted", "Page \{page + 1} of \{total_pages}"),
            div(class="tree-controls", [
              button(
                class="tree-control-button",
                disabled=page == 0,
                on_click=dispatch(SelectRunsPage(page - 1)),
                "Prev",
              ),
              button(
                class="tree-control-button",
                disabled=page + 1 >= total_pages,
                on_click=dispatch(SelectRunsPage(page + 1)),
                "Next",
              ),
            ]),
          ]),
        ])
      },
    ]),
  ])
}

///|
fn local_linkage_metadata(
  snapshot : UiSnapshot?,
  focused_node_id? : String? = None,
) -> Json {
  match snapshot {
    Some(snapshot) => {
      let workspace = snapshot.workspace_dir.unwrap_or("")
      let focused_node = match focused_node_id {
        Some(node_id) => node_for_id(snapshot, node_id)
        None => None
      }
      match focused_node {
        Some(node) =>
          match node.step_id {
            Some(step_id) =>
              if workspace == "" {
                {
                  "linked_job_run_id": snapshot.run.id,
                  "linked_job_id": snapshot.run.job_id,
                  "linked_job_node_id": node.id,
                  "linked_job_step_id": step_id,
                }
              } else {
                {
                  "linked_job_run_id": snapshot.run.id,
                  "linked_job_id": snapshot.run.job_id,
                  "linked_workspace": workspace,
                  "linked_job_node_id": node.id,
                  "linked_job_step_id": step_id,
                }
              }
            None =>
              if workspace == "" {
                {
                  "linked_job_run_id": snapshot.run.id,
                  "linked_job_id": snapshot.run.job_id,
                  "linked_job_node_id": node.id,
                }
              } else {
                {
                  "linked_job_run_id": snapshot.run.id,
                  "linked_job_id": snapshot.run.job_id,
                  "linked_workspace": workspace,
                  "linked_job_node_id": node.id,
                }
              }
          }
        None =>
          if workspace == "" {
            {
              "linked_job_run_id": snapshot.run.id,
              "linked_job_id": snapshot.run.job_id,
            }
          } else {
            {
              "linked_job_run_id": snapshot.run.id,
              "linked_job_id": snapshot.run.job_id,
              "linked_workspace": workspace,
            }
          }
      }
    }
    None => {}
  }
}

///|
fn main {
  let (dispatch, app) = @rabbita.cell_with_dispatch(
    model=init_model(),
    update~,
    view~,
  )
  @rabbita.new(app)
  ..with_route(url_changed=url => dispatch(UrlChanged(url)), url_request=req => {
    dispatch(UrlRequest(req))
  })
  ..with_init(batch([dispatch(LoadRuns), dispatch(LoadAcp)]))
  .mount("app")
}
