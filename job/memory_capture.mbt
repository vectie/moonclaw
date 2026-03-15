///|
fn json_string_field(config : Json, key : String) -> String? {
  match config {
    Object(obj) =>
      match obj.get(key) {
        Some(String(value)) => Some(value)
        _ => None
      }
    _ => None
  }
}

///|
fn compiled_job_workspace(definition : JobDefinition) -> String? {
  json_string_field(definition.config, "workspace")
}

///|
fn compiled_job_family(definition : JobDefinition) -> String? {
  json_string_field(definition.config, "family")
}

///|
fn compiled_job_template(definition : JobDefinition) -> String? {
  json_string_field(definition.config, "template")
}

///|
fn compiled_job_memory_scope(
  definition : JobDefinition,
  extra_scope? : Array[String] = [],
) -> Array[String] {
  let scope = ["jobs", "job:\{definition.id}"]
  match compiled_job_family(definition) {
    Some(family) if !family.is_blank() => scope.push(family)
    _ => ()
  }
  match compiled_job_template(definition) {
    Some(template) if !template.is_blank() => scope.push("template:\{template}")
    _ => ()
  }
  for item in extra_scope {
    if !scope.contains(item) {
      scope.push(item)
    }
  }
  scope
}

///|
fn summarize_memory_content(
  content : String,
  max_chars? : Int = 4000,
) -> String {
  let trimmed = content.trim().to_string()
  if trimmed.length() <= max_chars {
    trimmed
  } else {
    trimmed[:max_chars].to_string()
  }
}

///|
fn report_like_artifact(artifact : ArtifactRecord) -> Bool {
  artifact.artifact_type.has_suffix(".report") ||
  artifact.content_type.has_prefix("text/")
}

///|
fn report_memory_title(
  _definition : JobDefinition,
  artifact : ArtifactRecord,
) -> String {
  let label = artifact.logical_key.unwrap_or(artifact.artifact_type)
  "Job report: \{label}"
}

///|
pub async fn capture_successful_run_memories(
  store : SystemStore,
  definition : JobDefinition,
  run : JobRun,
  now_ms : Int,
) -> Array[MemoryRecord] {
  guard run.status is Succeeded else { return [] }
  let target = parse_job_notify_target(definition.config)
  let workspace = match run.workspace_dir {
    Some(workspace_dir) => Some(workspace_dir)
    None => compiled_job_workspace(definition)
  }
  let family = compiled_job_family(definition)
  let template = compiled_job_template(definition)
  let tags = [definition.kind, ..definition.tags]
  let tags = match family {
    Some(family) if !tags.contains(family) => [..tags, family]
    _ => tags
  }
  let tags = match template {
    Some(template) if !tags.contains(template) => [..tags, template]
    _ => tags
  }
  let memories = MemoryService::new(store~)
  let saved : Array[MemoryRecord] = []

  match run.summary {
    Some(summary) if !summary.trim().to_string().is_blank() =>
      saved.push(
        memories.remember(
          MemoryWriteRequest::new(
            kind="job.summary",
            title=Some("Job summary: \{definition.id}"),
            content=summarize_memory_content(summary),
            metadata={
              "job_id": definition.id,
              "run_id": run.id,
              "status": run.status.to_json(),
              "family": family,
              "template": template,
            },
            tags~,
            scope=compiled_job_memory_scope(definition),
            workspace~,
            channel_id=target.map(fn(target) { target.channel_id }),
            account_id=target.map(fn(target) { target.account_id }),
            recipient=target.map(fn(target) { target.recipient }),
            thread_id=target.bind(fn(target) { target.thread_id }),
          ),
          "memory.run.\{run.id}.summary",
          now_ms,
        ),
      )
    _ => ()
  }

  let artifacts = ArtifactStore::new(store~)
  let reports = artifacts.list(
    query=ArtifactQuery::new(
      run_id=Some(run.id),
      status=Some(ArtifactStatus::Active),
    ),
  )
  for artifact in reports {
    guard report_like_artifact(artifact) else { continue }
    match artifacts.read_text(artifact.id) {
      Some(content) if !content.trim().to_string().is_blank() =>
        saved.push(
          memories.remember(
            MemoryWriteRequest::new(
              kind="job.report",
              title=Some(report_memory_title(definition, artifact)),
              content=summarize_memory_content(content),
              metadata={
                "job_id": definition.id,
                "run_id": run.id,
                "artifact_id": artifact.id,
                "artifact_type": artifact.artifact_type,
                "logical_key": artifact.logical_key,
                "family": family,
                "template": template,
              },
              tags~,
              scope=compiled_job_memory_scope(
                definition,
                extra_scope=artifact.scope,
              ),
              workspace~,
              channel_id=target.map(fn(target) { target.channel_id }),
              account_id=target.map(fn(target) { target.account_id }),
              recipient=target.map(fn(target) { target.recipient }),
              thread_id=target.bind(fn(target) { target.thread_id }),
              source_artifact_id=Some(artifact.id),
            ),
            "memory.run.\{run.id}.artifact.\{artifact.id}",
            now_ms,
          ),
        )
      _ => ()
    }
  }
  saved
}
