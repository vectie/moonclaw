///|
fn acp_node_for_id(snapshot : AcpUiSnapshot, node_id : String) -> AcpUiNode? {
  for node in snapshot.nodes {
    if node.id == node_id {
      return Some(node)
    }
  }
  None
}

///|
fn acp_kind_label(kind : AcpUiNodeKind) -> String {
  match kind {
    Target => "Target"
    Session => "Session"
    Run => "Run"
  }
}

///|
fn resolved_acp_node_id(model : Model, snapshot : AcpUiSnapshot) -> String? {
  match model.selected_acp_node_id {
    Some(node_id) =>
      match acp_node_for_id(snapshot, node_id) {
        Some(_) => Some(node_id)
        None => snapshot.nodes.get(0).map(fn(node) { node.id })
      }
    None => snapshot.nodes.get(0).map(fn(node) { node.id })
  }
}

///|
fn acp_timeline_for_node(
  node : AcpUiNode,
  timeline : Array[AcpUiTimelineEntry],
) -> Array[AcpUiTimelineEntry] {
  timeline.filter(fn(entry) {
    match node.kind {
      Target => entry.target_id == node.target_id
      Session => entry.session_id == node.session_id
      Run => entry.run_id == node.run_id
    }
  })
}

///|
fn acp_node_for_entry(
  snapshot : AcpUiSnapshot,
  entry : AcpUiTimelineEntry,
) -> AcpUiNode? {
  for node in snapshot.nodes {
    if !acp_timeline_for_node(node, [entry]).is_empty() {
      return Some(node)
    }
  }
  None
}

///|
fn acp_timeline_entry_class(
  model : Model,
  entry : AcpUiTimelineEntry,
) -> String {
  let mut classes = "timeline-entry"
  if entry.event_type == "run.output" {
    classes = classes + " remote-handoff"
  }
  match entry.data {
    { "linkage": { "linked_job_run_id": String(_), .. }, .. } =>
      classes = classes + " local-origin"
    _ => ()
  }
  if contains_id(model.fresh_acp_timeline_ids, entry.id) {
    classes = classes + " fresh"
  }
  match model.selected_acp_node_id {
    Some(node_id) =>
      match model.acp_snapshot {
        Some(snapshot) =>
          match acp_node_for_id(snapshot, node_id) {
            Some(node) =>
              if acp_timeline_for_node(node, [entry]).length() > 0 {
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
fn acp_timeline_badges(entry : AcpUiTimelineEntry) -> Array[Html] {
  let badges : Array[Html] = []
  match entry.data {
    { "live": True, .. } => badges.push(render_meta_chip("live", "stdio"))
    _ => ()
  }
  match entry.data {
    { "linkage": { "linked_job_run_id": String(run_id), .. }, .. } =>
      badges.push(render_meta_chip("local-run", run_id))
    _ => ()
  }
  match entry.data {
    { "linkage": { "linked_job_node_id": String(node_id), .. }, .. } =>
      badges.push(render_meta_chip("node", node_id))
    _ => ()
  }
  match entry.data {
    { "linkage": { "linked_job_step_id": String(step_id), .. }, .. } =>
      badges.push(render_meta_chip("step", step_id))
    _ => ()
  }
  badges
}

///|
fn render_acp_node_card(
  dispatch : Dispatch[Msg],
  model : Model,
  node : AcpUiNode,
) -> Html {
  let active = model.selected_acp_node_id == Some(node.id)
  let fresh = contains_id(model.fresh_acp_node_ids, node.id)
  let cls = if active {
    "run-card active"
  } else if fresh {
    "run-card fresh"
  } else {
    "run-card"
  }
  button(class=cls, on_click=dispatch(SelectAcpNode(node.id)), [
    p(class="node-kind", acp_kind_label(node.kind)),
    p(class="run-title", node.title),
    div([render_status_badge(node.status)]),
    div(class="timeline-meta", render_acp_runtime_chips(node)),
    match node.summary {
      Some(summary) => p(class="run-meta", preview_text(summary, 120))
      None => nothing
    },
    match node.detail {
      Some(detail) => p(class="run-meta mono", preview_text(detail, 120))
      None => nothing
    },
  ])
}

///|
fn acp_duration_label(node : AcpUiNode) -> String? {
  let created_at = match node.created_at {
    Some(created_at) => created_at
    None => return None
  }
  let updated_at = match node.updated_at {
    Some(updated_at) => updated_at
    None => return None
  }
  let elapsed_ms = updated_at - created_at
  if elapsed_ms < 0 {
    None
  } else if elapsed_ms < 1000 {
    Some("\{elapsed_ms}ms")
  } else if elapsed_ms < 60_000 {
    Some("\{elapsed_ms / 1000}s")
  } else {
    let minutes = elapsed_ms / 60_000
    let seconds = elapsed_ms % 60_000 / 1000
    Some("\{minutes}m \{seconds}s")
  }
}

///|
fn acp_exit_status(node : AcpUiNode) -> Int? {
  match node.metadata {
    { "stdout_stderr": { "exit_status": Number(exit_status, ..), .. }, .. } =>
      Some(exit_status.to_int())
    _ => None
  }
}

///|
fn render_acp_runtime_chips(node : AcpUiNode) -> Array[Html] {
  let chips : Array[Html] = []
  match acp_duration_label(node) {
    Some(duration) => chips.push(render_meta_chip("elapsed", duration))
    None => ()
  }
  match acp_exit_status(node) {
    Some(exit_status) =>
      chips.push(render_meta_chip("exit", exit_status.to_string()))
    None => ()
  }
  chips
}

///|
fn latest_live_acp_run(snapshot : AcpUiSnapshot) -> AcpUiNode? {
  let live_runs = snapshot.nodes.filter(fn(node) {
    node.kind == Run && acp_status_is_live(node.status)
  })
  if live_runs.is_empty() {
    None
  } else {
    let sorted = live_runs.copy()
    sorted.sort_by(fn(left, right) {
      right.updated_at.unwrap_or(0).compare(left.updated_at.unwrap_or(0))
    })
    Some(sorted[0])
  }
}

///|
fn render_acp_panel(dispatch : Dispatch[Msg], model : Model) -> Html {
  section(class="panel", [
    header(class="panel-header", [h2(class="panel-title", "ACP Remote Agents")]),
    div(class="panel-body", [
      if model.acp_loading && model.acp_snapshot is None {
        p(class="empty", "Loading ACP targets, sessions, and runs...")
      } else if model.acp_error is Some(error) {
        p(class="empty", error)
      } else {
        match model.acp_snapshot {
          Some(snapshot) =>
            div(class="runs-list", [
              match latest_live_acp_run(snapshot) {
                Some(run) =>
                  article(class="overview-stat", [
                    p(class="kv-label", "Latest Active Run"),
                    button(
                      class="focus-link",
                      on_click=dispatch(SelectAcpNode(run.id)),
                      [
                        p(class="node-kind", "run"),
                        p(class="timeline-title", run.title),
                        div(
                          class="timeline-meta",
                          [
                            render_status_badge(run.status),
                            match run.run_id {
                              Some(run_id) => render_meta_chip("run", run_id)
                              None => nothing
                            },
                            ..render_acp_runtime_chips(run),
                          ],
                        ),
                        match run.summary {
                          Some(summary) =>
                            p(class="muted", preview_text(summary, 160))
                          None => nothing
                        },
                      ],
                    ),
                  ])
                None => nothing
              },
              article(class="overview-stat", [
                p(class="kv-label", "Targets"),
                p(class="detail-title", "\{snapshot.targets.length()}"),
              ]),
              article(class="overview-stat", [
                p(class="kv-label", "Sessions"),
                p(class="detail-title", "\{snapshot.sessions.length()}"),
              ]),
              article(class="overview-stat", [
                p(class="kv-label", "Runs"),
                p(class="detail-title", "\{snapshot.runs.length()}"),
              ]),
              p(class="kv-label", "Targets"),
              div(
                class="runs-list",
                snapshot.nodes
                .filter(fn(node) { node.kind == Target })
                .map(fn(node) { render_acp_node_card(dispatch, model, node) }),
              ),
              p(class="kv-label", "Sessions"),
              div(
                class="runs-list",
                snapshot.nodes
                .filter(fn(node) { node.kind == Session })
                .map(fn(node) { render_acp_node_card(dispatch, model, node) }),
              ),
              p(class="kv-label", "Runs"),
              div(
                class="runs-list",
                snapshot.nodes
                .filter(fn(node) { node.kind == Run })
                .map(fn(node) { render_acp_node_card(dispatch, model, node) }),
              ),
            ])
          None => p(class="empty", "No ACP targets configured yet.")
        }
      },
    ]),
  ])
}

///|
fn render_acp_timeline(
  dispatch : Dispatch[Msg],
  model : Model,
  timeline : Array[AcpUiTimelineEntry],
) -> Html {
  if timeline.is_empty() {
    p(class="empty", "No ACP activity yet.")
  } else {
    div(
      class="timeline",
      timeline.map(fn(entry) {
        let badges = acp_timeline_badges(entry)
        button(
          class=acp_timeline_entry_class(model, entry),
          on_click=match model.acp_snapshot {
            Some(snapshot) =>
              match acp_node_for_entry(snapshot, entry) {
                Some(node) => dispatch(SelectAcpNode(node.id))
                None => @rabbita.none
              }
            None => @rabbita.none
          },
          [
            p(class="timeline-title", entry.title),
            p(class="timeline-detail", preview_text(entry.detail, 220)),
            if badges.is_empty() {
              nothing
            } else {
              div(class="timeline-meta", badges)
            },
            div([
              match entry.status {
                Some(status) => render_status_badge(status)
                None => nothing
              },
              span(class="muted mono", "\{entry.timestamp}"),
            ]),
          ],
        )
      }),
    )
  }
}

///|
fn acp_output_id(node : AcpUiNode, label : String) -> String {
  "\{node.id}:\{label}"
}

///|
fn render_stdio_preview(
  dispatch : Dispatch[Msg],
  model : Model,
  node : AcpUiNode,
  label : String,
  value : String?,
) -> Html {
  match value {
    Some(text) if !text.trim().is_blank() => {
      let output_id = acp_output_id(node, label)
      let expanded = contains_id(model.expanded_acp_output_ids, output_id)
      div(class="focus-block", [
        div(class="timeline-meta", [
          p(class="kv-label", label),
          render_action_chip(
            if expanded {
              "Collapse"
            } else {
              "Show Full"
            },
            dispatch(ToggleAcpOutput(output_id)),
          ),
          render_action_chip("Copy", dispatch(CopyAcpOutput(label, text))),
        ]),
        article(class="artifact-card", [
          p(
            class="timeline-detail mono",
            if expanded {
              text
            } else {
              preview_text(text, 320)
            },
          ),
        ]),
      ])
    }
    _ => nothing
  }
}

///|
fn acp_node_stdout(node : AcpUiNode) -> String? {
  match node.metadata {
    { "stdout_stderr": { "stdout": String(stdout), .. }, .. } => Some(stdout)
    _ => None
  }
}

///|
fn acp_node_stderr(node : AcpUiNode) -> String? {
  match node.metadata {
    { "stdout_stderr": { "stderr": String(stderr), .. }, .. } => Some(stderr)
    _ => None
  }
}

///|
fn acp_linkage_lines(node : AcpUiNode) -> Array[String] {
  let lines : Array[String] = []
  match acp_node_linkage(node) {
    Some({ "linked_job_run_id": String(run_id), .. }) =>
      lines.push("linked_job_run_id: \{run_id}")
    _ => ()
  }
  match acp_node_linkage(node) {
    Some({ "linked_job_id": String(job_id), .. }) =>
      lines.push("linked_job_id: \{job_id}")
    _ => ()
  }
  match acp_node_linkage(node) {
    Some({ "linked_job_node_id": String(node_id), .. }) =>
      lines.push("linked_job_node_id: \{node_id}")
    _ => ()
  }
  match acp_node_linkage(node) {
    Some({ "linked_job_step_id": String(step_id), .. }) =>
      lines.push("linked_job_step_id: \{step_id}")
    _ => ()
  }
  match acp_linked_local_workspace(node) {
    Some(workspace) => lines.push("linked_workspace: \{workspace}")
    None => ()
  }
  lines
}

///|
fn acp_run_transcript(node : AcpUiNode) -> String {
  let lines : Array[String] = [
    "ACP Run Transcript",
    "",
    "title: \{node.title}",
    "status: \{normalize_status(node.status)}",
  ]
  match node.run_id {
    Some(run_id) => lines.push("run_id: \{run_id}")
    None => ()
  }
  match node.session_id {
    Some(session_id) => lines.push("session_id: \{session_id}")
    None => ()
  }
  match node.target_id {
    Some(target_id) => lines.push("target_id: \{target_id}")
    None => ()
  }
  match node.created_at {
    Some(created_at) => lines.push("created_at: \{created_at}")
    None => ()
  }
  match node.updated_at {
    Some(updated_at) => lines.push("updated_at: \{updated_at}")
    None => ()
  }
  match acp_duration_label(node) {
    Some(duration) => lines.push("elapsed: \{duration}")
    None => ()
  }
  match acp_exit_status(node) {
    Some(exit_status) => lines.push("exit_status: \{exit_status}")
    None => ()
  }
  match node.summary {
    Some(summary) if !summary.trim().is_blank() => {
      lines.push("")
      lines.push("summary:")
      lines.push(summary)
    }
    _ => ()
  }
  match node.detail {
    Some(detail) if !detail.trim().is_blank() => {
      lines.push("")
      lines.push("detail:")
      lines.push(detail)
    }
    _ => ()
  }
  let linkage = acp_linkage_lines(node)
  if !linkage.is_empty() {
    lines.push("")
    lines.push("linkage:")
    for line in linkage {
      lines.push(line)
    }
  }
  match acp_node_stdout(node) {
    Some(stdout) if !stdout.trim().is_blank() => {
      lines.push("")
      lines.push("stdout:")
      lines.push(stdout)
    }
    _ => ()
  }
  match acp_node_stderr(node) {
    Some(stderr) if !stderr.trim().is_blank() => {
      lines.push("")
      lines.push("stderr:")
      lines.push(stderr)
    }
    _ => ()
  }
  lines.join("\n")
}

///|
fn acp_session_transcript(snapshot : AcpUiSnapshot, node : AcpUiNode) -> String {
  let lines : Array[String] = [
    "ACP Session Transcript",
    "",
    "title: \{node.title}",
    "status: \{normalize_status(node.status)}",
  ]
  match node.session_id {
    Some(session_id) => lines.push("session_id: \{session_id}")
    None => ()
  }
  match node.target_id {
    Some(target_id) => lines.push("target_id: \{target_id}")
    None => ()
  }
  match node.created_at {
    Some(created_at) => lines.push("created_at: \{created_at}")
    None => ()
  }
  match node.updated_at {
    Some(updated_at) => lines.push("updated_at: \{updated_at}")
    None => ()
  }
  match acp_duration_label(node) {
    Some(duration) => lines.push("elapsed: \{duration}")
    None => ()
  }
  match node.summary {
    Some(summary) if !summary.trim().is_blank() => {
      lines.push("")
      lines.push("summary:")
      lines.push(summary)
    }
    _ => ()
  }
  match node.detail {
    Some(detail) if !detail.trim().is_blank() => {
      lines.push("")
      lines.push("detail:")
      lines.push(detail)
    }
    _ => ()
  }
  let linkage = acp_linkage_lines(node)
  if !linkage.is_empty() {
    lines.push("")
    lines.push("linkage:")
    for line in linkage {
      lines.push(line)
    }
  }
  match node.session_id {
    Some(session_id) => {
      let runs = acp_session_run_nodes(snapshot, session_id)
      lines.push("")
      lines.push("run_count: \{runs.length()}")
      if !runs.is_empty() {
        lines.push("")
        lines.push("runs:")
        for run in runs {
          lines.push("")
          lines.push("---")
          lines.push("title: \{run.title}")
          lines.push("status: \{normalize_status(run.status)}")
          match run.run_id {
            Some(run_id) => lines.push("run_id: \{run_id}")
            None => ()
          }
          match run.created_at {
            Some(created_at) => lines.push("created_at: \{created_at}")
            None => ()
          }
          match run.updated_at {
            Some(updated_at) => lines.push("updated_at: \{updated_at}")
            None => ()
          }
          match acp_duration_label(run) {
            Some(duration) => lines.push("elapsed: \{duration}")
            None => ()
          }
          match acp_exit_status(run) {
            Some(exit_status) => lines.push("exit_status: \{exit_status}")
            None => ()
          }
          match run.summary {
            Some(summary) if !summary.trim().is_blank() => {
              lines.push("")
              lines.push("summary:")
              lines.push(summary)
            }
            _ => ()
          }
          match run.detail {
            Some(detail) if !detail.trim().is_blank() => {
              lines.push("")
              lines.push("detail:")
              lines.push(detail)
            }
            _ => ()
          }
          match acp_node_stdout(run) {
            Some(stdout) if !stdout.trim().is_blank() => {
              lines.push("")
              lines.push("stdout:")
              lines.push(stdout)
            }
            _ => ()
          }
          match acp_node_stderr(run) {
            Some(stderr) if !stderr.trim().is_blank() => {
              lines.push("")
              lines.push("stderr:")
              lines.push(stderr)
            }
            _ => ()
          }
        }
      }
    }
    None => ()
  }
  lines.join("\n")
}

///|
fn acp_session_timeline_transcript(
  node : AcpUiNode,
  timeline : Array[AcpUiTimelineEntry],
) -> String {
  let lines : Array[String] = [
    "ACP Session Timeline Transcript",
    "",
    "title: \{node.title}",
    "status: \{normalize_status(node.status)}",
  ]
  match node.session_id {
    Some(session_id) => lines.push("session_id: \{session_id}")
    None => ()
  }
  match node.target_id {
    Some(target_id) => lines.push("target_id: \{target_id}")
    None => ()
  }
  lines.push("event_count: \{timeline.length()}")
  if !timeline.is_empty() {
    lines.push("")
    lines.push("events:")
    for entry in timeline {
      lines.push("")
      lines.push("---")
      lines.push("timestamp: \{entry.timestamp}")
      lines.push("event_type: \{entry.event_type}")
      lines.push("title: \{entry.title}")
      lines.push("detail: \{entry.detail}")
      match entry.status {
        Some(status) => lines.push("status: \{normalize_status(status)}")
        None => ()
      }
      match entry.session_id {
        Some(session_id) => lines.push("session_id: \{session_id}")
        None => ()
      }
      match entry.run_id {
        Some(run_id) => lines.push("run_id: \{run_id}")
        None => ()
      }
      match entry.target_id {
        Some(target_id) => lines.push("target_id: \{target_id}")
        None => ()
      }
    }
  }
  lines.join("\n")
}

///|
fn acp_session_run_nodes(
  snapshot : AcpUiSnapshot,
  session_id : String,
) -> Array[AcpUiNode] {
  snapshot.nodes.filter(fn(node) {
    node.kind == Run && node.session_id == Some(session_id)
  })
}

///|
fn render_acp_run_history(
  dispatch : Dispatch[Msg],
  snapshot : AcpUiSnapshot,
  selected_node_id : String?,
  session_id : String?,
) -> Html {
  match session_id {
    Some(session_id) => {
      let runs = acp_session_run_nodes(snapshot, session_id)
      div(class="focus-block", [
        p(class="kv-label", "Run History"),
        if runs.is_empty() {
          p(class="empty", "No remote runs for this ACP session yet.")
        } else {
          div(
            class="focus-links",
            runs.map(fn(run) {
              let button_class = if selected_node_id == Some(run.id) {
                "focus-link active"
              } else {
                "focus-link"
              }
              button(
                class=button_class,
                on_click=dispatch(SelectAcpNode(run.id)),
                [
                  p(class="node-kind", "run"),
                  p(class="timeline-title", run.title),
                  div(
                    class="timeline-meta",
                    [
                      match run.run_id {
                        Some(run_id) => render_meta_chip("run", run_id)
                        None => nothing
                      },
                      render_status_badge(run.status),
                      ..render_acp_runtime_chips(run),
                    ],
                  ),
                  match run.summary {
                    Some(summary) =>
                      p(class="muted", preview_text(summary, 140))
                    None => nothing
                  },
                ],
              )
            }),
          )
        },
      ])
    }
    None => nothing
  }
}

///|
fn render_acp_output_pane(
  dispatch : Dispatch[Msg],
  model : Model,
  snapshot : AcpUiSnapshot,
  node : AcpUiNode,
  related : Array[AcpUiTimelineEntry],
) -> Html {
  let session_id = match node.kind {
    Session => node.session_id
    Run => node.session_id
    _ => None
  }
  let live_output_events = related.filter(fn(entry) {
    entry.event_type == "run.output"
  })
  section([
    h3(class="section-title", "Remote Output"),
    render_stdio_preview(dispatch, model, node, "stdout", acp_node_stdout(node)),
    render_stdio_preview(dispatch, model, node, "stderr", acp_node_stderr(node)),
    if live_output_events.is_empty() {
      nothing
    } else {
      div(class="focus-block", [
        p(class="kv-label", "Live Output Feed"),
        div(
          class="focus-events",
          preview_items(live_output_events, 6).map(fn(entry) {
            article(class="focus-event", [
              p(class="timeline-title", entry.title),
              p(class="muted", preview_text(entry.detail, 220)),
            ])
          }),
        ),
      ])
    },
    render_acp_run_history(
      dispatch,
      snapshot,
      model.selected_acp_node_id,
      session_id,
    ),
  ])
}

///|
fn render_acp_action_bar(
  dispatch : Dispatch[Msg],
  model : Model,
  node : AcpUiNode,
) -> Html {
  div(
    class="tree-controls",
    match node.kind {
      Target =>
        match node.target_id {
          Some(target_id) =>
            [
              button(
                class="tree-control-button active-filter",
                on_click=dispatch(AttachAcpTarget(target_id)),
                "Attach",
              ),
            ]
          None => []
        }
      Session =>
        match node.session_id {
          Some(session_id) =>
            [
              button(
                class="tree-control-button",
                on_click=dispatch(ExportAcpSession(session_id)),
                "Export Session",
              ),
              button(
                class="tree-control-button",
                on_click=dispatch(ExportAcpSessionTimeline(session_id)),
                "Export Timeline",
              ),
              button(
                class="tree-control-button",
                on_click=dispatch(ResetAcpSession(session_id)),
                "Reset",
              ),
              button(
                class="tree-control-button",
                on_click=dispatch(DetachAcpSession(session_id)),
                "Detach",
              ),
              button(
                class="tree-control-button active-filter",
                disabled=model.acp_run_message.trim().is_blank(),
                on_click=dispatch(StartAcpRun(session_id)),
                "Run",
              ),
            ]
          None => []
        }
      Run =>
        match node.run_id {
          Some(run_id) =>
            [
              button(
                class="tree-control-button",
                on_click=dispatch(CancelAcpRun(run_id)),
                "Cancel Run",
              ),
              button(
                class="tree-control-button",
                on_click=dispatch(ExportAcpRun(run_id)),
                "Export",
              ),
            ]
          None => []
        }
    },
  )
}

///|
fn render_acp_detail(dispatch : Dispatch[Msg], model : Model) -> Html {
  match model.acp_snapshot {
    Some(snapshot) =>
      match resolved_acp_node_id(model, snapshot) {
        Some(node_id) =>
          match acp_node_for_id(snapshot, node_id) {
            Some(node) => {
              let related = acp_timeline_for_node(node, model.acp_timeline)
              section(class="panel", [
                header(class="panel-header", [
                  div(class="detail-header", [
                    div([
                      p(class="eyebrow", "Remote ACP Control"),
                      h2(class="detail-title", node.title),
                      p(
                        class="subline",
                        node.summary.unwrap_or(
                          "Attached ACP targets, sessions, and remote runs.",
                        ),
                      ),
                    ]),
                    render_status_badge(node.status),
                  ]),
                ]),
                div(class="panel-body", [
                  if model.acp_loading {
                    div(class="refresh-banner", [
                      p(class="kv-label", "ACP Refresh"),
                      p(
                        class="timeline-detail",
                        "Refreshing remote-agent state...",
                      ),
                    ])
                  } else {
                    nothing
                  },
                  match model.acp_action_notice {
                    Some(notice) =>
                      div(class="refresh-banner", [
                        p(class="kv-label", "ACP Action"),
                        p(class="timeline-detail", notice),
                      ])
                    None => nothing
                  },
                  div(class="detail-grid", [
                    section([
                      if node.kind == Session {
                        div(class="runs-controls", [
                          input(
                            class="runs-search-input",
                            placeholder="Message for remote ACP run",
                            value=model.acp_run_message,
                            on_input=value => dispatch(SetAcpRunMessage(value)),
                            nothing,
                          ),
                          render_acp_action_bar(dispatch, model, node),
                        ])
                      } else {
                        render_acp_action_bar(dispatch, model, node)
                      },
                      h3(class="section-title", "Remote Timeline"),
                      render_acp_timeline(dispatch, model, related),
                    ]),
                    render_acp_output_pane(
                      dispatch, model, snapshot, node, related,
                    ),
                  ]),
                ]),
              ])
            }
            None =>
              section(class="panel", [
                header(class="panel-header", [
                  h2(class="panel-title", "ACP Detail"),
                ]),
                div(class="panel-body", [
                  p(class="empty", "Select an ACP node."),
                ]),
              ])
          }
        None =>
          section(class="panel", [
            header(class="panel-header", [h2(class="panel-title", "ACP Detail")]),
            div(class="panel-body", [
              p(class="empty", "No ACP state available yet."),
            ]),
          ])
      }
    None =>
      section(class="panel", [
        header(class="panel-header", [h2(class="panel-title", "ACP Detail")]),
        div(class="panel-body", [p(class="empty", "Loading ACP state...")]),
      ])
  }
}

///|
fn render_acp_inspector(dispatch : Dispatch[Msg], model : Model) -> Html {
  match model.acp_snapshot {
    Some(snapshot) =>
      match resolved_acp_node_id(model, snapshot) {
        Some(node_id) =>
          match acp_node_for_id(snapshot, node_id) {
            Some(node) => {
              let related = acp_timeline_for_node(node, model.acp_timeline)
              section(class="panel", [
                header(class="panel-header", [
                  h2(class="panel-title", "ACP Inspector"),
                ]),
                div(class="panel-body", [
                  p(class="node-kind", acp_kind_label(node.kind)),
                  p(class="node-title", node.title),
                  div([render_status_badge(node.status)]),
                  render_acp_action_bar(dispatch, model, node),
                  match node.detail {
                    Some(detail) => p(class="mono", detail)
                    None => nothing
                  },
                  match node.summary {
                    Some(summary) => p(class="timeline-detail", summary)
                    None => nothing
                  },
                  div(class="inspector-stats", [
                    render_meta_chip("events", related.length().to_string()),
                    match node.target_id {
                      Some(target_id) => render_meta_chip("target", target_id)
                      None => nothing
                    },
                    match node.session_id {
                      Some(session_id) =>
                        render_meta_chip("session", session_id)
                      None => nothing
                    },
                    match node.run_id {
                      Some(run_id) => render_meta_chip("run", run_id)
                      None => nothing
                    },
                  ]),
                  render_linked_local_panel(node),
                  render_stdio_preview(
                    dispatch,
                    model,
                    node,
                    "stdout",
                    acp_node_stdout(node),
                  ),
                  render_stdio_preview(
                    dispatch,
                    model,
                    node,
                    "stderr",
                    acp_node_stderr(node),
                  ),
                  render_acp_run_history(
                    dispatch,
                    snapshot,
                    model.selected_acp_node_id,
                    match node.kind {
                      Session => node.session_id
                      Run => node.session_id
                      _ => None
                    },
                  ),
                  if related.is_empty() {
                    p(class="empty", "No related ACP events yet.")
                  } else {
                    div(
                      class="focus-events",
                      preview_items(related, 6).map(fn(entry) {
                        article(class="focus-event", [
                          p(class="timeline-title", entry.title),
                          p(class="muted", preview_text(entry.detail, 180)),
                        ])
                      }),
                    )
                  },
                ]),
              ])
            }
            None =>
              section(class="panel", [
                header(class="panel-header", [
                  h2(class="panel-title", "ACP Inspector"),
                ]),
                div(class="panel-body", [
                  p(class="empty", "Select an ACP node."),
                ]),
              ])
          }
        None =>
          section(class="panel", [
            header(class="panel-header", [
              h2(class="panel-title", "ACP Inspector"),
            ]),
            div(class="panel-body", [p(class="empty", "No ACP node selected.")]),
          ])
      }
    None =>
      section(class="panel", [
        header(class="panel-header", [h2(class="panel-title", "ACP Inspector")]),
        div(class="panel-body", [p(class="empty", "Loading ACP state...")]),
      ])
  }
}

///|
fn acp_node_workspace(node : AcpUiNode) -> String? {
  match node.detail {
    Some(detail) if !detail.trim().is_blank() => Some(detail)
    _ => None
  }
}

///|
fn acp_node_linkage(node : AcpUiNode) -> Json? {
  match node.metadata {
    { "linkage": linkage, .. } => Some(linkage)
    _ => None
  }
}

///|
fn acp_linked_local_run_id(node : AcpUiNode) -> String? {
  match acp_node_linkage(node) {
    Some({ "linked_job_run_id": String(run_id), .. }) => Some(run_id)
    _ => None
  }
}

///|
fn acp_linked_local_job_id(node : AcpUiNode) -> String? {
  match acp_node_linkage(node) {
    Some({ "linked_job_id": String(job_id), .. }) => Some(job_id)
    _ => None
  }
}

///|
fn acp_linked_local_workspace(node : AcpUiNode) -> String? {
  match acp_node_linkage(node) {
    Some({ "linked_workspace": String(workspace), .. }) if !workspace
      .trim()
      .is_blank() => Some(workspace)
    _ => None
  }
}

///|
fn render_linked_local_panel(node : AcpUiNode) -> Html {
  match acp_linked_local_run_id(node) {
    Some(run_id) =>
      div(class="focus-block", [
        p(class="kv-label", "Originated Locally"),
        button(
          class="focus-link",
          on_click=@nav.push_url(
            run_url(
              run_id,
              focused_node_id=match acp_node_linkage(node) {
                Some({ "linked_job_node_id": String(node_id), .. }) =>
                  Some(node_id)
                _ => None
              },
              panel=Some(Artifacts),
            ),
          ),
          [
            p(class="node-kind", "local"),
            p(
              class="timeline-title",
              acp_linked_local_job_id(node).unwrap_or(run_id),
            ),
            div(class="timeline-meta", [
              render_meta_chip("run", run_id),
              match acp_node_linkage(node) {
                Some({ "linked_job_node_id": String(node_id), .. }) =>
                  render_meta_chip("node", node_id)
                _ => nothing
              },
              match acp_node_linkage(node) {
                Some({ "linked_job_step_id": String(step_id), .. }) =>
                  render_meta_chip("step", step_id)
                _ => nothing
              },
            ]),
            match acp_linked_local_workspace(node) {
              Some(workspace) =>
                p(class="muted mono", preview_text(workspace, 96))
              None => nothing
            },
          ],
        ),
      ])
    None => nothing
  }
}
