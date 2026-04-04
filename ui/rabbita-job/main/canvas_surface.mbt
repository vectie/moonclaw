///|
struct CanvasNodeLayout {
  node : UiNode
  x : Int
  y : Int
  width : Int
  height : Int
}

///|
struct CanvasEdgeLayout {
  x1 : Int
  y1 : Int
  x2 : Int
  y2 : Int
  kind : String
}

///|
fn canvas_node_width() -> Int {
  280
}

///|
fn canvas_base_node_height() -> Int {
  132
}

///|
fn canvas_summary_lines(text : String) -> Int {
  let compact = text.trim().to_string()
  if compact == "" {
    1
  } else {
    let approx = (compact.length() + 47) / 48
    if approx < 2 {
      2
    } else if approx > 7 {
      7
    } else {
      approx
    }
  }
}

///|
fn canvas_node_height_for(node : UiNode) -> Int {
  let detail = node.detail.unwrap_or(node.summary.unwrap_or(""))
  let title_lines = if node.title.length() > 42 { 2 } else { 1 }
  let summary_lines = canvas_summary_lines(detail)
  canvas_base_node_height() + (title_lines - 1) * 18 + (summary_lines - 2) * 18
}

///|
fn canvas_column_gap() -> Int {
  130
}

///|
fn canvas_row_gap() -> Int {
  72
}

///|
fn canvas_origin_x() -> Int {
  90
}

///|
fn canvas_origin_y() -> Int {
  90
}

///|
fn canvas_inline_child_gap() -> Int {
  20
}

///|
fn canvas_step_output_node(parent : UiNode, child : UiNode) -> Bool {
  if parent.kind != "Step" || child.kind != "Artifact" {
    return false
  }
  if child.step_id != parent.step_id {
    return false
  }
  let detail = child.detail.unwrap_or("").to_lower()
  detail.contains(".report") ||
  detail.contains(".result") ||
  detail == "report" ||
  detail == "result"
}

///|
fn canvas_child_sort_key(node : UiNode) -> (Int, String, String) {
  let detail = node.detail.unwrap_or("").to_lower()
  let priority = if detail.contains(".report") || detail == "report" {
    0
  } else if detail.contains(".result") || detail == "result" {
    1
  } else if node.kind == "Artifact" {
    2
  } else if node.kind == "Memory" {
    3
  } else if node.kind == "ChildRun" {
    4
  } else {
    5
  }
  (priority, node.kind, node.title)
}

///|
fn canvas_sorted_children(
  snapshot : UiSnapshot,
  parent_id : String,
) -> Array[UiNode] {
  let children = child_nodes(snapshot, parent_id)
  children.sort_by(fn(left, right) {
    canvas_child_sort_key(left).compare(canvas_child_sort_key(right))
  })
  children
}

///|
fn canvas_inline_children(
  snapshot : UiSnapshot,
  node : UiNode,
) -> Array[UiNode] {
  canvas_sorted_children(snapshot, node.id).filter(fn(child) {
    canvas_step_output_node(node, child)
  })
}

///|
fn canvas_stacked_children(
  snapshot : UiSnapshot,
  node : UiNode,
) -> Array[UiNode] {
  canvas_sorted_children(snapshot, node.id).filter(fn(child) {
    !canvas_step_output_node(node, child)
  })
}

///|
fn project_canvas_subtree(
  snapshot : UiSnapshot,
  node : UiNode,
  depth : Int,
  y : Int,
  layouts : Array[CanvasNodeLayout],
) -> Int {
  let height = canvas_node_height_for(node)
  let x = canvas_origin_x() +
    depth * (canvas_node_width() + canvas_column_gap())
  layouts.push(CanvasNodeLayout::{
    node,
    x,
    y,
    width: canvas_node_width(),
    height,
  })

  let inline_children = canvas_inline_children(snapshot, node)
  let mut inline_extent = height
  if !inline_children.is_empty() {
    let mut child_y = y
    for child in inline_children {
      let child_height = canvas_node_height_for(child)
      let child_x = canvas_origin_x() +
        (depth + 1) * (canvas_node_width() + canvas_column_gap())
      layouts.push(CanvasNodeLayout::{
        node: child,
        x: child_x,
        y: child_y,
        width: canvas_node_width(),
        height: child_height,
      })
      let child_bottom = child_y + child_height - y
      if child_bottom > inline_extent {
        inline_extent = child_bottom
      }
      child_y = child_y + child_height + canvas_inline_child_gap()
    }
  }

  let stacked_children = canvas_stacked_children(snapshot, node)
  if stacked_children.is_empty() {
    return inline_extent
  }

  let mut child_y = y + inline_extent + canvas_row_gap()
  for child in stacked_children {
    let subtree_height = project_canvas_subtree(
      snapshot,
      child,
      depth + 1,
      child_y,
      layouts,
    )
    child_y = child_y + subtree_height + canvas_row_gap()
  }
  child_y - y - canvas_row_gap()
}

///|
fn project_canvas_nodes(snapshot : UiSnapshot) -> Array[CanvasNodeLayout] {
  let layouts : Array[CanvasNodeLayout] = []
  let mut current_y = canvas_origin_y()
  let roots = snapshot.nodes.filter(fn(node) { node_is_root(snapshot, node) })
  for root in roots {
    let subtree_height = project_canvas_subtree(
      snapshot, root, 0, current_y, layouts,
    )
    current_y = current_y + subtree_height + canvas_row_gap()
  }
  layouts
}

///|
fn canvas_layout_for_id(
  layouts : Array[CanvasNodeLayout],
  node_id : String,
) -> CanvasNodeLayout? {
  for layout in layouts {
    if layout.node.id == node_id {
      return Some(layout)
    }
  }
  None
}

///|
fn canvas_edge_kind(parent : UiNode, child : UiNode) -> String {
  if child.kind == "ChildRun" {
    "subplan"
  } else if parent.kind == "Step" && child.kind == "Step" {
    "step"
  } else {
    "lineage"
  }
}

///|
fn project_canvas_edges(
  snapshot : UiSnapshot,
  layouts : Array[CanvasNodeLayout],
) -> Array[CanvasEdgeLayout] {
  let edges : Array[CanvasEdgeLayout] = []
  for layout in layouts {
    match layout.node.parent_id {
      Some(parent_id) =>
        match canvas_layout_for_id(layouts, parent_id) {
          Some(parent_layout) =>
            edges.push(CanvasEdgeLayout::{
              x1: parent_layout.x + parent_layout.width,
              y1: parent_layout.y + parent_layout.height / 2,
              x2: layout.x,
              y2: layout.y + layout.height / 2,
              kind: match node_for_id(snapshot, parent_id) {
                Some(parent) => canvas_edge_kind(parent, layout.node)
                None => "lineage"
              },
            })
          None => ()
        }
      None => ()
    }
  }
  edges
}

///|
fn canvas_board_size(layouts : Array[CanvasNodeLayout]) -> (Int, Int) {
  let mut width = 1200
  let mut height = 800
  for layout in layouts {
    let candidate_width = layout.x + layout.width + canvas_origin_x()
    let candidate_height = layout.y + layout.height + canvas_origin_y()
    if candidate_width > width {
      width = candidate_width
    }
    if candidate_height > height {
      height = candidate_height
    }
  }
  (width, height)
}

///|
fn canvas_edge_segment(
  classes : String,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
) -> Html {
  let empty_children : Array[Html] = []
  div(
    class=classes,
    style=[
      "left: \{x}px",
      "top: \{y}px",
      "width: \{width}px",
      "height: \{height}px",
    ],
    empty_children,
  )
}

///|
fn canvas_edge_html(edge : CanvasEdgeLayout) -> Array[Html] {
  let mid_x = (edge.x1 + edge.x2) / 2
  let horizontal_one = canvas_edge_segment(
    "canvas-edge \{edge.kind}",
    edge.x1,
    edge.y1,
    mid_x - edge.x1,
    2,
  )
  let vertical_top = if edge.y1 < edge.y2 { edge.y1 } else { edge.y2 }
  let vertical_height = if edge.y1 < edge.y2 {
    edge.y2 - edge.y1
  } else {
    edge.y1 - edge.y2
  }
  let vertical = canvas_edge_segment(
    "canvas-edge \{edge.kind}",
    mid_x,
    vertical_top,
    2,
    vertical_height + 2,
  )
  let horizontal_two = canvas_edge_segment(
    "canvas-edge \{edge.kind}",
    mid_x,
    edge.y2,
    edge.x2 - mid_x,
    2,
  )
  [horizontal_one, vertical, horizontal_two]
}

///|
fn canvas_starter_artifact_node(node : UiNode) -> Bool {
  if node.kind != "Artifact" {
    return false
  }
  match node.detail {
    Some(detail) =>
      detail == "starter document digest" ||
      detail == "starter document text" ||
      detail == "starter document summary" ||
      detail == "starter attachment manifest"
    None => false
  }
}

///|
fn canvas_node_html(
  dispatch : Dispatch[Msg],
  model : Model,
  snapshot : UiSnapshot,
  layout : CanvasNodeLayout,
) -> Html {
  let node = layout.node
  let base_classes = node_state_class(model, snapshot, node).replace(
    old="tree-node",
    new="canvas-node",
  )
  let classes = if canvas_starter_artifact_node(node) {
    "\{base_classes} starter-doc"
  } else {
    base_classes
  }
  let detail = node.detail.unwrap_or(node.summary.unwrap_or(""))
  let subtitle = if detail.trim().is_empty() { node.kind } else { detail }
  div(
    class=classes,
    style=[
      "left: \{layout.x}px",
      "top: \{layout.y}px",
      "width: \{layout.width}px",
      "height: \{layout.height}px",
    ],
    [
      div(class="canvas-node-head", [
        span(class="canvas-node-kind", node.kind),
        render_status_badge(node.status),
      ]),
      button(class="canvas-node-focus", on_click=dispatch(FocusNode(node.id)), [
        p(class="canvas-node-title", node.title),
        p(class="canvas-node-summary", subtitle),
      ]),
    ],
  )
}

///|
fn flatten_canvas_edges(edges : Array[CanvasEdgeLayout]) -> Array[Html] {
  let items : Array[Html] = []
  for edge in edges {
    for item in canvas_edge_html(edge) {
      items.push(item)
    }
  }
  items
}

///|
fn render_run_canvas(dispatch : Dispatch[Msg], model : Model) -> Html {
  match model.snapshot {
    Some(snapshot) => {
      let layouts = project_canvas_nodes(snapshot)
      let edges = project_canvas_edges(snapshot, layouts)
      let (board_width, board_height) = canvas_board_size(layouts)
      let zoom = model.canvas_zoom
      let empty_children : Array[Html] = []
      section(class="panel canvas-panel", [
        header(class="panel-header", [
          div(class="detail-header", [
            div([
              p(class="eyebrow", "Infinite Canvas"),
              h2(class="detail-title", snapshot.run.job_id),
              p(
                class="subline",
                "Graph projection of the current run tree. Scroll to pan, use zoom controls to inspect branches.",
              ),
            ]),
            div(class="canvas-toolbar", [
              button(
                class="tree-control-button",
                on_click=@nav.push_url(
                  run_url(
                    snapshot.run.id,
                    runs_status_filter=model.runs_status_filter,
                    runs_query=model.runs_query,
                    runs_sort=model.runs_sort,
                    runs_page=model.runs_page,
                  ),
                ),
                "Detail",
              ),
              button(
                class="tree-control-button",
                on_click=dispatch(CanvasZoomOut),
                "−",
              ),
              span(class="gateway-chip", "\{zoom}%"),
              button(
                class="tree-control-button",
                on_click=dispatch(CanvasZoomIn),
                "+",
              ),
              button(
                class="tree-control-button",
                on_click=dispatch(CanvasZoomReset),
                "Reset",
              ),
            ]),
          ]),
        ]),
        div(class="panel-body canvas-panel-body", [
          div(class="canvas-hint-row", [
            span(class="meta-chip", "Nodes: \{layouts.length()}"),
            span(class="meta-chip", "Edges: \{edges.length()}"),
            span(class="meta-chip", "Pan: scroll / trackpad"),
          ]),
          div(class="canvas-viewport", [
            div(
              class="canvas-board",
              style=[
                "width: \{board_width}px",
                "height: \{board_height}px",
                "transform: scale(\{zoom.to_double() / 100.0})",
                "transform-origin: top left",
              ],
              [
                div(class="canvas-grid", empty_children),
                div(class="canvas-layer edges", flatten_canvas_edges(edges)),
                div(
                  class="canvas-layer nodes",
                  layouts.map(fn(layout) {
                    canvas_node_html(dispatch, model, snapshot, layout)
                  }),
                ),
              ],
            ),
          ]),
        ]),
      ])
    }
    None =>
      section(class="panel canvas-panel", [
        header(class="panel-header", [
          h2(class="panel-title", "Infinite Canvas"),
        ]),
        div(class="panel-body", [
          if model.detail_loading {
            p(class="empty", "Loading run canvas...")
          } else {
            p(class="empty", "Select a run to open its canvas projection.")
          },
        ]),
      ])
  }
}
