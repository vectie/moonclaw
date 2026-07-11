///|
fn provider_task_required_research_artifacts() -> Array[String] {
  [
    "raw/bootstrap/research-question.md", "raw/bootstrap/search-log.md", "raw/bootstrap/source-screen.md",
    "raw/bootstrap/local-sources.md", "raw/bootstrap/evidence-matrix.md", "raw/bootstrap/synthesis-brief.md",
    "raw/bootstrap/deep-report.md",
  ]
}

///|
async fn provider_task_existing_research_artifacts(
  workspace_root : String,
) -> Array[String] {
  let present : Array[String] = []
  for path in provider_task_required_research_artifacts() {
    let absolute = @pathx.join(workspace_root, path)
    if (@fsx.exists(absolute) catch { _ => false }) {
      present.push(path)
    }
  }
  present
}

///|
fn provider_task_research_dossier_needed(task : ProviderTaskSpec) -> Bool {
  task.kind.trim().to_lower() == "bootstrap_gather"
}

///|
fn provider_task_markdown_list(items : Array[String]) -> String {
  if items.is_empty() {
    "- none"
  } else {
    items.map(fn(item) { "- \{item}" }).join("\n")
  }
}

///|
fn provider_task_research_topic(context : ProviderTaskWorkerContext) -> String {
  let base = if context.book_id.is_blank() {
    context.task_id
  } else {
    context.book_id
  }
  let trimmed = if base.has_prefix("research-") { base[9:] } else { base }
  let topic = trimmed.trim().to_owned()
  if topic.is_blank() {
    "research topic"
  } else {
    topic
  }
}

///|
fn provider_task_research_question_summary(
  content : String,
  fallback : String,
) -> String {
  for line in content.split("\n") {
    let trimmed = line.trim().to_owned()
    if trimmed.contains("- Research question:") {
      let parts = trimmed.split("- Research question:").collect()
      if parts.length() > 1 {
        return provider_task_trim_research_clause(parts[1].trim().to_owned())
      }
    }
    if trimmed.contains("Research question:") {
      let parts = trimmed.split("Research question:").collect()
      if parts.length() > 1 {
        return provider_task_trim_research_clause(parts[1].trim().to_owned())
      }
    }
  }
  if !fallback.trim().is_blank() {
    fallback.trim().to_owned()
  } else if !content.trim().is_blank() {
    provider_task_first_nonblank_lines(content, 3)
  } else {
    "Produce source-backed research coverage with explicit evidence and known gaps."
  }
}

///|
fn provider_task_trim_research_clause(text : String) -> String {
  let stop_markers = [
    " - Quality bar:", " - Required durable outputs:", " - Required raw outputs:",
    " - Output contract:", " - Mode:",
  ]
  let mut value = text.trim().to_owned()
  for marker in stop_markers {
    let parts = value.split(marker).collect()
    if parts.length() > 1 {
      value = parts[0].trim().to_owned()
    }
  }
  if value.is_blank() {
    "Produce source-backed research coverage with explicit evidence and known gaps."
  } else {
    value
  }
}

///|
fn provider_task_first_nonblank_lines(content : String, limit : Int) -> String {
  let lines : Array[String] = []
  for line in content.split("\n") {
    let trimmed = line.trim()
    if trimmed.is_blank() {
      continue
    }
    lines.push(trimmed.to_owned())
    if lines.length() >= limit {
      break
    }
  }
  if lines.is_empty() {
    "(file had no non-blank preview lines)"
  } else {
    lines.join(" ")
  }
}

///|
async fn provider_task_local_source_notes(
  workspace_root : String,
  local_paths : Array[String],
) -> Array[String] {
  let notes : Array[String] = []
  let mut i = 0
  while i < local_paths.length() {
    if provider_task_cancellation_requested() {
      notes.push(
        "L\{i + 1}: status=cancelled reason=\{provider_task_cancelled_error()}",
      )
      return notes
    }
    let original = local_paths[i]
    let mounted_alias = if @pathx.is_absolute(original) {
      source_hint_mounted_relative_path(original)
    } else {
      original
    }
    let mounted_absolute = @pathx.join(workspace_root, mounted_alias)
    let original_absolute = original
    let mounted_exists = @fsx.exists(mounted_absolute) catch { _ => false }
    let original_exists = @pathx.is_absolute(original_absolute) &&
      (@fsx.exists(original_absolute) catch { _ => false })
    let read_path = if mounted_exists {
      mounted_absolute
    } else {
      original_absolute
    }
    let exists = mounted_exists || original_exists
    let preview = if exists {
      let content = @fsx.read_file(read_path) catch { _ => "(read failed)" }
      provider_task_first_nonblank_lines(content, 3)
    } else {
      "(mounted alias missing or unreadable)"
    }
    let status = if exists { "included" } else { "blocked" }
    notes.push(
      "L\{i + 1}: original=`\{original}` alias=`\{mounted_alias}` status=\{status} preview=\{preview}",
    )
    i += 1
  }
  notes
}

///|
fn provider_task_limited_strings(
  items : Array[String],
  limit : Int,
) -> Array[String] {
  let limited : Array[String] = []
  let mut i = 0
  while i < items.length() && i < limit {
    limited.push(items[i])
    i += 1
  }
  limited
}

///|
fn provider_task_add_unique(items : Array[String], item : String) -> Unit {
  let trimmed = item.trim().to_owned()
  if !trimmed.is_blank() && !items.contains(trimmed) {
    items.push(trimmed)
  }
}

///|
fn provider_task_github_raw_readme_candidates(url : String) -> Array[String] {
  let marker = "github.com/"
  guard url.contains(marker) else { return [] }
  let start = match url.find(marker) {
    Some(index) => index + marker.length()
    None => return []
  }
  let after_host = url[start:].to_owned()
  let without_query = match after_host.find("?") {
    Some(index) => after_host[:index].to_owned()
    None => after_host
  }
  let rest = match without_query.find("#") {
    Some(index) => without_query[:index].to_owned()
    None => without_query
  }
  let parts : Array[String] = []
  for part in rest.split("/") {
    let value = part.trim().to_owned()
    if !value.is_blank() {
      parts.push(value)
    }
  }
  guard parts.length() >= 2 else { return [] }
  let owner = parts[0]
  let repo = parts[1].replace_all(old=".git", new="")
  [
    "https://raw.githubusercontent.com/\{owner}/\{repo}/main/README.mbt.md",
    "https://raw.githubusercontent.com/\{owner}/\{repo}/main/README.md",
    "https://raw.githubusercontent.com/\{owner}/\{repo}/master/README.mbt.md",
    "https://raw.githubusercontent.com/\{owner}/\{repo}/master/README.md",
  ]
}

///|
fn provider_task_fetch_url_candidates(
  high_signal_urls : Array[String],
  discovered_urls : Array[String],
) -> Array[String] {
  let urls : Array[String] = []
  for url in high_signal_urls {
    for candidate in provider_task_github_raw_readme_candidates(url) {
      provider_task_add_unique(urls, candidate)
    }
    provider_task_add_unique(urls, url)
  }
  for url in discovered_urls {
    for candidate in provider_task_github_raw_readme_candidates(url) {
      provider_task_add_unique(urls, candidate)
    }
    provider_task_add_unique(urls, url)
  }
  urls
}

///|
async fn provider_task_web_source_notes(
  web_queries : Array[String],
  high_signal_urls : Array[String],
  web_search_enabled~ : Bool,
  web_fetch_enabled~ : Bool,
) -> Array[String] {
  let notes : Array[String] = []
  let discovered_urls : Array[String] = []
  let mut next_id = 1
  if web_search_enabled {
    let search_tool = @web_search.new()
    for query in provider_task_limited_strings(web_queries, 4) {
      if provider_task_cancellation_requested() {
        notes.push(
          "W\{next_id}: status=cancelled tool=web_search reason=\{provider_task_cancelled_error()}",
        )
        return notes
      }
      let result = search_tool.call({ "query": query, "max_results": 5 })
      match result {
        Ok(output) => {
          match output.answer {
            Some(answer) if !answer.trim().is_blank() => {
              notes.push(
                "W\{next_id}: query=`\{query}` status=searched answer=\{provider_task_first_nonblank_lines(answer, 2)}",
              )
              next_id += 1
            }
            _ => ()
          }
          for item in output.results {
            if !discovered_urls.contains(item.url) {
              discovered_urls.push(item.url)
            }
            notes.push(
              "W\{next_id}: query=`\{query}` status=searched title=`\{item.title}` url=`\{item.url}` snippet=\{provider_task_first_nonblank_lines(item.snippet, 2)}",
            )
            next_id += 1
            if next_id > 12 {
              break
            }
          }
        }
        Error(_, message) => {
          notes.push(
            "W\{next_id}: query=`\{query}` status=blocked tool=web_search reason=\{provider_task_first_nonblank_lines(message, 2)}",
          )
          next_id += 1
        }
      }
      if next_id > 12 {
        break
      }
    }
  } else if !web_queries.is_empty() {
    notes.push(
      "W\{next_id}: status=blocked tool=web_search reason=web_search was not enabled by the provider runtime",
    )
    next_id += 1
  }
  let fetch_urls = provider_task_fetch_url_candidates(
    high_signal_urls, discovered_urls,
  )
  if web_fetch_enabled {
    let fetch_tool = @web_fetch.new()
    for url in provider_task_limited_strings(fetch_urls, 6) {
      if provider_task_cancellation_requested() {
        notes.push(
          "W\{next_id}: status=cancelled tool=web_fetch reason=\{provider_task_cancelled_error()}",
        )
        return notes
      }
      let result = fetch_tool.call({ "url": url, "max_chars": 1800 })
      match result {
        Ok(output) => {
          let title = output.title.unwrap_or(output.final_url)
          notes.push(
            "W\{next_id}: url=`\{output.final_url}` status=fetched title=`\{title}` snippet=\{provider_task_first_nonblank_lines(output.text, 4)}",
          )
          next_id += 1
        }
        Error(_, message) => {
          notes.push(
            "W\{next_id}: url=`\{url}` status=blocked tool=web_fetch reason=\{provider_task_first_nonblank_lines(message, 2)}",
          )
          next_id += 1
        }
      }
      if next_id > 18 {
        break
      }
    }
  } else if !fetch_urls.is_empty() {
    notes.push(
      "W\{next_id}: status=blocked tool=web_fetch reason=web_fetch was not enabled by the provider runtime",
    )
  }
  notes
}

///|
async fn provider_task_write_research_dossier_if_needed(
  task : ProviderTaskSpec,
  context : ProviderTaskWorkerContext,
  web_search_enabled~ : Bool,
  web_fetch_enabled~ : Bool,
) -> Array[String] {
  if !provider_task_research_dossier_needed(task) ||
    !provider_task_research_contract_requested(task, context) {
    return provider_task_existing_research_artifacts(context.workspace_root)
  }
  let existing = provider_task_existing_research_artifacts(
    context.workspace_root,
  )
  if existing.length() == provider_task_required_research_artifacts().length() {
    return existing
  }
  let raw_bootstrap = @pathx.join(context.workspace_root, "raw")
    |> @pathx.join("bootstrap")
  @fsx.make_directory(raw_bootstrap, recursive=true) catch {
    _ => ()
  }
  let request_path = @pathx.join(raw_bootstrap, "RESEARCH_REQUEST.md")
  let hints_path = @pathx.join(raw_bootstrap, "SOURCE_HINTS.md")
  let request_content = @fsx.read_file(request_path) catch { _ => "" }
  let hints_content = @fsx.read_file(hints_path) catch { _ => "" }
  let web_queries = provider_task_markdown_bullet_section(
    hints_content, "Web Search First",
  )
  let high_signal_urls = provider_task_markdown_bullet_section(
    hints_content, "High-Signal URLs",
  )
  let local_paths = provider_task_markdown_bullet_section(
    hints_content, "Local Repository Follow-Up",
  )
  let local_notes = provider_task_local_source_notes(
    context.workspace_root,
    local_paths,
  )
  let web_notes = provider_task_web_source_notes(
    web_queries,
    high_signal_urls,
    web_search_enabled~,
    web_fetch_enabled~,
  )
  let topic = provider_task_research_topic(context)
  let materialization_targets = provider_task_markdown_bullet_section(
    hints_content, "Materialization Target",
  )
  let write = async fn(path : String, content : String) -> Unit {
    let absolute = @pathx.join(context.workspace_root, path)
    if (@fsx.exists(absolute) catch { _ => false }) {
      return
    }
    @fsx.write_to_file(absolute, content)
  }
  let included_notes : Array[String] = []
  let blocked_notes : Array[String] = []
  let evidence_rows : Array[String] = [
    "| Source ID | Evidence | Confidence | Gap or contradiction |", "| --- | --- | --- | --- |",
  ]
  let mut has_blocked_notes = false
  for note in local_notes {
    if note.contains("status=included") {
      included_notes.push(note)
    }
    if note.contains("status=blocked") {
      blocked_notes.push(note)
      has_blocked_notes = true
    }
    let source_parts = note.split(":").collect()
    let source_id = source_parts[0]
    let sanitized_note = note.replace_all(old="|", new="/")
    evidence_rows.push(
      "| \{source_id} | \{sanitized_note} | Medium | Needs human/model synthesis before durable ontology promotion. |",
    )
  }
  for note in web_notes {
    let source_parts = note.split(":").collect()
    let source_id = source_parts[0]
    let sanitized_note = note.replace_all(old="|", new="/")
    evidence_rows.push(
      "| \{source_id} | \{sanitized_note} | Medium | Web evidence captured by provider tool path or explicit tool blocker. |",
    )
  }
  write(
    "raw/bootstrap/research-question.md",
    [
      "# Research Question",
      "",
      "Task: \{task.title}",
      "",
      "Question:",
      provider_task_research_question_summary(request_content, context.prompt),
      "",
      "Success criteria:",
      provider_task_markdown_list(materialization_targets),
    ].join("\n"),
  )
  write(
    "raw/bootstrap/search-log.md",
    [
      "# Search Log",
      "",
      "Web queries requested by the provider packet:",
      provider_task_markdown_list(web_queries),
      "",
      "High-signal URLs requested by the provider packet:",
      provider_task_markdown_list(high_signal_urls),
      "",
      "Web evidence gathered by provider tools:",
      provider_task_markdown_list(web_notes),
      "",
      "Local source aliases inspected before launching model substeps:",
      provider_task_markdown_list(local_notes),
      "",
      "Note: this bootstrap file records the executable search plan, local inspection state, and any web-source limitations exposed by the provider runtime.",
    ].join("\n"),
  )
  write(
    "raw/bootstrap/source-screen.md",
    [
      "# Source Screen",
      "",
      "Included local candidates:",
      provider_task_markdown_list(included_notes),
      "",
      "Blocked local candidates:",
      provider_task_markdown_list(blocked_notes),
      "",
      "Fetched web evidence and explicit web blockers:",
      provider_task_markdown_list(web_notes),
      "",
      "Screening rule: candidate inventories are not durable source coverage until a follow-up materialization pass digests inspected evidence with provenance.",
    ].join("\n"),
  )
  write(
    "raw/bootstrap/local-sources.md",
    [
      "# Local Sources",
      "",
      "Mounted source manifest: `mounted-sources/MANIFEST.md`",
      "",
      provider_task_markdown_list(local_notes),
    ].join("\n"),
  )
  write(
    "raw/bootstrap/evidence-matrix.md",
    ["# Evidence Matrix", "", ..evidence_rows].join("\n"),
  )
  write(
    "raw/bootstrap/synthesis-brief.md",
    [
      "# Synthesis Brief",
      "",
      "Topic: \{topic}",
      "",
      "Verified findings:",
      "- \{topic} local source hints were mounted and inspected through workspace aliases where available.",
      "",
      "Web verification status:",
      if web_notes.is_empty() {
        "- No web queries or high-signal URLs were provided by the packet."
      } else {
        "- Web search/fetch results or explicit web-access blockers are recorded with W-source IDs in `search-log.md`, `source-screen.md`, and `evidence-matrix.md`."
      },
      "",
      "Blockers:",
      if has_blocked_notes {
        "- One or more local source aliases were missing or unreadable; see `source-screen.md`."
      } else {
        "- none detected during local preflight."
      },
      "",
      "Next materialization:",
      provider_task_markdown_list(materialization_targets),
    ].join("\n"),
  )
  provider_task_existing_research_artifacts(context.workspace_root)
}
