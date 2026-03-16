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
fn render_stdio_preview(label : String, value : String?) -> Html {
  match value {
    Some(text) if !text.trim().is_blank() =>
      div(class="focus-block", [
        p(class="kv-label", label),
        article(class="artifact-card", [
          p(class="timeline-detail mono", preview_text(text, 320)),
        ]),
      ])
    _ => nothing
  }
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
              let stdout_preview = match node.metadata {
                { "stdout_stderr": { "stdout": String(stdout), .. }, .. } =>
                  Some(stdout)
                _ => None
              }
              let stderr_preview = match node.metadata {
                { "stdout_stderr": { "stderr": String(stderr), .. }, .. } =>
                  Some(stderr)
                _ => None
              }
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
                  render_stdio_preview("stdout", stdout_preview),
                  render_stdio_preview("stderr", stderr_preview),
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
