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
