///|
fn[T] preview_items(items : Array[T], limit : Int) -> Array[T] {
  let preview : Array[T] = []
  let mut count = 0
  for item in items {
    if count >= limit {
      break
    }
    preview.push(item)
    count = count + 1
  }
  preview
}

///|
fn starter_artifact(artifact : UiArtifact) -> Bool {
  artifact.artifact_type == "starter_attachment.digest" ||
  artifact.artifact_type == "starter_attachment.text" ||
  artifact.artifact_type == "starter_attachment.summary" ||
  artifact.artifact_type == "starter_attachment.manifest"
}

///|
fn partition_starter_artifacts(
  artifacts : Array[UiArtifact],
) -> (Array[UiArtifact], Array[UiArtifact]) {
  let starter : Array[UiArtifact] = []
  let other : Array[UiArtifact] = []
  for artifact in artifacts {
    if starter_artifact(artifact) {
      starter.push(artifact)
    } else {
      other.push(artifact)
    }
  }
  (starter, other)
}

///|
fn path_basename(path : String) -> String {
  match path.split("/").collect() {
    [] => path
    parts => parts[parts.length() - 1].to_string()
  }
}

///|
fn primary_starter_artifact(artifacts : Array[UiArtifact]) -> UiArtifact? {
  let priorities = [
    "starter_attachment.digest", "starter_attachment.summary", "starter_attachment.text",
    "starter_attachment.manifest",
  ]
  for priority in priorities {
    for artifact in artifacts {
      if artifact.artifact_type == priority {
        return Some(artifact)
      }
    }
  }
  artifacts.get(0)
}

///|
fn starter_artifact_preview(artifacts : Array[UiArtifact]) -> String {
  let names : Array[String] = []
  for artifact in artifacts {
    let name = path_basename(artifact.path)
    if !names.contains(name) {
      names.push(name)
    }
    if names.length() >= 3 {
      break
    }
  }
  match names {
    [] => "No starter documents"
    [name] => name
    [first, second] => "\{first}, \{second}"
    [first, second, third, ..] => "\{first}, \{second}, \{third}"
  }
}

///|
fn render_starter_docs_card(
  dispatch : Dispatch[Msg],
  artifacts : Array[UiArtifact],
) -> Html {
  let primary = primary_starter_artifact(artifacts)
  let unique_paths : Array[String] = []
  for artifact in artifacts {
    if !unique_paths.contains(artifact.path) {
      unique_paths.push(artifact.path)
    }
  }
  let summary = "\{unique_paths.length()} file(s) materialized across \{artifacts.length()} artifact(s)"
  let body = [
    p(class="node-title", "Starter Docs"),
    p(class="muted", summary),
    p(class="mono", starter_artifact_preview(artifacts)),
  ]
  match primary {
    Some(artifact) if artifact_is_textual(artifact) =>
      button(
        class="artifact-card artifact-card-button",
        on_click=dispatch(OpenArtifact(artifact.id)),
        body,
      )
    _ => article(class="artifact-card", body)
  }
}

///|
fn artifact_is_textual(artifact : UiArtifact) -> Bool {
  artifact.content_type.has_prefix("text/") ||
  artifact.content_type == "application/json"
}

///|
fn artifact_is_report_like(artifact : UiArtifact) -> Bool {
  artifact.artifact_type.contains(".report") ||
  artifact.artifact_type == "report" ||
  artifact.path.has_suffix("/report.md") ||
  artifact.path.has_suffix(".report.md")
}

///|
fn render_artifact_card(
  dispatch : Dispatch[Msg],
  artifact : UiArtifact,
) -> Html {
  let body = [
    p(
      class="node-title",
      artifact.logical_key.unwrap_or(artifact.artifact_type),
    ),
    p(class="muted", artifact.artifact_type),
    p(class="mono", artifact.path),
  ]
  if artifact_is_textual(artifact) {
    button(
      class="artifact-card artifact-card-button",
      on_click=dispatch(OpenArtifact(artifact.id)),
      body,
    )
  } else {
    article(class="artifact-card", body)
  }
}

///|
fn render_artifact_focus_card(
  dispatch : Dispatch[Msg],
  artifact : UiArtifact,
  label : String,
  preview : String,
) -> Html {
  let body = [
    p(
      class="node-title",
      artifact.logical_key.unwrap_or(artifact.artifact_type),
    ),
    p(class="muted", label),
    p(class="mono", preview),
  ]
  if artifact_is_textual(artifact) {
    button(
      class="artifact-card artifact-card-button",
      on_click=dispatch(OpenArtifact(artifact.id)),
      body,
    )
  } else {
    article(class="artifact-card", body)
  }
}

///|
fn child_run_nodes(snapshot : UiSnapshot) -> Array[UiNode] {
  snapshot.nodes.filter(fn(node) { node.kind == "ChildRun" })
}

///|
struct CompanyLaneEntry {
  step : UiNode
  child_runs : Array[UiNode]
}

///|
struct CompanyLane {
  key : String
  title : String
  order : Int
  entries : Array[CompanyLaneEntry]
}

///|
struct CompanyLaneStats {
  live : Int
  failed : Int
  completed : Int
  total : Int
}

///|
struct CompanyBoardStats {
  lane_count : Int
  live_lanes : Int
  blocked_lanes : Int
  completed_lanes : Int
  waiting_lanes : Int
  remote_workers : Int
}

///|
struct CompanyHandoff {
  from_title : String
  to_title : String
  from_status : String
  to_status : String
  active_title : String
}

///|
fn node_is_root(snapshot : UiSnapshot, node : UiNode) -> Bool {
  match node.parent_id {
    None => true
    Some(parent_id) =>
      !snapshot.nodes.any(fn(candidate) { candidate.id == parent_id })
  }
}

///|
fn child_nodes(snapshot : UiSnapshot, parent_id : String) -> Array[UiNode] {
  snapshot.nodes.filter(fn(node) { node.parent_id == Some(parent_id) })
}

///|
fn descendant_nodes(snapshot : UiSnapshot, node : UiNode) -> Array[UiNode] {
  let descendants : Array[UiNode] = []
  let frontier = child_nodes(snapshot, node.id)
  while !frontier.is_empty() {
    match frontier.pop() {
      Some(current) => {
        descendants.push(current)
        for child in child_nodes(snapshot, current.id) {
          frontier.push(child)
        }
      }
      None => ()
    }
  }
  descendants
}

///|
fn parent_node(snapshot : UiSnapshot, node : UiNode) -> UiNode? {
  match node.parent_id {
    Some(parent_id) => node_for_id(snapshot, parent_id)
    None => None
  }
}

///|
fn node_has_collapsible_children(snapshot : UiSnapshot, node : UiNode) -> Bool {
  !child_nodes(snapshot, node.id).is_empty()
}

///|
fn auto_collapsible_node(snapshot : UiSnapshot, node : UiNode) -> Bool {
  node_has_collapsible_children(snapshot, node) &&
  !node.provisional &&
  !normalize_status(node.status).contains("Running") &&
  !normalize_status(node.status).contains("Pending") &&
  !normalize_status(node.status).contains("Failed")
}

///|
fn parent_chain_ids(snapshot : UiSnapshot, node_id : String) -> Array[String] {
  let ids : Array[String] = []
  let mut current = node_for_id(snapshot, node_id)
  while current is Some(_) {
    match current {
      Some(node) =>
        match node.parent_id {
          Some(parent_id) => {
            ids.push(parent_id)
            current = node_for_id(snapshot, parent_id)
          }
          None => current = None
        }
      None => ()
    }
  }
  ids
}

///|
fn auto_collapsed_ids(snapshot : UiSnapshot) -> Array[String] {
  snapshot.nodes
  .filter(fn(node) { auto_collapsible_node(snapshot, node) })
  .map(fn(node) { node.id })
}

///|
fn manual_tree_state_for_snapshot(
  model : Model,
  snapshot : UiSnapshot,
) -> (Array[String], Array[String]) {
  let node_ids = snapshot.nodes.map(fn(node) { node.id })
  let collapsed = model.collapsed_node_ids.filter(fn(id) {
    contains_id(node_ids, id)
  })
  let expanded = model.expanded_node_ids.filter(fn(id) {
    contains_id(node_ids, id)
  })
  (collapsed, expanded)
}

///|
fn keep_expanded_node(
  snapshot : UiSnapshot,
  model : Model,
  node : UiNode,
) -> Bool {
  contains_id(model.fresh_node_ids, node.id) ||
  model.focused_node_id == Some(node.id) ||
  snapshot.current_step_id == node.step_id ||
  contains_id(
    parent_chain_ids(snapshot, model.focused_node_id.unwrap_or("")),
    node.id,
  ) ||
  normalize_status(node.status).contains("Running") ||
  normalize_status(node.status).contains("Pending") ||
  normalize_status(node.status).contains("Failed")
}

///|
fn node_is_collapsed(
  model : Model,
  snapshot : UiSnapshot,
  node : UiNode,
) -> Bool {
  let focus_path = parent_chain_ids(
    snapshot,
    model.focused_node_id.unwrap_or(""),
  )
  if keep_expanded_node(snapshot, model, node) {
    false
  } else if contains_id(model.collapsed_node_ids, node.id) {
    true
  } else if contains_id(model.expanded_node_ids, node.id) {
    false
  } else {
    auto_collapsible_node(snapshot, node) &&
    !contains_id(model.fresh_node_ids, node.id) &&
    model.focused_node_id != Some(node.id) &&
    !contains_id(focus_path, node.id)
  }
}

///|
fn toggle_manual_tree_state(
  model : Model,
  snapshot : UiSnapshot,
  node_id : String,
) -> (Array[String], Array[String]) {
  match node_for_id(snapshot, node_id) {
    Some(node) if node_has_collapsible_children(snapshot, node) => {
      let collapsed = model.collapsed_node_ids
      let expanded = model.expanded_node_ids
      if node_is_collapsed(model, snapshot, node) {
        (
          collapsed.filter(fn(id) { id != node_id }),
          if contains_id(expanded, node_id) {
            expanded
          } else {
            expanded + [node_id]
          },
        )
      } else {
        (
          if contains_id(collapsed, node_id) {
            collapsed
          } else {
            collapsed + [node_id]
          },
          expanded.filter(fn(id) { id != node_id }),
        )
      }
    }
    _ => (model.collapsed_node_ids, model.expanded_node_ids)
  }
}

///|
fn collapsed_summary(
  snapshot : UiSnapshot,
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> String {
  let stats = lineage_event_stats(snapshot, node, timeline)
  let child_count = descendant_nodes(snapshot, node).length()
  let parts : Array[String] = ["\{child_count} nodes"]
  if stats.artifact_hits > 0 {
    parts.push("\{stats.artifact_hits} artifacts")
  }
  if stats.memory_hits > 0 {
    parts.push("\{stats.memory_hits} memories")
  }
  if stats.failed_events > 0 {
    parts.push("\{stats.failed_events} failures")
  }
  if stats.max_attempt > 1 {
    parts.push("retry x\{stats.max_attempt}")
  }
  let mut summary = ""
  for i = 0; i < parts.length(); i = i + 1 {
    if i > 0 {
      summary = summary + " · "
    }
    summary = summary + parts[i]
  }
  summary
}

///|
fn render_collapsed_actions(
  dispatch : Dispatch[Msg],
  snapshot : UiSnapshot,
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> Html {
  let stats = lineage_event_stats(snapshot, node, timeline)
  let has_actions = stats.artifact_hits > 0 ||
    stats.memory_hits > 0 ||
    stats.failed_events > 0
  if !has_actions {
    nothing
  } else {
    div(class="timeline-meta", [
      if stats.artifact_hits > 0 {
        render_action_chip(
          "Open Artifacts",
          dispatch(FocusBranchPanel(node.id, Artifacts)),
        )
      } else {
        nothing
      },
      if stats.memory_hits > 0 {
        render_action_chip(
          "Open Memory",
          dispatch(FocusBranchPanel(node.id, Memory)),
        )
      } else {
        nothing
      },
      if stats.failed_events > 0 {
        render_action_chip(
          "Inspect Failures",
          dispatch(FocusBranchEvents(node.id)),
        )
      } else {
        nothing
      },
    ])
  }
}

///|
fn render_tree_node(
  model : Model,
  dispatch : Dispatch[Msg],
  snapshot : UiSnapshot,
  node : UiNode,
  depth : Int,
) -> Html {
  let children = child_nodes(snapshot, node.id)
  let has_children = !children.is_empty()
  let collapsed = node_is_collapsed(model, snapshot, node)
  div(style=["margin-left: \{depth * 18}px;"], [
    div(class="tree-node-row", [
      if has_children {
        button(
          class="tree-toggle",
          on_click=dispatch(ToggleNode(node.id)),
          if collapsed {
            "Expand"
          } else {
            "Collapse"
          },
        )
      } else {
        nothing
      },
      button(
        class=node_state_class(model, snapshot, node) + " tree-node-body",
        on_click=dispatch(FocusNode(node.id)),
        [
          p(class="node-kind", node.kind),
          p(class="node-title", node.title),
          div([render_status_badge(node.status)]),
          div(class="node-meta", [
            render_meta_chip("node", node.id),
            match node.step_id {
              Some(step_id) => render_meta_chip("step", step_id)
              None => nothing
            },
            match node.run_id {
              Some(run_id) => render_meta_chip("run", run_id)
              None => nothing
            },
            if node.provisional {
              render_meta_chip("state", "provisional")
            } else if node.kind == "ChildRun" {
              render_meta_chip("state", "delegated")
            } else {
              nothing
            },
          ]),
          render_node_badges(snapshot, node, model.timeline),
          match node.summary {
            Some(summary) => p(class="muted", summary)
            None => nothing
          },
          match node.detail {
            Some(detail) => p(class="muted mono", detail)
            None => nothing
          },
          if collapsed {
            div([
              p(
                class="collapsed-summary",
                "Collapsed branch: \{collapsed_summary(snapshot, node, model.timeline)}",
              ),
              render_collapsed_actions(dispatch, snapshot, node, model.timeline),
            ])
          } else {
            nothing
          },
        ],
      ),
    ]),
    if children.is_empty() || collapsed {
      nothing
    } else {
      div(
        class="tree-children",
        children.map(fn(child) {
          render_tree_node(model, dispatch, snapshot, child, depth + 1)
        }),
      )
    },
  ])
}

///|
fn render_tree(
  dispatch : Dispatch[Msg],
  model : Model,
  snapshot : UiSnapshot,
) -> Html {
  let roots = snapshot.nodes.filter(fn(node) { node_is_root(snapshot, node) })
  div(
    class="tree",
    roots.map(fn(node) { render_tree_node(model, dispatch, snapshot, node, 0) }),
  )
}

///|
fn render_tree_controls(dispatch : Dispatch[Msg]) -> Html {
  div(class="tree-controls", [
    button(
      class="tree-control-button",
      on_click=dispatch(ExpandActiveBranches),
      "Expand Active",
    ),
    button(
      class="tree-control-button",
      on_click=dispatch(CollapseCompletedBranches),
      "Collapse Completed",
    ),
    button(
      class="tree-control-button",
      on_click=dispatch(ResetTree),
      "Reset Tree",
    ),
  ])
}

///|
fn node_metadata_string(node : UiNode, key : String) -> String? {
  match node.metadata {
    Object(obj) =>
      match obj.get(key) {
        Some(String(value)) => Some(value)
        _ => None
      }
    _ => None
  }
}

///|
fn node_metadata_int(node : UiNode, key : String) -> Int? {
  match node.metadata {
    Object(obj) =>
      match obj.get(key) {
        Some(Number(value, ..)) => Some(value.to_int())
        _ => None
      }
    _ => None
  }
}

///|
fn node_metadata_has_string(
  node : UiNode,
  key : String,
  target : String,
) -> Bool {
  match node.metadata {
    Object(obj) =>
      match obj.get(key) {
        Some(Array(values)) =>
          values.any(fn(value) {
            match value {
              String(text) => text == target
              _ => false
            }
          })
        _ => false
      }
    _ => false
  }
}

///|
fn node_step_text(node : UiNode) -> String {
  let step_id = node.step_id.unwrap_or("")
  let detail = node.detail.unwrap_or("")
  let child_profile = node_metadata_string(node, "child_profile").unwrap_or("")
  let worker_role = node_metadata_string(node, "worker_role").unwrap_or("")
  "\{node.title} \{step_id} \{detail} \{child_profile} \{worker_role}"
}

///|
fn lane_title_from_text(text : String) -> String {
  let lowered = text.to_lower()
  if lowered.contains("ceo") || lowered.contains("founder") {
    "CEO"
  } else if lowered.contains("eng") || lowered.contains("engineering") {
    "Engineering"
  } else if lowered.contains("implement") || lowered.contains("builder") {
    "Implementation"
  } else if lowered.contains("review") {
    "Review"
  } else if lowered.contains("qa") ||
    lowered.contains("verify") ||
    lowered.contains("test") {
    "QA"
  } else if lowered.contains("ship") || lowered.contains("release") {
    "Shipping"
  } else {
    "Operations"
  }
}

///|
fn lane_title_for_node(snapshot : UiSnapshot, node : UiNode) -> String {
  match node_metadata_string(node, "board_lane") {
    Some(title) if !title.is_blank() => return title
    _ => ()
  }
  if node.kind == "ChildRun" {
    match node_metadata_string(node, "worker_role") {
      Some(role) => lane_title_from_text(role)
      None =>
        match parent_node(snapshot, node) {
          Some(parent) => lane_title_for_node(snapshot, parent)
          None => "Operations"
        }
    }
  } else if node_metadata_has_string(node, "preferred_skills", "opc-ceo") {
    "CEO"
  } else if node_metadata_has_string(node, "preferred_skills", "opc-eng") {
    "Engineering"
  } else if node_metadata_has_string(node, "preferred_skills", "opc-review") {
    "Review"
  } else if node_metadata_has_string(node, "preferred_skills", "opc-qa") {
    "QA"
  } else if node_metadata_has_string(node, "preferred_skills", "opc-ship") {
    "Shipping"
  } else {
    lane_title_from_text(node_step_text(node))
  }
}

///|
fn lane_rank(title : String) -> Int {
  match title {
    "CEO" => 0
    "Engineering" => 1
    "Implementation" => 2
    "Review" => 3
    "QA" => 4
    "Shipping" => 5
    _ => 6
  }
}

///|
fn lane_order_for_node(snapshot : UiSnapshot, node : UiNode) -> Int {
  match node_metadata_int(node, "board_order") {
    Some(order) => order
    None =>
      if node.kind == "ChildRun" {
        match parent_node(snapshot, node) {
          Some(parent) => lane_order_for_node(snapshot, parent)
          None => lane_rank(lane_title_for_node(snapshot, node))
        }
      } else {
        lane_rank(lane_title_for_node(snapshot, node))
      }
  }
}

///|
fn controller_split_node(snapshot : UiSnapshot) -> UiNode? {
  for node in snapshot.nodes {
    if node.kind == "Split" {
      return Some(node)
    }
  }
  None
}

///|
fn controller_merge_node(snapshot : UiSnapshot) -> UiNode? {
  for node in snapshot.nodes {
    if node.kind == "Merge" {
      return Some(node)
    }
  }
  None
}

///|
fn company_lane_entries(snapshot : UiSnapshot) -> Array[CompanyLane] {
  let split = match controller_split_node(snapshot) {
    Some(node) => node
    None => return []
  }
  let lanes : Array[CompanyLane] = []
  for
    step in child_nodes(snapshot, split.id).filter(fn(node) {
      node.kind == "Step"
    }) {
    let title = lane_title_for_node(snapshot, step)
    let key = title.to_lower()
    let order = lane_order_for_node(snapshot, step)
    let entry = {
      step,
      child_runs: child_nodes(snapshot, step.id).filter(fn(node) {
        node.kind == "ChildRun"
      }),
    }
    let mut matched = false
    for i = 0; i < lanes.length(); i = i + 1 {
      if lanes[i].key == key {
        lanes[i] = { ..lanes[i], entries: lanes[i].entries + [entry] }
        matched = true
        break
      }
    }
    if !matched {
      lanes.push({ key, title, order, entries: [entry] })
    }
  }
  lanes.sort_by(fn(left, right) { left.order.compare(right.order) })
  lanes
}

///|
fn render_company_step_stack(
  dispatch : Dispatch[Msg],
  snapshot : UiSnapshot,
  timeline : Array[UiTimelineEntry],
  entry : CompanyLaneEntry,
) -> Html {
  div(class="company-step-stack", [
    render_focus_node_button(dispatch, snapshot, timeline, entry.step),
    if entry.child_runs.is_empty() {
      nothing
    } else {
      div(
        class="company-substack",
        entry.child_runs.map(fn(node) {
          render_focus_node_button(dispatch, snapshot, timeline, node)
        }),
      )
    },
  ])
}

///|
fn render_company_lane(
  dispatch : Dispatch[Msg],
  snapshot : UiSnapshot,
  timeline : Array[UiTimelineEntry],
  lane : CompanyLane,
) -> Html {
  let stats = company_lane_stats(lane)
  let active_title = company_lane_active_title(lane)
  section(class="company-lane", [
    div(class="company-lane-header", [
      div(class="company-lane-title-stack", [
        h3(class="section-title", lane.title),
        if active_title == "" {
          nothing
        } else {
          p(class="muted", "Active: \{active_title}")
        },
      ]),
      div(class="company-lane-header-meta", [
        render_status_badge(company_lane_status(lane)),
        render_meta_chip("tracks", lane.entries.length().to_string()),
      ]),
    ]),
    div(class="company-lane-summary", [
      render_meta_chip("nodes", stats.total.to_string()),
      if stats.live > 0 {
        render_meta_chip("live", stats.live.to_string())
      } else {
        nothing
      },
      if stats.failed > 0 {
        render_meta_chip("failed", stats.failed.to_string())
      } else {
        nothing
      },
      if stats.completed > 0 {
        render_meta_chip("done", stats.completed.to_string())
      } else {
        nothing
      },
    ]),
    div(
      class="company-lane-stack",
      lane.entries.map(fn(entry) {
        render_company_step_stack(dispatch, snapshot, timeline, entry)
      }),
    ),
  ])
}

///|
fn render_company_board(
  dispatch : Dispatch[Msg],
  snapshot : UiSnapshot,
  timeline : Array[UiTimelineEntry],
) -> Html {
  match controller_split_node(snapshot) {
    Some(split) => {
      let lanes = company_lane_entries(snapshot)
      let merge = controller_merge_node(snapshot)
      let stats = company_board_stats(lanes)
      let handoffs = company_handoffs(lanes)
      section(class="company-board", [
        div(class="section-header", [
          h3(class="section-title", "Company Board"),
          div(class="company-board-meta", [
            render_meta_chip("lanes", lanes.length().to_string()),
            render_meta_chip("mode", "parallel roles"),
          ]),
        ]),
        render_company_health_strip(stats),
        div(class="company-board-anchors", [
          render_focus_node_button(dispatch, snapshot, timeline, split),
        ]),
        render_company_lane_sequence(lanes),
        render_company_handoff_row(handoffs),
        div(
          class="company-board-lanes",
          lanes.map(fn(lane) {
            render_company_lane(dispatch, snapshot, timeline, lane)
          }),
        ),
        match merge {
          Some(merge) =>
            div(class="company-board-anchors", [
              render_focus_node_button(dispatch, snapshot, timeline, merge),
            ])
          None => nothing
        },
      ])
    }
    None => nothing
  }
}

///|
fn company_lane_nodes(lane : CompanyLane) -> Array[UiNode] {
  let nodes : Array[UiNode] = []
  for entry in lane.entries {
    nodes.push(entry.step)
    for child in entry.child_runs {
      nodes.push(child)
    }
  }
  nodes
}

///|
fn company_lane_stats(lane : CompanyLane) -> CompanyLaneStats {
  let mut live = 0
  let mut failed = 0
  let mut completed = 0
  let nodes = company_lane_nodes(lane)
  for node in nodes {
    let status = normalize_status(node.status)
    if status.contains("Running") || status.contains("Pending") {
      live = live + 1
    } else if status.contains("Failed") {
      failed = failed + 1
    } else if status.contains("Succeeded") {
      completed = completed + 1
    }
  }
  { live, failed, completed, total: nodes.length() }
}

///|
fn company_lane_status(lane : CompanyLane) -> String {
  let stats = company_lane_stats(lane)
  if stats.live > 0 {
    "\"Running\""
  } else if stats.failed > 0 {
    "\"Failed\""
  } else if stats.completed > 0 {
    "\"Succeeded\""
  } else {
    "\"Pending\""
  }
}

///|
fn company_lane_active_title(lane : CompanyLane) -> String {
  let nodes = company_lane_nodes(lane)
  for node in nodes {
    let status = normalize_status(node.status)
    if status.contains("Running") || status.contains("Pending") {
      return node.title
    }
  }
  ""
}

///|
fn company_board_stats(lanes : Array[CompanyLane]) -> CompanyBoardStats {
  let mut live_lanes = 0
  let mut blocked_lanes = 0
  let mut completed_lanes = 0
  let mut waiting_lanes = 0
  let mut remote_workers = 0
  for lane in lanes {
    let status = normalize_status(company_lane_status(lane))
    if status.contains("Running") {
      live_lanes = live_lanes + 1
    } else if status.contains("Failed") {
      blocked_lanes = blocked_lanes + 1
    } else if status.contains("Succeeded") {
      completed_lanes = completed_lanes + 1
    } else {
      waiting_lanes = waiting_lanes + 1
    }
    for node in company_lane_nodes(lane) {
      if node.kind == "ChildRun" {
        remote_workers = remote_workers + 1
      }
    }
  }
  {
    lane_count: lanes.length(),
    live_lanes,
    blocked_lanes,
    completed_lanes,
    waiting_lanes,
    remote_workers,
  }
}

///|
fn render_company_health_strip(stats : CompanyBoardStats) -> Html {
  div(class="company-health-strip", [
    article(class="company-health-card", [
      p(class="kv-label", "Departments"),
      p(class="node-title", stats.lane_count.to_string()),
    ]),
    article(class="company-health-card", [
      p(class="kv-label", "Active"),
      p(class="node-title", stats.live_lanes.to_string()),
    ]),
    article(class="company-health-card", [
      p(class="kv-label", "Blocked"),
      p(class="node-title", stats.blocked_lanes.to_string()),
    ]),
    article(class="company-health-card", [
      p(class="kv-label", "Waiting"),
      p(class="node-title", stats.waiting_lanes.to_string()),
    ]),
    article(class="company-health-card", [
      p(class="kv-label", "Done"),
      p(class="node-title", stats.completed_lanes.to_string()),
    ]),
    article(class="company-health-card", [
      p(class="kv-label", "Workers"),
      p(class="node-title", stats.remote_workers.to_string()),
    ]),
  ])
}

///|
fn render_company_lane_sequence(lanes : Array[CompanyLane]) -> Html {
  if lanes.is_empty() {
    nothing
  } else {
    let items : Array[Html] = []
    for i = 0; i < lanes.length(); i = i + 1 {
      let lane = lanes[i]
      items.push(
        div(class="company-sequence-chip", [
          span(class="meta-chip", lane.title),
          render_status_badge(company_lane_status(lane)),
        ]),
      )
      if i < lanes.length() - 1 {
        items.push(
          div(class="company-sequence-arrow", [span(class="meta-chip", "then")]),
        )
      }
    }
    div(class="company-sequence", items)
  }
}

///|
fn company_handoffs(lanes : Array[CompanyLane]) -> Array[CompanyHandoff] {
  let handoffs : Array[CompanyHandoff] = []
  if lanes.length() < 2 {
    return handoffs
  }
  for i = 0; i < lanes.length() - 1; i = i + 1 {
    let from_lane = lanes[i]
    let to_lane = lanes[i + 1]
    handoffs.push({
      from_title: from_lane.title,
      to_title: to_lane.title,
      from_status: company_lane_status(from_lane),
      to_status: company_lane_status(to_lane),
      active_title: if company_lane_active_title(to_lane) != "" {
        company_lane_active_title(to_lane)
      } else {
        company_lane_active_title(from_lane)
      },
    })
  }
  handoffs
}

///|
fn render_company_handoff_card(handoff : CompanyHandoff) -> Html {
  article(class="company-handoff-card", [
    div(class="company-handoff-head", [
      span(class="meta-chip", handoff.from_title),
      span(class="company-handoff-arrow", "→"),
      span(class="meta-chip", handoff.to_title),
    ]),
    div(class="company-handoff-status", [
      render_status_badge(handoff.from_status),
      render_status_badge(handoff.to_status),
    ]),
    if handoff.active_title == "" {
      p(class="muted", "Waiting for next handoff")
    } else {
      p(class="muted", "Current baton: \{handoff.active_title}")
    },
  ])
}

///|
fn render_company_handoff_row(handoffs : Array[CompanyHandoff]) -> Html {
  if handoffs.is_empty() {
    nothing
  } else {
    div(
      class="company-handoff-row",
      handoffs.map(fn(handoff) { render_company_handoff_card(handoff) }),
    )
  }
}

///|
fn scoped_timeline(
  model : Model,
  snapshot : UiSnapshot,
) -> Array[UiTimelineEntry] {
  match model.timeline_scope_node_id {
    Some(node_id) =>
      match node_for_id(snapshot, node_id) {
        Some(node) =>
          if model.timeline_scope_branch_only {
            branch_only_timeline_for_node(snapshot, node, model.timeline)
          } else {
            lineage_timeline_for_node(snapshot, node, model.timeline)
          }
        None => model.timeline
      }
    None => model.timeline
  }
}

///|
fn timeline_scope_label(model : Model, snapshot : UiSnapshot) -> String? {
  match model.timeline_scope_node_id {
    Some(node_id) =>
      match node_for_id(snapshot, node_id) {
        Some(node) =>
          Some(
            if model.timeline_scope_branch_only {
              "Branch timeline · \{node.title}"
            } else {
              "Scoped timeline · \{node.title}"
            },
          )
        None => None
      }
    None => None
  }
}

///|
fn render_active_strip(
  dispatch : Dispatch[Msg],
  model : Model,
  snapshot : UiSnapshot,
  timeline : Array[UiTimelineEntry],
  fresh_ids : Array[String],
) -> Html {
  let latest_title = latest_fresh_title(snapshot, timeline, fresh_ids).unwrap_or(
    current_step_title(snapshot),
  )
  section(class="active-strip", [
    p(class="active-strip-label", "Currently Expanding"),
    div(class="active-strip-body", [
      render_status_badge(snapshot.run.status),
      p(class="active-strip-title", latest_title),
      p(class="muted", "Current step: \{current_step_title(snapshot)}"),
      match timeline_scope_label(model, snapshot) {
        Some(label) =>
          div(class="timeline-scope-bar", [
            span(class="meta-chip", label),
            button(
              class="tree-control-button",
              on_click=dispatch(ClearTimelineScope),
              "Clear Scope",
            ),
          ])
        None => nothing
      },
    ]),
  ])
}

///|
fn render_timeline_group(
  dispatch : Dispatch[Msg],
  model : Model,
  group : TimelineGroup,
) -> Html {
  section(class="timeline-group", [
    p(class="timeline-group-title", group.title),
    div(
      class="timeline",
      group.entries.map(fn(entry) {
        let entry_class = timeline_entry_class(model, model.snapshot, entry)
        let badges = timeline_data_badges(entry) +
          timeline_remote_badges(model.snapshot, entry)
        button(
          class=entry_class,
          on_click=timeline_entry_action(dispatch, entry),
          [
            p(class="timeline-title", entry.title),
            p(class="timeline-detail", entry.detail),
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
    ),
  ])
}

///|
fn render_timeline(
  dispatch : Dispatch[Msg],
  model : Model,
  timeline : Array[UiTimelineEntry],
) -> Html {
  if timeline.is_empty() {
    p(class="empty", "No timeline events yet.")
  } else {
    div(
      class="timeline-groups",
      timeline_groups(timeline).map(fn(group) {
        render_timeline_group(dispatch, model, group)
      }),
    )
  }
}

///|
fn render_workspace_panel(snapshot : UiSnapshot) -> Html {
  section(class="panel", [
    header(class="panel-header", [h2(class="panel-title", "Workspace")]),
    div(class="panel-body", [
      div(class="kv", [
        div(class="kv-row", [
          p(class="kv-label", "Run"),
          p(class="mono", snapshot.run.id),
        ]),
        div(class="kv-row", [
          p(class="kv-label", "Job"),
          p(class="mono", snapshot.run.job_id),
        ]),
        div(class="kv-row", [
          p(class="kv-label", "Workspace"),
          p(
            class="mono",
            snapshot.workspace_dir.unwrap_or("No dedicated workspace"),
          ),
        ]),
        div(class="kv-row", [
          p(class="kv-label", "Current step"),
          p(class="mono", snapshot.current_step_id.unwrap_or("pending")),
        ]),
      ]),
    ]),
  ])
}

///|
fn render_artifacts_panel(
  dispatch : Dispatch[Msg],
  snapshot : UiSnapshot,
) -> Html {
  let (starter, other) = partition_starter_artifacts(snapshot.artifacts)
  section(class="panel", [
    header(class="panel-header", [h2(class="panel-title", "Artifacts")]),
    div(class="panel-body", [
      if snapshot.artifacts.is_empty() {
        p(class="empty", "No artifacts yet.")
      } else {
        div(class="artifact-list", [
          if starter.is_empty() {
            nothing
          } else {
            div(class="focus-block starter-artifacts-block", [
              p(class="kv-label", "Starter Docs"),
              p(
                class="muted",
                "Materialized starter files, extracted text, and attachment manifests are grouped here.",
              ),
              div(class="artifact-list", [
                render_starter_docs_card(dispatch, starter),
              ]),
            ])
          },
          if other.is_empty() {
            nothing
          } else {
            div(class="focus-block", [
              p(class="kv-label", "Run Outputs"),
              div(
                class="artifact-list",
                other.map(fn(artifact) {
                  render_artifact_card(dispatch, artifact)
                }),
              ),
            ])
          },
        ])
      },
    ]),
  ])
}

///|
fn render_memory_panel(snapshot : UiSnapshot) -> Html {
  section(class="panel", [
    header(class="panel-header", [h2(class="panel-title", "Memory")]),
    div(class="panel-body", [
      if snapshot.memories.is_empty() {
        p(class="empty", "No captured memories yet.")
      } else {
        div(
          class="memory-list",
          snapshot.memories.map(fn(memory) {
            article(class="memory-card", [
              p(class="node-title", memory.title.unwrap_or(memory.kind)),
              p(class="muted", memory.kind),
              p(class="timeline-detail", memory.content),
            ])
          }),
        )
      },
    ]),
  ])
}

///|
fn render_child_runs_panel(
  dispatch : Dispatch[Msg],
  snapshot : UiSnapshot,
) -> Html {
  let child_runs = child_run_nodes(snapshot)
  section(class="panel", [
    header(class="panel-header", [h2(class="panel-title", "Delegated Runs")]),
    div(class="panel-body", [
      if child_runs.is_empty() {
        p(class="empty", "No delegated runs yet.")
      } else {
        div(
          class="focus-links",
          child_runs.map(fn(node) {
            render_focus_node_button(
              dispatch,
              snapshot,
              snapshot.timeline,
              node,
            )
          }),
        )
      },
    ]),
  ])
}

///|
fn render_recent_changes_panel(
  dispatch : Dispatch[Msg],
  timeline : Array[UiTimelineEntry],
) -> Html {
  let recent = recent_change_entries(timeline)
  section(class="panel", [
    header(class="panel-header", [h2(class="panel-title", "Recent Changes")]),
    div(class="panel-body", [
      if recent.is_empty() {
        p(class="empty", "No recent output changes yet.")
      } else {
        div(
          class="focus-events",
          recent.map(fn(entry) { render_focus_timeline_button(dispatch, entry) }),
        )
      },
    ]),
  ])
}

///|
fn render_right_panel(
  dispatch : Dispatch[Msg],
  model : Model,
  snapshot : UiSnapshot,
) -> Html {
  let button_for = fn(panel : RightPanel, label : String) {
    let active = model.right_panel == panel
    let cls = if active { "run-card active" } else { "run-card" }
    button(class=cls, on_click=dispatch(SelectPanel(panel)), label)
  }
  div(class="side-stack", [
    render_focus_inspector(dispatch, model, snapshot),
    render_linked_remote_panel(snapshot),
    render_child_runs_panel(dispatch, snapshot),
    render_recent_changes_panel(dispatch, model.timeline),
    section(class="panel", [
      header(class="panel-header", [h2(class="panel-title", "Panels")]),
      div(class="panel-body", [
        div(class="runs-list", [
          button_for(Workspace, "Workspace"),
          button_for(Artifacts, "Artifacts"),
          button_for(Memory, "Memory"),
        ]),
      ]),
    ]),
    match model.right_panel {
      Workspace => render_workspace_panel(snapshot)
      Artifacts => render_artifacts_panel(dispatch, snapshot)
      Memory => render_memory_panel(snapshot)
    },
  ])
}

///|
fn artifact_for_node(snapshot : UiSnapshot, node : UiNode) -> UiArtifact? {
  match node.artifact_id {
    Some(artifact_id) => {
      for artifact in snapshot.artifacts {
        if artifact.id == artifact_id {
          return Some(artifact)
        }
      }
      None
    }
    None => None
  }
}

///|
fn memory_for_node(snapshot : UiSnapshot, node : UiNode) -> UiMemory? {
  match node.memory_id {
    Some(memory_id) => {
      for memory in snapshot.memories {
        if memory.id == memory_id {
          return Some(memory)
        }
      }
      None
    }
    None => None
  }
}

///|
fn related_timeline_for_node(
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> Array[UiTimelineEntry] {
  timeline.filter(fn(entry) {
    match node.step_id {
      Some(step_id) => entry.step_id == Some(step_id)
      None =>
        match node.run_id {
          Some(run_id) => entry.run_id == run_id
          None => false
        }
    }
  })
}

///|
fn node_matches_entry(node : UiNode, entry : UiTimelineEntry) -> Bool {
  match node.step_id {
    Some(step_id) => entry.step_id == Some(step_id)
    None =>
      match node.run_id {
        Some(run_id) => entry.run_id == run_id
        None => false
      }
  }
}

///|
fn lineage_timeline_for_node(
  snapshot : UiSnapshot,
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> Array[UiTimelineEntry] {
  let nodes = [node] + descendant_nodes(snapshot, node)
  timeline.filter(fn(entry) {
    nodes.any(fn(candidate) { node_matches_entry(candidate, entry) })
  })
}

///|
fn branch_only_timeline_for_node(
  snapshot : UiSnapshot,
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> Array[UiTimelineEntry] {
  let descendants = descendant_nodes(snapshot, node)
  timeline.filter(fn(entry) {
    descendants.any(fn(candidate) { node_matches_entry(candidate, entry) })
  })
}

///|
fn collect_node_event_stats(
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> NodeEventStats {
  let mut stats = {
    event_count: 0,
    max_attempt: 0,
    metric_events: 0,
    artifact_hits: 0,
    memory_hits: 0,
    workspace_hits: 0,
    failed_events: 0,
  }
  for entry in related_timeline_for_node(node, timeline) {
    stats = { ..stats, event_count: stats.event_count + 1 }
    match entry.data {
      { "attempt": Number(attempt, ..), .. } =>
        if attempt.to_int() > stats.max_attempt {
          stats = { ..stats, max_attempt: attempt.to_int() }
        }
      _ => ()
    }
    match entry.data {
      { "metrics": Object(metrics), .. } if !metrics.is_empty() =>
        stats = { ..stats, metric_events: stats.metric_events + 1 }
      _ => ()
    }
    if entry.event_type.contains("artifact") {
      stats = { ..stats, artifact_hits: stats.artifact_hits + 1 }
    }
    if entry.event_type.contains("memory") {
      stats = { ..stats, memory_hits: stats.memory_hits + 1 }
    }
    if entry.event_type.contains("workspace") {
      stats = { ..stats, workspace_hits: stats.workspace_hits + 1 }
    }
    match entry.status {
      Some(status) if normalize_status(status).contains("Failed") =>
        stats = { ..stats, failed_events: stats.failed_events + 1 }
      _ => ()
    }
  }
  stats
}

///|
fn merge_node_event_stats(
  left : NodeEventStats,
  right : NodeEventStats,
) -> NodeEventStats {
  {
    event_count: left.event_count + right.event_count,
    max_attempt: if left.max_attempt > right.max_attempt {
      left.max_attempt
    } else {
      right.max_attempt
    },
    metric_events: left.metric_events + right.metric_events,
    artifact_hits: left.artifact_hits + right.artifact_hits,
    memory_hits: left.memory_hits + right.memory_hits,
    workspace_hits: left.workspace_hits + right.workspace_hits,
    failed_events: left.failed_events + right.failed_events,
  }
}

///|
fn lineage_event_stats(
  snapshot : UiSnapshot,
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> NodeEventStats {
  let mut stats = collect_node_event_stats(node, timeline)
  for descendant in descendant_nodes(snapshot, node) {
    stats = merge_node_event_stats(
      stats,
      collect_node_event_stats(descendant, timeline),
    )
  }
  stats
}

///|
fn node_event_badges(
  snapshot : UiSnapshot,
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> Array[Html] {
  let direct = collect_node_event_stats(node, timeline)
  let lineage = lineage_event_stats(snapshot, node, timeline)
  let badges : Array[Html] = []
  if direct.max_attempt > 1 {
    badges.push(render_meta_chip("retry", direct.max_attempt.to_string()))
  }
  if normalize_status(node.status).contains("Failed") {
    badges.push(render_meta_chip("state", "failed"))
  }
  if direct.artifact_hits > 0 || node.artifact_id is Some(_) {
    badges.push(render_meta_chip("artifact", direct.artifact_hits.to_string()))
  }
  if direct.memory_hits > 0 || node.memory_id is Some(_) {
    badges.push(render_meta_chip("memory", direct.memory_hits.to_string()))
  }
  if direct.workspace_hits > 0 {
    badges.push(
      render_meta_chip("workspace", direct.workspace_hits.to_string()),
    )
  }
  if lineage.artifact_hits > direct.artifact_hits {
    badges.push(
      render_meta_chip(
        "branch-artifacts",
        (lineage.artifact_hits - direct.artifact_hits).to_string(),
      ),
    )
  }
  if lineage.memory_hits > direct.memory_hits {
    badges.push(
      render_meta_chip(
        "branch-memories",
        (lineage.memory_hits - direct.memory_hits).to_string(),
      ),
    )
  }
  if lineage.failed_events > direct.failed_events {
    badges.push(
      render_meta_chip(
        "branch-failures",
        (lineage.failed_events - direct.failed_events).to_string(),
      ),
    )
  }
  if lineage.max_attempt > direct.max_attempt && lineage.max_attempt > 1 {
    badges.push(
      render_meta_chip("branch-retry", lineage.max_attempt.to_string()),
    )
  }
  badges
}

///|
fn render_node_badges(
  snapshot : UiSnapshot,
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> Html {
  let badges = node_event_badges(snapshot, node, timeline)
  if badges.is_empty() {
    nothing
  } else {
    div(class="timeline-meta", badges)
  }
}

///|
fn render_focus_summary(
  node : UiNode,
  related_events : Array[UiTimelineEntry],
) -> Html {
  let stats = collect_node_event_stats(node, related_events)
  div(class="focus-block", [
    p(class="kv-label", "Event Summary"),
    div(class="inspector-stats", [
      render_meta_chip("events", stats.event_count.to_string()),
      if stats.max_attempt > 1 {
        render_meta_chip("retry", stats.max_attempt.to_string())
      } else {
        nothing
      },
      if stats.metric_events > 0 {
        render_meta_chip("metrics", stats.metric_events.to_string())
      } else {
        nothing
      },
      if stats.artifact_hits > 0 {
        render_meta_chip("artifacts", stats.artifact_hits.to_string())
      } else if node.artifact_id is Some(_) {
        render_meta_chip("artifacts", "1")
      } else {
        nothing
      },
      if stats.memory_hits > 0 {
        render_meta_chip("memories", stats.memory_hits.to_string())
      } else if node.memory_id is Some(_) {
        render_meta_chip("memories", "1")
      } else {
        nothing
      },
      if stats.workspace_hits > 0 {
        render_meta_chip("workspace", stats.workspace_hits.to_string())
      } else {
        nothing
      },
      if stats.failed_events > 0 {
        render_meta_chip("failures", stats.failed_events.to_string())
      } else {
        nothing
      },
    ]),
    p(
      class="muted",
      if related_events.is_empty() {
        "No direct timeline events for this node yet."
      } else if node.kind == "ChildRun" {
        "Delegated branch activity is summarized here before you drill into the branch timeline."
      } else {
        "This summary is derived from direct timeline events tied to the focused node."
      },
    ),
  ])
}

///|
fn descendant_artifacts(
  snapshot : UiSnapshot,
  node : UiNode,
) -> Array[UiArtifact] {
  let artifacts : Array[UiArtifact] = []
  for descendant in descendant_nodes(snapshot, node) {
    match artifact_for_node(snapshot, descendant) {
      Some(artifact) => artifacts.push(artifact)
      None => ()
    }
  }
  artifacts
}

///|
fn descendant_memories(snapshot : UiSnapshot, node : UiNode) -> Array[UiMemory] {
  let memories : Array[UiMemory] = []
  for descendant in descendant_nodes(snapshot, node) {
    match memory_for_node(snapshot, descendant) {
      Some(memory) => memories.push(memory)
      None => ()
    }
  }
  memories
}

///|
fn latest_descendant_artifact(
  snapshot : UiSnapshot,
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> UiArtifact? {
  let artifacts = descendant_artifacts(snapshot, node)
  if artifacts.is_empty() {
    return None
  }
  let _ = timeline
  artifacts.get(artifacts.length() - 1)
}

///|
fn latest_descendant_memory(
  snapshot : UiSnapshot,
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> UiMemory? {
  let memories = descendant_memories(snapshot, node)
  if memories.is_empty() {
    return None
  }
  let _ = timeline
  memories.get(memories.length() - 1)
}

///|
fn recent_change_entries(
  timeline : Array[UiTimelineEntry],
) -> Array[UiTimelineEntry] {
  let recent : Array[UiTimelineEntry] = []
  for i = timeline.length() - 1; i >= 0; i = i - 1 {
    if recent.length() >= 5 {
      break
    }
    let entry = timeline[i]
    if entry.event_type.contains("artifact") ||
      entry.event_type.contains("memory") ||
      entry.event_type.contains("workspace") ||
      entry.event_type.contains("complete") ||
      entry.event_type.contains("spawn") {
      recent.push(entry)
    }
  }
  recent
}

///|
fn render_focus_node_button(
  dispatch : Dispatch[Msg],
  snapshot : UiSnapshot,
  timeline : Array[UiTimelineEntry],
  node : UiNode,
) -> Html {
  let lineage = lineage_event_stats(snapshot, node, timeline)
  button(class="focus-link", on_click=dispatch(FocusNode(node.id)), [
    p(class="node-kind", node.kind),
    p(class="timeline-title", node.title),
    div([render_status_badge(node.status)]),
    div(class="timeline-meta", [
      if lineage.artifact_hits > 0 {
        render_meta_chip("artifacts", lineage.artifact_hits.to_string())
      } else {
        nothing
      },
      if lineage.memory_hits > 0 {
        render_meta_chip("memories", lineage.memory_hits.to_string())
      } else {
        nothing
      },
      if lineage.failed_events > 0 {
        render_meta_chip("failures", lineage.failed_events.to_string())
      } else {
        nothing
      },
      if lineage.max_attempt > 1 {
        render_meta_chip("retry", lineage.max_attempt.to_string())
      } else {
        nothing
      },
    ]),
  ])
}

///|
fn render_focus_timeline_button(
  dispatch : Dispatch[Msg],
  entry : UiTimelineEntry,
) -> Html {
  button(class="focus-event", on_click=dispatch(FocusTimeline(entry.id)), [
    p(class="timeline-title", entry.title),
    p(class="muted", preview_text(entry.detail, 180)),
    div([
      match entry.status {
        Some(status) => render_status_badge(status)
        None => nothing
      },
      span(class="muted mono", "\{entry.timestamp}"),
    ]),
  ])
}

///|
fn render_focus_inspector(
  dispatch : Dispatch[Msg],
  model : Model,
  snapshot : UiSnapshot,
) -> Html {
  match resolved_focus_node_id(model, snapshot) {
    Some(node_id) =>
      match node_for_id(snapshot, node_id) {
        Some(node) => {
          let related_events = related_timeline_for_node(node, model.timeline)
          let lineage_events = lineage_timeline_for_node(
            snapshot,
            node,
            model.timeline,
          )
          let branch_events = lineage_events.filter(fn(entry) {
            !node_matches_entry(node, entry)
          })
          let branch_stats = lineage_event_stats(snapshot, node, model.timeline)
          let artifact = artifact_for_node(snapshot, node)
          let memory = memory_for_node(snapshot, node)
          let branch_artifacts = descendant_artifacts(snapshot, node)
          let (starter_branch_artifacts, other_branch_artifacts) = partition_starter_artifacts(
            branch_artifacts,
          )
          let branch_memories = descendant_memories(snapshot, node)
          let latest_branch_artifact = latest_descendant_artifact(
            snapshot,
            node,
            model.timeline,
          )
          let latest_branch_memory = latest_descendant_memory(
            snapshot,
            node,
            model.timeline,
          )
          let parent = parent_node(snapshot, node)
          let children = child_nodes(snapshot, node.id)
          section(class="panel", [
            header(class="panel-header", [
              h2(class="panel-title", "Focused Node"),
            ]),
            div(class="panel-body", [
              p(class="node-kind", node.kind),
              p(class="node-title", node.title),
              div([render_status_badge(node.status)]),
              div(class="node-meta", [
                render_meta_chip("node", node.id),
                match node.step_id {
                  Some(step_id) => render_meta_chip("step", step_id)
                  None => nothing
                },
                match node.run_id {
                  Some(run_id) => render_meta_chip("run", run_id)
                  None => nothing
                },
              ]),
              if children.is_empty() {
                nothing
              } else {
                div(class="branch-health", [
                  render_meta_chip(
                    "branch-events",
                    branch_stats.event_count.to_string(),
                  ),
                  if branch_stats.artifact_hits > 0 {
                    render_meta_chip(
                      "artifacts",
                      branch_stats.artifact_hits.to_string(),
                    )
                  } else {
                    nothing
                  },
                  if branch_stats.memory_hits > 0 {
                    render_meta_chip(
                      "memories",
                      branch_stats.memory_hits.to_string(),
                    )
                  } else {
                    nothing
                  },
                  if branch_stats.failed_events > 0 {
                    render_meta_chip(
                      "failures",
                      branch_stats.failed_events.to_string(),
                    )
                  } else {
                    nothing
                  },
                  if branch_stats.max_attempt > 1 {
                    render_meta_chip(
                      "retry",
                      branch_stats.max_attempt.to_string(),
                    )
                  } else {
                    nothing
                  },
                ])
              },
              render_focus_summary(node, related_events),
              div(class="inspector-stats", [
                render_meta_chip("children", children.length().to_string()),
                render_meta_chip(
                  "artifact",
                  if artifact is Some(_) {
                    "1"
                  } else {
                    "0"
                  },
                ),
                render_meta_chip(
                  "memory",
                  if memory is Some(_) {
                    "1"
                  } else {
                    "0"
                  },
                ),
              ]),
              match node.summary {
                Some(summary) => p(class="timeline-detail", summary)
                None => nothing
              },
              match node.detail {
                Some(detail) => p(class="muted mono", detail)
                None => nothing
              },
              if normalize_status(node.status).contains("Failed") {
                div(class="focus-block focus-failure", [
                  p(class="kv-label", "Failure"),
                  p(
                    class="timeline-detail",
                    "This node is in a failed state. Check related events below for the latest failure context.",
                  ),
                ])
              } else {
                nothing
              },
              match parent {
                Some(parent) =>
                  div(class="focus-block", [
                    p(class="kv-label", "Parent"),
                    render_focus_node_button(
                      dispatch,
                      snapshot,
                      model.timeline,
                      parent,
                    ),
                  ])
                None => nothing
              },
              if children.is_empty() {
                nothing
              } else {
                div(class="focus-block", [
                  p(class="kv-label", "Children"),
                  div(
                    class="focus-links",
                    children.map(fn(child) {
                      render_focus_node_button(
                        dispatch,
                        snapshot,
                        model.timeline,
                        child,
                      )
                    }),
                  ),
                ])
              },
              match artifact {
                Some(artifact) =>
                  div(class="focus-block", [
                    p(
                      class="kv-label",
                      if starter_artifact(artifact) {
                        "Starter Doc"
                      } else {
                        "Artifact"
                      },
                    ),
                    p(
                      class="timeline-detail",
                      artifact.logical_key.unwrap_or(artifact.artifact_type),
                    ),
                    p(class="mono", artifact.path),
                    p(
                      class="muted",
                      if starter_artifact(artifact) {
                        "Materialized starter-document artifact."
                      } else {
                        "Preview: \{preview_text(artifact.path, 120)}"
                      },
                    ),
                    render_artifact_focus_card(
                      dispatch,
                      artifact,
                      "Open artifact",
                      preview_text(artifact.path, 120),
                    ),
                  ])
                None => nothing
              },
              match memory {
                Some(memory) =>
                  div(class="focus-block", [
                    p(class="kv-label", "Memory"),
                    p(
                      class="timeline-detail",
                      memory.title.unwrap_or(memory.kind),
                    ),
                    p(class="muted", preview_text(memory.content, 220)),
                  ])
                None => nothing
              },
              render_run_linked_remote_panel(snapshot, node),
              if latest_branch_artifact is Some(_) ||
                latest_branch_memory is Some(_) {
                div(class="focus-block", [
                  p(class="kv-label", "Latest Branch Output"),
                  if !starter_branch_artifacts.is_empty() {
                    render_starter_docs_card(dispatch, starter_branch_artifacts)
                  } else {
                    match latest_branch_artifact {
                      Some(artifact) =>
                        render_artifact_focus_card(
                          dispatch,
                          artifact,
                          "Latest artifact",
                          preview_text(artifact.path, 120),
                        )
                      None => nothing
                    }
                  },
                  match latest_branch_memory {
                    Some(memory) =>
                      article(class="memory-card", [
                        p(
                          class="node-title",
                          memory.title.unwrap_or(memory.kind),
                        ),
                        p(class="muted", "Latest memory"),
                        p(
                          class="timeline-detail",
                          preview_text(memory.content, 160),
                        ),
                      ])
                    None => nothing
                  },
                ])
              } else {
                nothing
              },
              if branch_artifacts.is_empty() {
                nothing
              } else {
                div(class="focus-block", [
                  p(class="kv-label", "Descendant Artifacts"),
                  div(
                    class="artifact-list",
                    [
                      if starter_branch_artifacts.is_empty() {
                        nothing
                      } else {
                        render_starter_docs_card(
                          dispatch, starter_branch_artifacts,
                        )
                      },
                    ] +
                    preview_items(other_branch_artifacts, 3).map(fn(artifact) {
                      render_artifact_card(dispatch, artifact)
                    }),
                  ),
                ])
              },
              if branch_memories.is_empty() {
                nothing
              } else {
                div(class="focus-block", [
                  p(class="kv-label", "Descendant Memories"),
                  div(
                    class="memory-list",
                    preview_items(branch_memories, 3).map(fn(memory) {
                      article(class="memory-card", [
                        p(
                          class="node-title",
                          memory.title.unwrap_or(memory.kind),
                        ),
                        p(class="muted", memory.kind),
                        p(
                          class="timeline-detail",
                          preview_text(memory.content, 180),
                        ),
                      ])
                    }),
                  ),
                ])
              },
              if related_events.is_empty() {
                nothing
              } else {
                div(class="focus-block", [
                  p(class="kv-label", "Related Events"),
                  div(
                    class="focus-events",
                    related_events.map(fn(entry) {
                      render_focus_timeline_button(dispatch, entry)
                    }),
                  ),
                ])
              },
              if branch_events.is_empty() {
                nothing
              } else {
                div(class="focus-block", [
                  p(class="kv-label", "Branch Events"),
                  div(
                    class="focus-events",
                    preview_items(branch_events, 5).map(fn(entry) {
                      render_focus_timeline_button(dispatch, entry)
                    }),
                  ),
                ])
              },
            ]),
          ])
        }
        None =>
          section(class="panel", [
            header(class="panel-header", [
              h2(class="panel-title", "Focused Node"),
            ]),
            div(class="panel-body", [
              p(class="empty", "Select a node to inspect it."),
            ]),
          ])
      }
    None =>
      section(class="panel", [
        header(class="panel-header", [h2(class="panel-title", "Focused Node")]),
        div(class="panel-body", [
          p(class="empty", "Select a node to inspect it."),
        ]),
      ])
  }
}

///|
fn render_detail(dispatch : Dispatch[Msg], model : Model) -> Html {
  match model.snapshot {
    Some(snapshot) => {
      let timeline = scoped_timeline(model, snapshot)
      section(class="panel", [
        header(class="panel-header", [
          div(class="detail-header", [
            div([
              p(class="eyebrow", "Generative Expansion"),
              h2(class="detail-title", snapshot.run.job_id),
              p(
                class="subline",
                snapshot.run.summary.unwrap_or(
                  "Expansion tree, execution timeline, and outputs for the selected run.",
                ),
              ),
            ]),
            div(class="canvas-toolbar", [
              button(
                class="tree-control-button",
                on_click=@nav.push_url(
                  run_canvas_url(
                    snapshot.run.id,
                    runs_status_filter=model.runs_status_filter,
                    runs_query=model.runs_query,
                    runs_sort=model.runs_sort,
                    runs_page=model.runs_page,
                  ),
                ),
                "Canvas",
              ),
              render_status_badge(snapshot.run.status),
            ]),
          ]),
        ]),
        div(class="panel-body", [
          if model.detail_loading {
            div(class="refresh-banner", [
              p(class="kv-label", "Live Refresh"),
              p(
                class="timeline-detail",
                "Updating the run snapshot and timeline...",
              ),
            ])
          } else {
            nothing
          },
          match snapshot.run.error {
            Some(error) =>
              div(class="run-error-banner", [
                p(class="kv-label", "Run Error"),
                p(class="timeline-detail", error),
              ])
            None => nothing
          },
          render_company_board(dispatch, snapshot, timeline),
          div(class="detail-grid", [
            section([
              div(class="section-header", [
                h3(class="section-title", "Expansion Tree"),
                render_tree_controls(dispatch),
              ]),
              render_tree(dispatch, model, snapshot),
            ]),
            section([
              h3(class="section-title", "Timeline"),
              render_active_strip(
                dispatch,
                model,
                snapshot,
                timeline,
                model.fresh_timeline_ids,
              ),
              render_timeline(dispatch, model, timeline),
            ]),
          ]),
        ]),
      ])
    }
    None =>
      section(class="panel", [
        header(class="panel-header", [h2(class="panel-title", "Run Detail")]),
        div(class="panel-body", [
          if model.detail_loading {
            p(class="empty", "Loading run detail...")
          } else if model.detail_error is Some(error) {
            p(class="empty", error)
          } else {
            p(
              class="empty",
              "Select a run to inspect how the workflow expanded and executed.",
            )
          },
        ]),
      ])
  }
}
