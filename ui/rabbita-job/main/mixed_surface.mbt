///|
fn string_contains_ci(text : String, needle : String) -> Bool {
  text.to_lower().contains(needle.to_lower())
}

///|
fn path_tail(path : String) -> String {
  match path.split("/").filter(fn(part) { !part.is_empty() }).last() {
    Some(part) => part.to_string()
    None => path
  }
}

///|
fn acp_node_linkage_matches_local(
  snapshot : UiSnapshot,
  node : AcpUiNode,
) -> Bool {
  let linkage = match node.metadata {
    { "linkage": linkage, .. } => Some(linkage)
    _ => None
  }
  match linkage {
    Some({ "linked_job_run_id": String(run_id), .. }) if run_id ==
      snapshot.run.id => true
    Some({ "linked_job_id": String(job_id), .. }) if job_id ==
      snapshot.run.job_id => true
    Some({ "linked_workspace": String(workspace), .. }) => {
      let local_workspace = snapshot.workspace_dir.unwrap_or("")
      local_workspace != "" &&
      (
        workspace == local_workspace ||
        path_tail(workspace) == path_tail(local_workspace)
      )
    }
    _ => false
  }
}

///|
fn acp_node_related_to_local(snapshot : UiSnapshot, node : AcpUiNode) -> Bool {
  if acp_node_linkage_matches_local(snapshot, node) {
    return true
  }
  let run_id = snapshot.run.id
  let job_id = snapshot.run.job_id
  let workspace = snapshot.workspace_dir.unwrap_or("")
  let workspace_tail = if workspace == "" { "" } else { path_tail(workspace) }
  let summary = node.summary.unwrap_or("")
  let detail = node.detail.unwrap_or("")
  let node_workspace = acp_node_workspace(node).unwrap_or("")
  let metadata_session_key = match node.metadata {
    { "session_key": String(session_key), .. } => session_key
    _ => ""
  }
  string_contains_ci(summary, run_id) ||
  string_contains_ci(summary, job_id) ||
  string_contains_ci(detail, run_id) ||
  string_contains_ci(detail, job_id) ||
  string_contains_ci(metadata_session_key, run_id) ||
  string_contains_ci(metadata_session_key, job_id) ||
  (
    workspace != "" &&
    (
      string_contains_ci(node_workspace, workspace) ||
      string_contains_ci(workspace, node_workspace) ||
      (
        workspace_tail != "" &&
        string_contains_ci(node_workspace, workspace_tail)
      )
    )
  )
}

///|
fn render_linked_remote_button(link : UiRemoteLink) -> Html {
  button(
    class="focus-link",
    on_click=@nav.push_url(acp_url_for_remote_link(link)),
    [
      p(class="node-kind", link.kind),
      p(class="timeline-title", link.title),
      div([render_status_badge(link.status)]),
      div(class="timeline-meta", [
        match remote_linked_node_id(link) {
          Some(node_id) => render_meta_chip("node", node_id)
          None => nothing
        },
        match remote_linked_step_id(link) {
          Some(step_id) => render_meta_chip("step", step_id)
          None => nothing
        },
      ]),
      match link.summary {
        Some(summary) => p(class="muted", preview_text(summary, 140))
        None => nothing
      },
      match link.detail {
        Some(detail) => p(class="mono", preview_text(detail, 120))
        None => nothing
      },
    ],
  )
}

///|
fn render_linked_remote_panel(snapshot : UiSnapshot) -> Html {
  let links = snapshot.linked_remote
  section(class="panel", [
    header(class="panel-header", [h2(class="panel-title", "Linked Remote")]),
    div(class="panel-body", [
      if links.is_empty() {
        p(class="empty", "No linked ACP sessions or runs yet.")
      } else {
        div(
          class="focus-links",
          links.map(fn(link) { render_linked_remote_button(link) }),
        )
      },
    ]),
  ])
}

///|
fn dedupe_remote_links(links : Array[UiRemoteLink]) -> Array[UiRemoteLink] {
  let deduped : Array[UiRemoteLink] = []
  let seen : Array[String] = []
  for link in links {
    if !contains_id(seen, link.id) {
      seen.push(link.id)
      deduped.push(link)
    }
  }
  deduped
}

///|
fn remote_lineage_key(links : Array[UiRemoteLink]) -> String {
  let ids = dedupe_remote_links(links).map(fn(link) { link.id })
  ids.sort()
  ids.join("|")
}

///|
fn grouped_handoffs(handoffs : Array[UiHandoff]) -> Array[MixedHandoffGroup] {
  let groups : Array[MixedHandoffGroup] = []
  for handoff in handoffs {
    let remote = dedupe_remote_links(handoff.remote)
    let key = remote_lineage_key(remote)
    let mut matched = false
    for i = 0; i < groups.length(); i = i + 1 {
      if groups[i].key == key {
        groups[i] = {
          ..groups[i],
          handoffs: groups[i].handoffs + [handoff],
          remote: dedupe_remote_links(groups[i].remote + remote),
        }
        matched = true
        break
      }
    }
    if !matched {
      groups.push({ key, handoffs: [handoff], remote })
    }
  }
  groups
}

///|
fn mixed_handoff_group_for_key(
  handoffs : Array[UiHandoff],
  key : String?,
) -> MixedHandoffGroup? {
  match key {
    Some(key) => {
      for group in grouped_handoffs(handoffs) {
        if group.key == key {
          return Some(group)
        }
      }
      None
    }
    None => None
  }
}

///|
fn render_mixed_handoff_card(
  dispatch : Dispatch[Msg],
  selected_key : String?,
  snapshot : UiSnapshot,
  group : MixedHandoffGroup,
) -> Html {
  let remote_links = group.remote
  let handoff = group.handoffs[0]
  let remote_running = remote_links
    .filter(fn(link) { normalize_status(link.status).contains("Running") })
    .length()
  let remote_failed = remote_links
    .filter(fn(link) { normalize_status(link.status).contains("Failed") })
    .length()
  let remote_completed = remote_links
    .filter(fn(link) { normalize_status(link.status).contains("Completed") })
    .length()
  let card_class = if selected_key == Some(group.key) {
    "artifact-card mixed-handoff-card active"
  } else {
    "artifact-card mixed-handoff-card"
  }
  article(class=card_class, [
    p(class="kv-label", "Handoff"),
    div(class="timeline-meta", [
      render_meta_chip("local", group.handoffs.length().to_string()),
      if group.handoffs.length() == 1 {
        render_meta_chip("node", handoff.node_id)
      } else {
        nothing
      },
      match handoff.step_id {
        Some(step_id) if group.handoffs.length() == 1 =>
          render_meta_chip("step", step_id)
        None => nothing
        _ => nothing
      },
      render_meta_chip("remote", remote_links.length().to_string()),
      if remote_running > 0 {
        render_meta_chip("running", remote_running.to_string())
      } else {
        nothing
      },
      if remote_failed > 0 {
        render_meta_chip("failed", remote_failed.to_string())
      } else {
        nothing
      },
      if remote_completed > 0 {
        render_meta_chip("completed", remote_completed.to_string())
      } else {
        nothing
      },
    ]),
    div(class="timeline-meta", [
      render_action_chip(
        if selected_key == Some(group.key) {
          "Clear Focus"
        } else {
          "Focus Lineage"
        },
        dispatch(
          SelectMixedHandoff(
            if selected_key == Some(group.key) {
              None
            } else {
              Some(group.key)
            },
          ),
        ),
      ),
    ]),
    div(class="mixed-handoff-grid", [
      div(class="focus-block handoff-column", [
        p(class="kv-label", "Local Origin"),
        div(
          class="focus-links",
          preview_items(group.handoffs, 3).map(fn(handoff) {
            button(
              class="focus-link",
              on_click=@nav.push_url(
                run_url(
                  snapshot.run.id,
                  focused_node_id=Some(handoff.node_id),
                  panel=Some(Artifacts),
                ),
              ),
              [
                p(class="node-kind", "local"),
                p(class="timeline-title", snapshot.run.job_id),
                div(class="timeline-meta", [
                  render_meta_chip("node", handoff.node_id),
                  match handoff.step_id {
                    Some(step_id) => render_meta_chip("step", step_id)
                    None => nothing
                  },
                ]),
              ],
            )
          }),
        ),
        if group.handoffs.length() > 3 {
          p(
            class="muted",
            "\{group.handoffs.length() - 3} more local nodes in this branch",
          )
        } else {
          nothing
        },
      ]),
      div(class="handoff-arrow", [span(class="meta-chip", "handoff")]),
      div(class="focus-block handoff-column", [
        p(class="kv-label", "Remote Branch"),
        div(
          class="focus-links",
          preview_items(remote_links, 3).map(fn(link) {
            render_linked_remote_button(link)
          }),
        ),
      ]),
    ]),
  ])
}

///|
fn render_focused_lineage_summary(
  dispatch : Dispatch[Msg],
  snapshot : UiSnapshot,
  group : MixedHandoffGroup,
) -> Html {
  let primary_handoff = group.handoffs[0]
  let primary_remote = group.remote[0]
  article(class="overview-stat", [
    p(class="kv-label", "Focused Lineage"),
    p(
      class="muted",
      "\{group.handoffs.length()} local handoff(s) mapped to \{group.remote.length()} remote link(s).",
    ),
    div(class="timeline-meta", [
      render_meta_chip("local", group.handoffs.length().to_string()),
      render_meta_chip("remote", group.remote.length().to_string()),
      render_meta_chip("node", primary_handoff.node_id),
      match primary_handoff.step_id {
        Some(step_id) => render_meta_chip("step", step_id)
        None => nothing
      },
    ]),
    div(class="timeline-meta", [
      render_action_chip(
        "Open Local",
        @nav.push_url(
          run_url(
            snapshot.run.id,
            focused_node_id=Some(primary_handoff.node_id),
            panel=Some(Artifacts),
          ),
        ),
      ),
      render_action_chip(
        "Open ACP",
        @nav.push_url(acp_url_for_remote_link(primary_remote)),
      ),
      render_action_chip("Export", dispatch(ExportMixedLineage(group.key))),
      render_action_chip("Export Case", dispatch(ExportMixedCase(group.key))),
      render_action_chip("Clear Focus", dispatch(SelectMixedHandoff(None))),
    ]),
  ])
}

///|
fn local_run_transcript(snapshot : UiSnapshot) -> String {
  let lines : Array[String] = [
    "Local Run Transcript",
    "",
    "run_id: \{snapshot.run.id}",
    "job_id: \{snapshot.run.job_id}",
    "status: \{normalize_status(snapshot.run.status)}",
    "node_count: \{snapshot.nodes.length()}",
    "timeline_count: \{snapshot.timeline.length()}",
    "artifact_count: \{snapshot.artifacts.length()}",
    "memory_count: \{snapshot.memories.length()}",
    "linked_remote_count: \{snapshot.linked_remote.length()}",
    "handoff_count: \{snapshot.handoffs.length()}",
  ]
  match snapshot.workspace_dir {
    Some(workspace) => lines.push("workspace: \{workspace}")
    None => ()
  }
  match snapshot.current_step_id {
    Some(step_id) => lines.push("current_step_id: \{step_id}")
    None => ()
  }
  match snapshot.run.summary {
    Some(summary) if !summary.trim().is_blank() => {
      lines.push("")
      lines.push("summary:")
      lines.push(summary)
    }
    _ => ()
  }
  match snapshot.run.error {
    Some(error) if !error.trim().is_blank() => {
      lines.push("")
      lines.push("error:")
      lines.push(error)
    }
    _ => ()
  }
  if !snapshot.timeline.is_empty() {
    lines.push("")
    lines.push("recent_timeline:")
    for entry in preview_items(snapshot.timeline, 20) {
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
      match entry.step_id {
        Some(step_id) => lines.push("step_id: \{step_id}")
        None => ()
      }
    }
  }
  lines.join("\n")
}

///|
fn mixed_lineage_transcript(
  snapshot : UiSnapshot,
  group : MixedHandoffGroup,
) -> String {
  let lines : Array[String] = [
    "Mixed Lineage Transcript",
    "",
    "lineage_key: \{group.key}",
    "run_id: \{snapshot.run.id}",
    "job_id: \{snapshot.run.job_id}",
    "status: \{normalize_status(snapshot.run.status)}",
  ]
  match snapshot.workspace_dir {
    Some(workspace) => lines.push("workspace: \{workspace}")
    None => ()
  }
  match snapshot.run.summary {
    Some(summary) if !summary.trim().is_blank() => {
      lines.push("")
      lines.push("run_summary:")
      lines.push(summary)
    }
    _ => ()
  }
  lines.push("")
  lines.push("local_handoffs: \{group.handoffs.length()}")
  lines.push("remote_links: \{group.remote.length()}")
  if !group.handoffs.is_empty() {
    lines.push("")
    lines.push("local_origins:")
    for handoff in group.handoffs {
      lines.push("")
      lines.push("---")
      lines.push("node_id: \{handoff.node_id}")
      match handoff.step_id {
        Some(step_id) => lines.push("step_id: \{step_id}")
        None => ()
      }
      match node_for_id(snapshot, handoff.node_id) {
        Some(node) => {
          lines.push("node_kind: \{node.kind}")
          lines.push("node_title: \{node.title}")
          lines.push("node_status: \{normalize_status(node.status)}")
          match node.summary {
            Some(summary) if !summary.trim().is_blank() =>
              lines.push("node_summary: \{summary}")
            _ => ()
          }
          match node.detail {
            Some(detail) if !detail.trim().is_blank() =>
              lines.push("node_detail: \{detail}")
            _ => ()
          }
        }
        None => ()
      }
    }
  }
  if !group.remote.is_empty() {
    lines.push("")
    lines.push("remote_branch:")
    for link in group.remote {
      lines.push("")
      lines.push("---")
      lines.push("id: \{link.id}")
      lines.push("kind: \{link.kind}")
      lines.push("title: \{link.title}")
      lines.push("status: \{normalize_status(link.status)}")
      match link.summary {
        Some(summary) if !summary.trim().is_blank() =>
          lines.push("summary: \{summary}")
        _ => ()
      }
      match link.detail {
        Some(detail) if !detail.trim().is_blank() =>
          lines.push("detail: \{detail}")
        _ => ()
      }
      match remote_linked_node_id(link) {
        Some(node_id) => lines.push("linked_job_node_id: \{node_id}")
        None => ()
      }
      match remote_linked_step_id(link) {
        Some(step_id) => lines.push("linked_job_step_id: \{step_id}")
        None => ()
      }
    }
  }
  lines.join("\n")
}

///|
fn session_ids_for_mixed_group(
  group : MixedHandoffGroup,
  acp_snapshot : AcpUiSnapshot,
) -> Array[String] {
  let session_ids : Array[String] = []
  for link in group.remote {
    if link.id.has_prefix("acp-session:") {
      match link.id.split_once(":") {
        Some((_, session_id)) => {
          let session_id = session_id.to_string()
          if !contains_id(session_ids, session_id) {
            session_ids.push(session_id)
          }
        }
        None => ()
      }
    } else if link.id.has_prefix("acp-run:") {
      match link.id.split_once(":") {
        Some((_, run_id)) =>
          match acp_node_for_id(acp_snapshot, "run:\{run_id}") {
            Some(node) =>
              match node.session_id {
                Some(session_id) =>
                  if !contains_id(session_ids, session_id) {
                    session_ids.push(session_id)
                  }
                None => ()
              }
            None => ()
          }
        None => ()
      }
    }
  }
  session_ids
}

///|
fn mixed_case_transcript(
  snapshot : UiSnapshot,
  acp_snapshot : AcpUiSnapshot,
  group : MixedHandoffGroup,
) -> String {
  let sections : Array[String] = [
    local_run_transcript(snapshot),
    mixed_lineage_transcript(snapshot, group),
  ]
  let session_ids = session_ids_for_mixed_group(group, acp_snapshot)
  for session_id in session_ids {
    match acp_node_for_id(acp_snapshot, "session:\{session_id}") {
      Some(node) =>
        sections.push(
          acp_session_timeline_transcript(
            node,
            acp_timeline_for_node(node, acp_snapshot.timeline),
          ),
        )
      None => ()
    }
  }
  sections.join("\n\n====================\n\n")
}

///|
fn render_mixed_relationships(
  dispatch : Dispatch[Msg],
  model : Model,
  snapshot : UiSnapshot?,
  acp_snapshot : AcpUiSnapshot?,
) -> Html {
  match (snapshot, acp_snapshot) {
    (Some(snapshot), Some(acp_snapshot)) => {
      let handoff_groups = grouped_handoffs(snapshot.handoffs)
      let focused_group = mixed_handoff_group_for_key(
        snapshot.handoffs,
        model.selected_mixed_handoff_key,
      )
      let explicit = snapshot.linked_remote
      let inferred = acp_snapshot.nodes.filter(fn(node) {
        acp_node_related_to_local(snapshot, node)
      })
      let visible_explicit = match focused_group {
        Some(group) =>
          explicit.filter(fn(link) {
            group.remote.any(fn(candidate) { candidate.id == link.id })
          })
        None => explicit
      }
      let visible_inferred = match focused_group {
        Some(group) =>
          inferred.filter(fn(node) {
            group.remote.any(fn(link) {
              acp_focus_id_for_remote_link(link) == Some(node.id)
            })
          })
        None => inferred
      }
      section(class="panel nested-panel", [
        header(class="panel-header", [h2(class="panel-title", "Mixed Links")]),
        div(class="panel-body", [
          p(
            class="muted",
            "Local run \{snapshot.run.id} / \{snapshot.run.job_id} cross-referenced against ACP remote targets, sessions, and runs.",
          ),
          if handoff_groups.is_empty() &&
            explicit.is_empty() &&
            inferred.is_empty() {
            p(
              class="empty",
              "No explicit local↔remote links inferred yet. Relationships appear here when workspace paths, run ids, or job ids overlap.",
            )
          } else {
            div(class="runs-list", [
              if !handoff_groups.is_empty() {
                article(class="overview-stat", [
                  p(class="kv-label", "Recorded Handoffs"),
                  p(
                    class="muted",
                    "Exact local node and remote ACP links captured from runtime linkage metadata.",
                  ),
                ])
              } else {
                nothing
              },
              match focused_group {
                Some(group) =>
                  render_focused_lineage_summary(dispatch, snapshot, group)
                None => nothing
              },
              div(
                class="runs-list",
                handoff_groups.map(fn(group) {
                  render_mixed_handoff_card(
                    dispatch,
                    model.selected_mixed_handoff_key,
                    snapshot,
                    group,
                  )
                }),
              ),
              if !visible_explicit.is_empty() {
                article(class="overview-stat", [
                  p(class="kv-label", "Explicit Links"),
                  p(
                    class="muted",
                    if focused_group is Some(_) {
                      "Scoped to the selected lineage only. These links were recorded directly when ACP was attached or run from a selected local job context."
                    } else {
                      "These links were recorded directly when ACP was attached or run from a selected local job context."
                    },
                  ),
                ])
              } else {
                nothing
              },
              div(
                class="runs-list",
                visible_explicit.map(fn(link) {
                  article(class="artifact-card", [
                    p(class="node-kind", link.kind),
                    p(class="node-title", link.title),
                    div([render_status_badge(link.status)]),
                    match link.detail {
                      Some(detail) => p(class="mono", preview_text(detail, 120))
                      None => nothing
                    },
                    match link.summary {
                      Some(summary) =>
                        p(class="muted", preview_text(summary, 140))
                      None => nothing
                    },
                  ])
                }),
              ),
              if !visible_inferred.is_empty() {
                article(class="overview-stat", [
                  p(class="kv-label", "Inferred Links"),
                  p(
                    class="muted",
                    if focused_group is Some(_) {
                      "Scoped to the selected lineage only. Fallback matches are based on workspace paths, run ids, job ids, and ACP session context."
                    } else {
                      "Fallback matches based on workspace paths, run ids, job ids, and ACP session context."
                    },
                  ),
                ])
              } else {
                nothing
              },
              div(
                class="runs-list",
                visible_inferred.map(fn(node) {
                  article(class="artifact-card", [
                    p(class="node-kind", acp_kind_label(node.kind)),
                    p(class="node-title", node.title),
                    div([render_status_badge(node.status)]),
                    match node.detail {
                      Some(detail) => p(class="mono", preview_text(detail, 120))
                      None => nothing
                    },
                    match node.summary {
                      Some(summary) =>
                        p(class="muted", preview_text(summary, 140))
                      None => nothing
                    },
                  ])
                }),
              ),
            ])
          },
        ]),
      ])
    }
    _ =>
      section(class="panel nested-panel", [
        header(class="panel-header", [h2(class="panel-title", "Mixed Links")]),
        div(class="panel-body", [
          p(
            class="empty",
            "Select or load both a local run and ACP state to inspect cross-linked local↔remote activity.",
          ),
        ]),
      ])
  }
}

///|
fn render_overview(dispatch : Dispatch[Msg], model : Model) -> Html {
  let local_running = model.runs
    .filter(fn(run) { run_status_is_live(run.status) })
    .length()
  let (acp_targets, acp_sessions, acp_runs, acp_live_runs) = match
    model.acp_snapshot {
    Some(snapshot) =>
      (
        snapshot.targets.length(),
        snapshot.sessions.length(),
        snapshot.runs.length(),
        snapshot.nodes
        .filter(fn(node) { node.kind == Run && acp_status_is_live(node.status) })
        .length(),
      )
    None => (0, 0, 0, 0)
  }
  section(class="panel", [
    header(class="panel-header", [h2(class="panel-title", "Work overview")]),
    div(class="panel-body", [
      render_operator_next_step(dispatch, model),
      div(class="overview-grid", [
        article(class="overview-stat", [
          p(class="kv-label", "Durable runs"),
          p(class="detail-title", "\{model.runs.length()}"),
          p(class="muted", "\{local_running} live"),
        ]),
        article(class="overview-stat", [
          p(class="kv-label", "Remote workers"),
          p(class="detail-title", "\{acp_targets}"),
          p(class="muted", "\{acp_sessions} sessions"),
        ]),
        article(class="overview-stat", [
          p(class="kv-label", "Remote runs"),
          p(class="detail-title", "\{acp_runs}"),
          p(class="muted", "\{acp_live_runs} live"),
        ]),
      ]),
      div(class="mixed-grid", [
        render_runs_panel(dispatch, model),
        render_acp_panel(dispatch, model),
      ]),
      render_mixed_relationships(
        dispatch,
        model,
        model.snapshot,
        model.acp_snapshot,
      ),
    ]),
  ])
}

///|
fn run_linked_remote_for_node(
  snapshot : UiSnapshot,
  node : UiNode,
) -> Array[UiRemoteLink] {
  let exact = exact_remote_links_for_node(snapshot, node)
  if !exact.is_empty() {
    exact
  } else {
    match node.run_id {
      Some(run_id) if run_id == snapshot.run.id => snapshot.linked_remote
      None => snapshot.linked_remote
      _ => []
    }
  }
}

///|
fn render_run_linked_remote_panel(snapshot : UiSnapshot, node : UiNode) -> Html {
  let links = run_linked_remote_for_node(snapshot, node)
  if links.is_empty() {
    nothing
  } else {
    div(class="focus-block", [
      p(
        class="kv-label",
        if exact_remote_links_for_node(snapshot, node).is_empty() {
          "Run-Linked Remote Activity"
        } else {
          "Remote Handoff"
        },
      ),
      div(
        class="focus-links",
        preview_items(links, 4).map(fn(link) {
          render_linked_remote_button(link)
        }),
      ),
    ])
  }
}
