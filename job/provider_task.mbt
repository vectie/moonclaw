///|
/// Provider-backed extension task runtime.
/// It lets workspace-local providers shape domain work while MoonClaw keeps
/// execution, artifacts, lineage, and operator visibility generic.
///
fn provider_task_substep_prompt(task : ProviderTaskSpec) -> String {
  let target_lines = if task.target_pages.is_empty() {
    "No explicit target pages were declared."
  } else {
    join_bullets(task.target_pages)
  }
  [
    task.prompt,
    "",
    "Provider-owned narrowed execution task:",
    "- task_id: \{provider_task_result_task_id(task)}",
    "- task_kind: \{task.kind}",
    "",
    "Declared target surfaces:",
    target_lines,
    "",
    "Execute this narrowed task directly. Do not expand back into a broad plan unless you hit a concrete blocker.",
  ].join("\n")
}

///|
fn provider_task_followup_execution_tasks(
  batch : ProviderTaskBatch,
  current_task : ProviderTaskSpec,
) -> Array[ProviderTaskSpec] {
  let execution_tasks = provider_task_execution_tasks(batch.tasks)
  let mut selected_index : Int? = None
  let mut index = 0
  while index < execution_tasks.length() {
    if execution_tasks[index].id == current_task.id {
      selected_index = Some(index)
      break
    }
    index += 1
  }
  match selected_index {
    Some(index) => execution_tasks[index + 1:].iter().to_array()
    None => []
  }
}

///|
fn provider_task_followup_substeps(
  batch : ProviderTaskBatch,
  current_task : ProviderTaskSpec,
) -> Array[AdaptiveSubstepPayload] {
  provider_task_followup_execution_tasks(batch, current_task).map(fn(task) {
    {
      title: task.title,
      prompt: provider_task_substep_prompt(task),
      kind: Some("job.analysis"),
    }
  })
}

///|
async fn provider_task_bootstrap_packet_paths(
  workspace_root : String,
) -> Array[String] {
  let packet_dir = @pathx.join(workspace_root, "raw")
    |> @pathx.join("bootstrap")
  let entries = @fsx.list_directory(packet_dir) catch { _ => return [] }
  let packets : Array[String] = []
  for entry in entries {
    guard entry.kind is Regular else { continue }
    guard entry.name.has_suffix(".md") else { continue }
    if entry.name == "RESEARCH_REQUEST.md" || entry.name == "SOURCE_HINTS.md" {
      continue
    }
    packets.push(@pathx.join("raw/bootstrap", entry.name))
  }
  packets.sort()
  packets
}

///|
fn provider_task_extract_candidate_pages_from_markdown(
  content : String,
  prefixes : Array[String],
) -> Array[String] {
  let pages : Array[String] = []
  for raw_line in content.split("\n") {
    for path in provider_task_artifact_paths_from_line(raw_line.to_owned()) {
      if prefixes.iter().any(fn(prefix) { path.has_prefix(prefix) }) &&
        path.has_suffix(".md") &&
        !pages.contains(path) {
        pages.push(path)
      }
    }
  }
  pages
}

///|
async fn provider_task_packet_candidate_pages(
  workspace_root : String,
  prefixes : Array[String],
) -> (Array[String], Array[String]) {
  let packets = provider_task_bootstrap_packet_paths(workspace_root)
  let pages : Array[String] = []
  for packet in packets {
    let absolute = @pathx.join(workspace_root, packet)
    let content = @fsx.read_file(absolute) catch { _ => continue }
    for
      page in provider_task_extract_candidate_pages_from_markdown(
        content, prefixes,
      ) {
      if !pages.contains(page) {
        pages.push(page)
      }
    }
  }
  (packets, pages)
}

///|
fn provider_task_markdown_bullet_section(
  content : String,
  heading : String,
) -> Array[String] {
  let section = heading.trim().to_lower()
  let items : Array[String] = []
  let mut in_section = false
  for raw_line in content.split("\n") {
    let line = raw_line.trim().to_owned()
    if line.has_prefix("## ") {
      let normalized = line[3:].trim().to_lower()
      if in_section && normalized != section {
        break
      }
      in_section = normalized == section
      continue
    }
    if !in_section {
      continue
    }
    if line.has_prefix("- ") {
      let item = line[2:].trim().to_owned()
      if !item.is_blank() {
        items.push(item)
      }
    }
  }
  items
}

///|
fn provider_task_chunk_strings(
  items : Array[String],
  chunk_size : Int,
) -> Array[Array[String]] {
  if items.is_empty() || chunk_size <= 0 {
    return []
  }
  let chunks : Array[Array[String]] = []
  let mut start = 0
  while start < items.length() {
    let end_ = Int::min(start + chunk_size, items.length())
    chunks.push(items[start:end_].to_owned())
    start = end_
  }
  chunks
}

///|
async fn provider_task_bootstrap_source_hints(
  workspace_root : String,
) -> Array[String] {
  let path = @pathx.join(workspace_root, "raw")
    |> @pathx.join("bootstrap")
    |> @pathx.join("SOURCE_HINTS.md")
  let content = @fsx.read_file(path) catch { _ => return [] }
  let resolved : Array[String] = []
  for
    source_path in provider_task_markdown_bullet_section(
      content, "Local Repository Follow-Up",
    ) {
    let source_exists = @fsx.exists(source_path) catch { _ => false }
    resolved.push(
      if source_exists && @pathx.is_absolute(source_path) {
        source_hint_mounted_relative_path(source_path)
      } else {
        source_path
      },
    )
  }
  resolved
}

///|
fn provider_task_mounted_source_section(paths : Array[String]) -> String {
  if paths.is_empty() {
    [
      "Mounted local source aliases:", "- none detected", "", "If `raw/bootstrap/SOURCE_HINTS.md` lists absolute paths, first check `mounted-sources/MANIFEST.md` for safe aliases before declaring those paths inaccessible.",
    ].join("\n")
  } else {
    [
      "Mounted local source aliases:",
      "- mounted-sources/MANIFEST.md",
      ..paths.map(fn(path) { "- \{path}" }),
      "",
      "Use these mounted aliases instead of the original absolute hint paths. Treat an absolute path as blocked only after its mounted alias is missing or unreadable.",
    ].join("\n")
  }
}

///|
fn provider_task_research_contract_requested(
  task : ProviderTaskSpec,
  context : ProviderTaskWorkerContext,
) -> Bool {
  let combined = [
      task.title,
      task.prompt,
      task.kind,
      context.prompt,
      context.output_contract.join("\n"),
      context.skill_paths.join("\n"),
    ]
    .join("\n")
    .to_lower()
  combined.contains("raw/bootstrap/research-question.md") ||
  combined.contains("raw/bootstrap/evidence-matrix.md") ||
  combined.contains("web-first-research")
}

///|
async fn provider_task_research_protocol_prompt(
  task : ProviderTaskSpec,
  context : ProviderTaskWorkerContext,
  slice_goal : String,
  requested_files : Array[String],
) -> String {
  let mounted_sources = provider_task_bootstrap_source_hints(
    context.workspace_root,
  )
  let requested_file_list = requested_files
    .map(fn(path) { "- \{path}" })
    .join("\n")
  [
    "Apply this bounded research dossier slice for provider task \{task.title}.",
    "",
    "Slice goal: \{slice_goal}",
    "",
    provider_task_contract_section(context),
    "Read first:",
    "- raw/bootstrap/RESEARCH_REQUEST.md",
    "- raw/bootstrap/SOURCE_HINTS.md",
    "- mounted-sources/MANIFEST.md if present",
    provider_task_mounted_source_section(mounted_sources),
    "Use web_search before local-only conclusions when the runtime exposes it.",
    "If web_search or web_fetch is unavailable or fails, still write the required files and record the exact limitation.",
    "Write or revise only these files for this slice:",
    requested_file_list,
    "The search log must include attempted web queries, selected or rejected URLs when available, and local path discovery state.",
    "The source screen must classify web and local candidates as included, excluded, verified, or blocked with reasons.",
    "The local sources file must map original hint paths to mounted aliases and summarize inspected local evidence.",
    "Use source IDs such as W1/W2 for web evidence, L1/L2 for local evidence, and B1/B2 for blockers.",
    "Every claim row in the evidence matrix must include source IDs, confidence, and a gap or contradiction note.",
    "The synthesis brief must separate verified findings, web verification status, contradictions, blockers, and next research.",
    "The marketing brief must be produced by the loaded marketing skill when available; do not fill it with deterministic fallback boilerplate.",
    "Use file_write or patch_edit to create the requested files before finishing. A prose-only answer is a failure.",
    "List which durable wiki/source/entity/concept/synthesis pages should be materialized next.",
    "Do not materialize wiki/source/entity/concept pages in this slice; it prepares the handoff.",
  ].join("\n")
}

///|
async fn provider_task_research_bootstrap_substeps(
  task : ProviderTaskSpec,
  context : ProviderTaskWorkerContext,
) -> Array[AdaptiveSubstepPayload] {
  if !provider_task_research_contract_requested(task, context) {
    return []
  }
  [
    {
      title: "Write research evidence packet",
      prompt: provider_task_research_protocol_prompt(
        task,
        context,
        "Gather and screen sources, inspect mounted local evidence, and write the claim-level research envelope.",
        [
          "raw/bootstrap/research-question.md", "raw/bootstrap/search-log.md", "raw/bootstrap/source-screen.md",
          "raw/bootstrap/local-sources.md", "raw/bootstrap/evidence-matrix.md", "raw/bootstrap/synthesis-brief.md",
        ],
      ),
      kind: Some("job.analysis"),
    },
    {
      title: "Write deep research report",
      prompt: provider_task_research_protocol_prompt(
        task,
        context,
        "Use the research-report skill to write the reader-facing deep research article from screened evidence and mounted sources.",
        ["raw/bootstrap/deep-report.md"],
      ),
      kind: Some("job.analysis"),
    },
    {
      title: "Write marketing brief",
      prompt: provider_task_research_protocol_prompt(
        task,
        context,
        "Use the wiki-marketing skill to write seller-facing product positioning from supported evidence, not backend status copy.",
        ["raw/bootstrap/marketing-brief.md"],
      ),
      kind: Some("job.analysis"),
    },
  ]
}

///|
fn provider_task_bootstrap_packet_slug(
  first_path : String,
  index : Int,
) -> String {
  let stem = @pathx.basename(first_path)
    .to_owned()
    .replace_all(old=".md", new="")
  let normalized = safe_step_file_segment(stem)
  if normalized.is_blank() {
    "bootstrap-lane-\{index}"
  } else {
    "\{normalized}-lane-\{index}"
  }
}

///|
async fn provider_task_bootstrap_gather_prompt(
  task : ProviderTaskSpec,
  context : ProviderTaskWorkerContext,
  lane_paths : Array[String],
  packet_path : String,
) -> String {
  let path_list = lane_paths.map(fn(path) { "- \{path}" }).join("\n")
  let mounted_sources = provider_task_bootstrap_source_hints(
    context.workspace_root,
  )
  [
    "Apply one bounded gather slice of the provider task \{task.title}.",
    provider_task_contract_section(context),
    "Read `mounted-sources/MANIFEST.md` if present, then inspect the listed mounted aliases.",
    provider_task_mounted_source_section(mounted_sources),
    "Inspect only these high-signal local files first:",
    path_list,
    "Write exactly one bootstrap packet at:",
    "- \{packet_path}",
    "The packet must be durable markdown under `raw/bootstrap/` and include:",
    "- a short summary",
    "- evidence bullets with concrete source paths",
    "- at least one candidate durable source page under `wiki/sources/*.md`",
    "- any additional candidate durable pages such as `wiki/entities/*.md`, `wiki/concepts/*.md`, or `wiki/synthesis/*.md`",
    "- explicit blockers or open gaps if the slice is weak",
    "Do not claim wiki coverage. This step only gathers evidence and writes the packet.",
  ].join("\n")
}

///|
fn provider_task_default_source_page_from_packet(
  packet_path : String,
  content : String,
) -> String {
  let mut title : String? = None
  for raw_line in content.split("\n") {
    let line = raw_line.trim().to_owned()
    if line.has_prefix("# Bootstrap Packet:") {
      title = Some(line["# Bootstrap Packet:".length():].trim().to_owned())
      break
    }
  }
  let base = match title {
    Some(name) if !name.is_blank() => name
    _ => @pathx.basename(packet_path).to_owned().replace_all(old=".md", new="")
  }
  let slug = safe_step_file_segment(base)
  let file_name = if slug.is_blank() {
    "bootstrap-source-\{packet_path.hash()}.md"
  } else {
    "\{slug}.md"
  }
  "wiki/sources/\{file_name}"
}

///|
fn provider_task_materialize_substep_title(page : String) -> String {
  let name = @pathx.basename(page).replace_all(old=".md", new="")
  "Materialize \{name}"
}

///|
async fn provider_task_materialize_substep_prompt(
  task : ProviderTaskSpec,
  context : ProviderTaskWorkerContext,
  packets : Array[String],
  target_page : String,
) -> String {
  let packet_list = if packets.is_empty() {
    "- none"
  } else {
    packets.map(fn(path) { "- \{path}" }).join("\n")
  }
  [
    "Apply one bounded slice of the provider task \{task.title}.",
    provider_task_contract_section(context),
    "Read the gathered bootstrap packet(s):",
    packet_list,
    "Materialize or revise only this durable page:",
    "- \{target_page}",
    "Use only evidence that is already present in the bootstrap packets or mounted workspace files.",
    "Update `wiki/index.md` and `wiki/log.md` if this page lands.",
    "Do not claim success unless the target page was actually written or revised.",
  ].join("\n")
}

///|
async fn provider_task_revision_substep_prompt(
  task : ProviderTaskSpec,
  context : ProviderTaskWorkerContext,
  packets : Array[String],
  target_page : String,
) -> String {
  let packet_list = if packets.is_empty() {
    "- none"
  } else {
    packets.map(fn(path) { "- \{path}" }).join("\n")
  }
  [
    "Apply one bounded revision slice of the provider task \{task.title}.",
    provider_task_contract_section(context),
    "Read the gathered bootstrap packet(s):",
    packet_list,
    "Revise only this durable page:",
    "- \{target_page}",
    "Cross-link to the strongest related source pages already present in the workspace.",
    "Keep claims bounded to cited packet evidence and mounted workspace files.",
    "If the page lands, update `wiki/index.md` and `wiki/log.md` so entity, concept, source, and synthesis sections reflect the actual durable files.",
  ].join("\n")
}

///|
async fn provider_task_catalog_refresh_substep_prompt(
  task : ProviderTaskSpec,
  context : ProviderTaskWorkerContext,
  source_pages : Array[String],
  revision_pages : Array[String],
) -> String {
  let source_list = if source_pages.is_empty() {
    "- none"
  } else {
    source_pages.map(fn(path) { "- \{path}" }).join("\n")
  }
  let revision_list = if revision_pages.is_empty() {
    "- none"
  } else {
    revision_pages.map(fn(path) { "- \{path}" }).join("\n")
  }
  [
    "Apply the catalog closeout slice of provider task \{task.title}.",
    provider_task_contract_section(context),
    "Durable source pages present:",
    source_list,
    "Durable knowledge pages expected from this revision:",
    revision_list,
    "Refresh only catalog and status surfaces:",
    "- wiki/index.md",
    "- wiki/log.md",
    "- wiki/synthesis/map.md",
    "Use actual files under `wiki/sources/`, `wiki/entities/`, `wiki/concepts/`, `wiki/queries/`, and `wiki/synthesis/`.",
    "Do not leave Entities or Concepts as `_None yet._` when corresponding durable pages exist.",
    "Do not invent prompt-derived titles. Use compact page titles derived from filenames and page headings.",
    "Return a concise completion result after the catalog reflects the durable workspace state.",
  ].join("\n")
}

///|
async fn provider_task_source_materialize_substeps(
  task : ProviderTaskSpec,
  context : ProviderTaskWorkerContext,
) -> Array[AdaptiveSubstepPayload] {
  let (packets, pages) = provider_task_packet_candidate_pages(
    context.workspace_root,
    ["wiki/sources/"],
  )
  let materialize_pages = if pages.is_empty() {
    let synthesized : Array[String] = []
    for packet in packets {
      let absolute = @pathx.join(context.workspace_root, packet)
      let content = @fsx.read_file(absolute) catch { _ => continue }
      let page = provider_task_default_source_page_from_packet(packet, content)
      if !synthesized.contains(page) {
        synthesized.push(page)
      }
    }
    synthesized
  } else {
    pages
  }
  let bounded_pages : Array[String] = []
  let mut i = 0
  while i < materialize_pages.length() && i < 2 {
    bounded_pages.push(materialize_pages[i])
    i += 1
  }
  let substeps : Array[AdaptiveSubstepPayload] = []
  for page in bounded_pages {
    substeps.push({
      title: provider_task_materialize_substep_title(page),
      prompt: provider_task_materialize_substep_prompt(
        task, context, packets, page,
      ),
      kind: Some("job.analysis"),
    })
  }
  substeps
}

///|
async fn provider_task_existing_source_pages(
  workspace_root : String,
) -> Array[String] {
  let source_dir = @pathx.join(workspace_root, "wiki") |> @pathx.join("sources")
  let entries = @fsx.list_directory(source_dir) catch { _ => return [] }
  let pages : Array[String] = []
  for entry in entries {
    guard entry.kind is Regular else { continue }
    guard entry.name.has_suffix(".md") else { continue }
    pages.push(@pathx.join("wiki/sources", entry.name))
  }
  pages.sort()
  pages
}

///|
fn provider_task_can_complete_from_research_artifacts(
  task : ProviderTaskSpec,
) -> Bool {
  let normalized_kind = task.kind.trim().to_lower()
  normalized_kind == "bootstrap_gather" ||
  normalized_kind == "source_materialize" ||
  normalized_kind == "knowledge_revise" ||
  normalized_kind == "review" ||
  normalized_kind == "review_finalize"
}

///|
fn provider_task_research_artifact_result(
  task : ProviderTaskSpec,
  artifacts : Array[String],
) -> ProviderTaskResult {
  {
    task_id: provider_task_result_task_id(task),
    summary: "Completed \{task.title} from research bootstrap dossier: \{artifacts.length()} required raw artifact(s) present. MoonBook owns durable wiki materialization from this envelope.",
    artifacts,
    memory_candidates: [],
    requires_review: false,
    notify_town: false,
  }
}

///|
fn provider_task_missing_research_artifacts(
  present : Array[String],
) -> Array[String] {
  let missing : Array[String] = []
  for path in provider_task_required_research_artifacts() {
    if !present.contains(path) {
      missing.push(path)
    }
  }
  missing
}

///|
fn provider_task_missing_research_artifact_result(
  task : ProviderTaskSpec,
  artifacts : Array[String],
  missing : Array[String],
) -> ProviderTaskResult {
  let missing_text = if missing.is_empty() {
    "none"
  } else {
    missing.join(", ")
  }
  {
    task_id: provider_task_result_task_id(task),
    summary: "Blocked \{task.title}: model-authored research dossier is incomplete. Missing required raw artifact(s): \{missing_text}.",
    artifacts,
    memory_candidates: [
      {
        kind: "blocker",
        title: "Incomplete model-authored research dossier",
        detail: "The provider/model did not produce all required raw/bootstrap research artifacts. Missing: \{missing_text}. Re-run the bounded research-report skill path instead of accepting deterministic fallback content.",
        durable: false,
        target_page: None,
      },
    ],
    requires_review: true,
    notify_town: false,
  }
}

///|
fn provider_task_can_complete_from_source_inventory(
  task : ProviderTaskSpec,
) -> Bool {
  let normalized_kind = task.kind.trim().to_lower()
  normalized_kind == "review" || normalized_kind == "review_finalize"
}

///|
fn provider_task_source_inventory_result(
  task : ProviderTaskSpec,
  source_pages : Array[String],
) -> ProviderTaskResult {
  {
    task_id: provider_task_result_task_id(task),
    summary: "Completed \{task.title} from durable source inventory: \{source_pages.length()} source page(s) present.",
    artifacts: source_pages,
    memory_candidates: [],
    requires_review: false,
    notify_town: false,
  }
}

///|
fn provider_task_synthesis_page_from_source(source_page : String) -> String {
  let name = @pathx.basename(source_page).replace_all(old=".md", new="")
  "wiki/synthesis/\{name}-notes.md"
}

///|
fn provider_task_wiki_page_slug(text : String) -> String {
  let buf = StringBuilder::new()
  let mut chars_written = 0
  let mut last_dash = true
  for c in text.to_lower().to_array() {
    let normalized = match c {
      'a'..='z' => Some(c)
      '0'..='9' => Some(c)
      _ => None
    }
    match normalized {
      Some(c) => {
        if chars_written >= 64 {
          break
        }
        buf.write_char(c)
        chars_written += 1
        last_dash = false
      }
      None =>
        if !last_dash && chars_written < 64 {
          buf.write_char('-')
          chars_written += 1
          last_dash = true
        }
    }
  }
  let slug = buf.to_string().trim(chars="-").to_owned()
  if slug.is_blank() {
    "topic"
  } else {
    slug
  }
}

///|
fn provider_task_concept_page_from_source(source_page : String) -> String {
  let name = @pathx.basename(source_page)
    .replace_all(old=".md", new="")
    .to_owned()
  "wiki/concepts/\{provider_task_wiki_page_slug(name)}.md"
}

///|
fn provider_task_entity_page_from_context(
  context : ProviderTaskWorkerContext,
) -> String? {
  let raw = context.book_id
    .trim()
    .to_owned()
    .to_lower()
    .replace_all(old="research-", new="")
  let slug = provider_task_wiki_page_slug(raw)
  if slug.is_blank() {
    None
  } else {
    Some("wiki/entities/\{slug}.md")
  }
}

///|
fn provider_task_bounded_pages(
  pages : Array[String],
  limit : Int,
) -> Array[String] {
  let bounded : Array[String] = []
  let mut i = 0
  while i < pages.length() && i < limit {
    bounded.push(pages[i])
    i += 1
  }
  bounded
}

///|
fn provider_task_revision_pages_from_sources(
  context : ProviderTaskWorkerContext,
  source_pages : Array[String],
) -> Array[String] {
  let pages : Array[String] = []
  match provider_task_entity_page_from_context(context) {
    Some(page) => pages.push(page)
    None => ()
  }
  for source_page in source_pages {
    let concept_page = provider_task_concept_page_from_source(source_page)
    if !pages.contains(concept_page) {
      pages.push(concept_page)
    }
  }
  for source_page in source_pages {
    let page = provider_task_synthesis_page_from_source(source_page)
    if !pages.contains(page) {
      pages.push(page)
    }
  }
  provider_task_bounded_pages(pages, 4)
}

///|
fn provider_task_review_substep_prompt(
  task : ProviderTaskSpec,
  source_pages : Array[String],
) -> String {
  let source_list = if source_pages.is_empty() {
    "- none"
  } else {
    source_pages.map(fn(path) { "- \{path}" }).join("\n")
  }
  [
    "Apply the bounded closeout slice of provider task \{task.title}.",
    "Durable source pages already present:",
    source_list,
    "Reconcile only the book status and review surfaces:",
    "- wiki/index.md",
    "- wiki/log.md",
    "- wiki/synthesis/map.md",
    "- wiki/history/journey.md",
    "- wiki/history/debug-journal.md",
    "- wiki/reviews/pending.md",
    "If durable source pages exist, do not report that no substantive pages were updated.",
    "Do not create new prompt-derived review titles. Use compact labels from existing page names.",
    "Return a concise completion result after those files are consistent.",
  ].join("\n")
}

///|
async fn provider_task_precompiled_substeps(
  task : ProviderTaskSpec,
  context : ProviderTaskWorkerContext,
) -> Array[AdaptiveSubstepPayload] {
  let normalized_kind = task.kind.trim().to_lower()
  if normalized_kind == "bootstrap_gather" {
    let substeps = provider_task_research_bootstrap_substeps(task, context)
    if !substeps.is_empty() {
      return substeps
    }
    let hint_paths = provider_task_bootstrap_source_hints(
      context.workspace_root,
    )
    let lanes = provider_task_chunk_strings(hint_paths, 2)
    let mut i = 0
    while i < lanes.length() && i < 2 {
      let lane_paths = lanes[i]
      guard !lane_paths.is_empty() else {
        i += 1
        continue
      }
      let packet_slug = provider_task_bootstrap_packet_slug(
        lane_paths[0],
        i + 1,
      )
      let packet_path = "raw/bootstrap/\{packet_slug}.md"
      substeps.push({
        title: "Gather bootstrap lane \{i + 1}",
        prompt: provider_task_bootstrap_gather_prompt(
          task, context, lane_paths, packet_path,
        ),
        kind: Some("job.analysis"),
      })
      i += 1
    }
    return substeps
  }
  if normalized_kind == "source_materialize" {
    return provider_task_source_materialize_substeps(task, context)
  }
  if normalized_kind == "knowledge_revise" {
    let existing_sources = provider_task_existing_source_pages(
      context.workspace_root,
    )
    if existing_sources.is_empty() {
      let materialize_substeps = provider_task_source_materialize_substeps(
        task, context,
      )
      if !materialize_substeps.is_empty() {
        return materialize_substeps
      }
    }
    let (packets, pages) = provider_task_packet_candidate_pages(
      context.workspace_root,
      ["wiki/entities/", "wiki/concepts/", "wiki/queries/", "wiki/synthesis/"],
    )
    let revision_pages = if pages.is_empty() {
      provider_task_bounded_pages(
        provider_task_revision_pages_from_sources(context, existing_sources),
        3,
      )
    } else {
      provider_task_bounded_pages(pages, 3)
    }
    let substeps : Array[AdaptiveSubstepPayload] = []
    for page in revision_pages {
      let name = @pathx.basename(page).replace_all(old=".md", new="")
      substeps.push({
        title: "Revise \{name}",
        prompt: provider_task_revision_substep_prompt(
          task, context, packets, page,
        ),
        kind: Some("job.analysis"),
      })
    }
    if !revision_pages.is_empty() {
      substeps.push({
        title: "Refresh wiki catalog",
        prompt: provider_task_catalog_refresh_substep_prompt(
          task, context, existing_sources, revision_pages,
        ),
        kind: Some("job.analysis"),
      })
    }
    return substeps
  }
  if normalized_kind == "review" || normalized_kind == "review_finalize" {
    let existing_sources = provider_task_existing_source_pages(
      context.workspace_root,
    )
    if existing_sources.is_empty() {
      return provider_task_source_materialize_substeps(task, context)
    }
    return [
      {
        title: "Finalize provider review",
        prompt: provider_task_review_substep_prompt(task, existing_sources),
        kind: Some("job.analysis"),
      },
    ]
  }
  []
}

///|
async fn provider_task_precompiled_envelope(
  task : ProviderTaskSpec,
  context : ProviderTaskWorkerContext,
) -> AdaptiveAnalysisEnvelope? {
  let substeps = provider_task_precompiled_substeps(task, context)
  if substeps.is_empty() {
    None
  } else {
    Some({
      verdict: "needs_subplan",
      summary: Some(
        "Split provider task \{task.title} into bounded workspace edits derived from gathered bootstrap material.",
      ),
      missing_inputs: None,
      suggested_substeps: Some(substeps),
      substeps: None,
    })
  }
}

///|
fn provider_task_requires_local_tool_loop(task : ProviderTaskSpec) -> Bool {
  // Provider-backed extension tasks are expected to read mounted workspace
  // files and materialize durable outputs. Forcing single-response mode here
  // blocks the very filesystem/tool work that imported bootstrap runs depend
  // on. Keep the loop bounded with the existing timeout/guardrail path rather
  // than disabling tools entirely.
  ignore(task)
  true
}

///|
fn provider_task_execution_step_metadata(
  metadata : Json,
  force_single_response : Bool,
) -> Json {
  let merged : Map[String, Json] = {}
  match metadata {
    Object(obj) =>
      for key, value in obj {
        merged.set(key, value)
      }
    _ => ()
  }
  merged.set("provider_force_single_response", force_single_response.to_json())
  Json::object(merged)
}

///|
fn provider_task_breadth_envelope_from_content(
  batch : ProviderTaskBatch,
  task : ProviderTaskSpec,
  content : String,
) -> AdaptiveAnalysisEnvelope? {
  let trimmed = match extract_first_json_object(content) {
    Some(payload) => payload.trim().to_owned()
    None => return None
  }
  let json = @json.parse(trimmed) catch { _ => return None }
  match parse_adaptive_analysis_envelope(trimmed) {
    Some(envelope) if envelope.verdict.trim().to_lower() == "needs_subplan" =>
      if adaptive_substeps(envelope).is_empty() {
        let followup_substeps = provider_task_followup_substeps(batch, task)
        if followup_substeps.is_empty() {
          Some(envelope)
        } else {
          Some({
            verdict: "needs_subplan",
            summary: envelope.summary,
            missing_inputs: envelope.missing_inputs,
            suggested_substeps: Some(followup_substeps),
            substeps: None,
          })
        }
      } else {
        Some(envelope)
      }
    _ => {
      let substeps = provider_task_plan_substeps_from_json(json)
      let summary = provider_task_breadth_summary(task, json)
      let lower = trimmed.to_lower()
      let substeps = if substeps.is_empty() &&
        (
          lower.contains("too broad") ||
          lower.contains("decompos") ||
          lower.contains("split") ||
          lower.contains("\"plan\"") ||
          lower.contains("\"steps\"")
        ) {
        provider_task_followup_substeps(batch, task)
      } else {
        substeps
      }
      if substeps.is_empty() {
        if lower.contains("too broad") ||
          lower.contains("decompos") ||
          lower.contains("split") ||
          lower.contains("\"plan\"") ||
          lower.contains("\"steps\"") {
          Some({
            verdict: "needs_subplan",
            summary: Some(summary),
            missing_inputs: None,
            suggested_substeps: None,
            substeps: None,
          })
        } else {
          None
        }
      } else {
        Some({
          verdict: "needs_subplan",
          summary: Some(summary),
          missing_inputs: None,
          suggested_substeps: Some(substeps),
          substeps: None,
        })
      }
    }
  }
}

///|
fn provider_task_guardrail_split_execution(
  execution : AnalysisExecution,
  request : AnalysisRequest,
  task : ProviderTaskSpec,
  envelope : AdaptiveAnalysisEnvelope,
  target_id : String,
) -> AnalysisExecution {
  let envelope_json : Map[String, Json] = {
    "verdict": "needs_subplan".to_json(),
    "summary": envelope.summary
    .unwrap_or("Provider task requires splitting before execution.")
    .to_json(),
  }
  match adaptive_substeps(envelope) {
    [] => ()
    substeps =>
      envelope_json["suggested_substeps"] = Json::array(
        substeps.map(fn(step) {
          { "title": step.title, "prompt": step.prompt, "kind": step.kind }
        }),
      )
  }
  {
    ..execution,
    content: Json::object(envelope_json).stringify(),
    metadata: {
      "job_id": execution_metadata_value(execution.metadata, "job_id"),
      "run_id": execution_metadata_value(execution.metadata, "run_id"),
      "step_id": execution_metadata_value(execution.metadata, "step_id"),
      "execution_mode": "provider",
      "execution_target": target_id,
      "extension_task_id": task.id,
      "extension_task_kind": task.kind,
      "extension_guardrail_verdict": "needs_subplan",
      "extension_guardrail_summary": envelope.summary.unwrap_or(
        "Provider task requires splitting before execution.",
      ),
      "execution_isolation": execution_metadata_value(
        execution.metadata,
        "execution_isolation",
      ),
      "role_runtime_contract": execution_metadata_value(
        execution.metadata,
        "role_runtime_contract",
      ),
      "disable_waiting_for_input": waiting_for_input_disabled_from_metadata(
        request.step_metadata,
      ),
      "best_effort_on_missing_input": best_effort_on_missing_input_from_metadata(
        request.step_metadata,
      ),
    },
  }
}

///|
fn provider_task_guardrail_reject_error(
  task : ProviderTaskSpec,
  envelope : AdaptiveAnalysisEnvelope,
) -> String {
  let detail = envelope.summary.unwrap_or(
    "Provider task requires splitting before execution.",
  )
  "Provider task \{task.id} is too broad to execute directly and no executable substeps were provided: \{detail}"
}

///|
fn normalize_provider_task_result(
  task : ProviderTaskSpec,
  content : String,
) -> Result[ProviderTaskResult, String] {
  let trimmed = match extract_first_json_object(content) {
    Some(payload) => payload.trim().to_owned()
    None => return Err("Provider task analysis must return a JSON object")
  }
  let json = match parse_provider_task_payload(trimmed, "analysis") {
    Ok(json) => json
    Err(error) => return Err(error)
  }
  let summary = provider_task_json_string_field(json, "summary").unwrap_or(
    provider_task_json_string_field(json, "message").unwrap_or(
      plan_summary_from_json(json).unwrap_or(
        "Completed provider task \{task.title}.",
      ),
    ),
  )
  let artifacts = provider_task_json_string_array_field(json, "artifacts")
  let memory_candidates = match json {
    Object(obj) =>
      match obj.get("memory_candidates") {
        Some(Array(_)) =>
          @json.from_json(obj.get("memory_candidates").unwrap()) catch {
            _ => []
          }
        _ => []
      }
    _ => []
  }
  Ok({
    task_id: provider_task_result_task_id(task),
    summary,
    artifacts,
    memory_candidates,
    requires_review: provider_task_json_bool_field(json, "requires_review").unwrap_or(
      task.requires_review,
    ),
    notify_town: provider_task_json_bool_field(json, "notify_town").unwrap_or(
      false,
    ),
  })
}

///|
fn provider_task_result_is_empty_pseudo_success(
  result : ProviderTaskResult,
) -> Bool {
  result.artifacts.is_empty() &&
  result.memory_candidates.is_empty() &&
  result.summary.trim().to_lower().contains("completed provider task")
}

///|
fn provider_task_blocker_result(
  task : ProviderTaskSpec,
  context : ProviderTaskWorkerContext,
  result : ProviderTaskResult,
) -> ProviderTaskResult {
  let target_pages = if task.target_pages.is_empty() {
    "no target pages were declared"
  } else {
    task.target_pages.join(", ")
  }
  let context_pages = if context.context_pages.is_empty() {
    "no context pages were provided"
  } else {
    context.context_pages.join(", ")
  }
  {
    task_id: result.task_id,
    summary: "Blocked provider task \{task.title}: provider returned generic completion text without durable artifacts or memory candidates.",
    artifacts: [],
    memory_candidates: [
      {
        kind: "blocker",
        title: "No durable provider outputs",
        detail: "Provider returned a generic completion for \{task.title} but produced no durable artifacts or memory candidates. Expected target pages: \{target_pages}. Context pages: \{context_pages}.",
        durable: false,
        target_page: None,
      },
      {
        kind: "next_step",
        title: "Materialize durable outputs or return concrete blocker",
        detail: "Re-run provider execution so it creates durable source, entity, concept, query, or synthesis outputs, or return a structured blocker that names the missing source material.",
        durable: false,
        target_page: None,
      },
    ],
    requires_review: true,
    notify_town: result.notify_town,
  }
}

///|
fn enforce_provider_task_result_semantics(
  task : ProviderTaskSpec,
  context : ProviderTaskWorkerContext,
  result : ProviderTaskResult,
) -> ProviderTaskResult {
  if provider_task_result_is_empty_pseudo_success(result) {
    provider_task_blocker_result(task, context, result)
  } else {
    result
  }
}

///|
fn provider_task_repair_system_prompt(task : ProviderTaskSpec) -> String {
  [
    "You repair invalid provider task outputs into the required runtime contract.",
    "The loaded `provider-task-repair` skill defines the repair method.",
    "Return strict JSON only.",
    "The required shape is:",
    "{\"task_id\":string,\"summary\":string,\"artifacts\":string[],\"memory_candidates\":[{\"kind\":string,\"title\":string,\"detail\":string,\"durable\":bool,\"target_page\":string|null}],\"requires_review\":bool,\"notify_town\":bool}",
    "Use task_id = \{provider_task_result_task_id(task)}.",
  ].join("\n\n")
}

///|
fn provider_task_repair_prompt(
  task : ProviderTaskSpec,
  raw_content : String,
) -> String {
  [
    "The previous provider task analysis output did not match the required runtime contract.",
    "Convert it into the required JSON object without inventing unrelated fields.",
    "If the previous output is planner-shaped, collapse it into one completed task result for the current task.",
    "Task id: \{task.id}",
    "Task title: \{task.title}",
    "Task kind: \{task.kind}",
    "",
    "Previous invalid output:",
    raw_content,
  ].join("\n")
}

///|
async fn repair_provider_task_result(
  request : AnalysisRequest,
  task : ProviderTaskSpec,
  raw_execution : AnalysisExecution,
  inner_runner : async (AnalysisRequest) -> Result[AnalysisExecution, String],
) -> Result[ProviderTaskResult, String] {
  let preferred_skills = provider_task_preferred_skills(request, repair=true)
  let loaded_skills = loaded_skills_prompt(
    request.cwd,
    request.home,
    preferred_skills,
  )
  let repair_request = AnalysisRequest::{
    ..request,
    prompt: [
      provider_task_repair_prompt(task, raw_execution.content),
      loaded_skills,
    ]
    .filter(fn(section) { !section.is_blank() })
    .join("\n\n"),
    system_prompt: provider_task_repair_system_prompt(task),
    enable_tools: false,
    execution_mode: None,
    execution_target: None,
    web_search: false,
    preferred_skills,
  }
  let repaired_execution = match inner_runner(repair_request) {
    Ok(execution) => execution
    Err(error) => return Err(error)
  }
  match parse_provider_task_result(repaired_execution.content) {
    Ok(result) => Ok(result)
    Err(_) => normalize_provider_task_result(task, repaired_execution.content)
  }
}

///|
fn persisted_provider_task_report(
  task : ProviderTaskSpec,
  result : ProviderTaskResult,
  outcome : ProviderTaskPersistOutcome,
) -> String {
  let updated_pages = if outcome.updated_pages.is_empty() {
    "- none"
  } else {
    outcome.updated_pages.map(fn(page) { "- \{page}" }).join("\n")
  }
  [
    "# Extension Task Result",
    "",
    "## Task",
    "- id: \{task.id}",
    "- title: \{task.title}",
    "- kind: \{task.kind}",
    "",
    "## Summary",
    result.summary,
    "",
    "## Persisted Pages",
    updated_pages,
    "",
    "## Persist Outcome",
    "- evidence_id: \{outcome.evidence_id}",
    "- review_queued: \{outcome.review_queued}",
    "- notify_town: \{outcome.notify_town}",
    "- log_path: \{outcome.log_path}",
  ].join("\n")
}

///|
fn execution_metadata_value(metadata : Json, key : String) -> Json? {
  match metadata {
    Object(obj) => obj.get(key)
    _ => None
  }
}

///|
fn persisted_provider_task_execution(
  execution : AnalysisExecution,
  task : ProviderTaskSpec,
  result : ProviderTaskResult,
  outcome : ProviderTaskPersistOutcome,
  target_id : String,
) -> AnalysisExecution {
  {
    ..execution,
    content: persisted_provider_task_report(task, result, outcome),
    metadata: {
      "job_id": execution_metadata_value(execution.metadata, "job_id"),
      "run_id": execution_metadata_value(execution.metadata, "run_id"),
      "step_id": execution_metadata_value(execution.metadata, "step_id"),
      "execution_mode": "provider",
      "execution_target": target_id,
      "extension_task_id": task.id,
      "extension_result": result,
      "extension_persist_outcome": outcome,
      "execution_isolation": execution_metadata_value(
        execution.metadata,
        "execution_isolation",
      ),
      "role_runtime_contract": execution_metadata_value(
        execution.metadata,
        "role_runtime_contract",
      ),
    },
  }
}

///|
async fn persist_provider_task_result(
  command : ProviderTaskCommand,
  request : AnalysisRequest,
  _task : ProviderTaskSpec,
  result : ProviderTaskResult,
) -> Result[ProviderTaskPersistOutcome, String] {
  let result_path = match
    provider_task_runtime_artifact_path(
      request,
      command.workspace_root,
      "result",
    ) {
    Ok(path) => path
    Err(error) => return Err(error)
  }
  @fsx.write_to_file(
    result_path,
    result.to_json().stringify(indent=2),
    create=0o644,
  )
  let stdout = match
    run_provider_task_stdout(command, "persist", [result_path], "persist") {
    Ok(stdout) => stdout
    Err(error) => return Err(error)
  }
  let outcome : ProviderTaskPersistOutcome = match
    parse_provider_task_persist_outcome_json(stdout, "persist") {
    Ok(outcome) => outcome
    Err(error) => return Err(error)
  }
  Ok(outcome)
}

///|
async fn persist_provider_task_failure_debug(
  request : AnalysisRequest,
  workspace_root : String,
  task : ProviderTaskSpec,
  execution : AnalysisExecution,
  error : String,
) -> String {
  let path = match provider_task_failure_debug_path(request, workspace_root) {
    Ok(path) => path
    Err(path_error) =>
      return "provider-task-failure-debug-unavailable: \{path_error}; original error: \{error}"
  }
  let payload : Map[String, Json] = {
    "error": error.to_json(),
    "task_id": task.id.to_json(),
    "task_title": task.title.to_json(),
    "conversation_id": execution.conversation_id.to_json(),
    "model_name": execution.model_name.to_json(),
    "raw_content": execution.content.to_json(),
    "usage": usage_json(execution.usage),
    "metadata": execution.metadata,
  }
  @fsx.write_to_file(
    path,
    Json::object(payload).stringify(indent=2),
    create=0o644,
  )
  path
}

///|
fn provider_task_synthesized_subplan_result(
  task : ProviderTaskSpec,
  execution : AnalysisExecution,
  artifacts : Array[String],
) -> ProviderTaskResult {
  let summary = metadata_string_value(
    execution.metadata,
    "extension_guardrail_summary",
  ).unwrap_or(
    "Adaptive subplan for \{task.title} completed and produced durable workspace outputs.",
  )
  {
    task_id: provider_task_result_task_id(task),
    summary,
    artifacts,
    memory_candidates: [],
    requires_review: false,
    notify_town: false,
  }
}

///|
async fn finalize_provider_task_subplan_execution(
  request : AnalysisRequest,
  execution : AnalysisExecution,
  child_outputs : Json,
) -> Result[AnalysisExecution, String]? {
  guard provider_execution_requested(request.execution_mode) else {
    return None
  }
  let goal = metadata_string_value(request.step_metadata, "extension_goal").unwrap_or(
    request.source_prompt,
  )
  let selected_task_id = metadata_string_value(
    request.step_metadata,
    "extension_task_id",
  )
  let (command, batch) = match
    load_provider_task_task_batch(
      request.cwd,
      request.home,
      request.execution_target,
      goal,
      metadata=request.step_metadata,
    ) {
    Ok(value) => value
    Err(error) => return Some(Err(error))
  }
  let resolved_target_id = command.provider.name
  let task = match provider_task_spec_from_metadata(request.step_metadata) {
    Some(task) => task
    None =>
      match select_provider_task_task(batch, selected_task_id) {
        Ok(task) => task
        Err(error) => return Some(Err(error))
      }
  }
  let task = normalize_provider_task_spec_from_metadata(
    request.step_metadata,
    task,
  )
  let context = match load_provider_task_context(command, goal, task.id) {
    Ok(context) => context
    Err(error) => return Some(Err(error))
  }
  let artifact_root = provider_task_effective_workspace_root(
    command.workspace_root,
    context.workspace_root,
    request.cwd,
  )
  let context = ProviderTaskWorkerContext::{
    ..context,
    workspace_root: artifact_root,
  }
  if provider_task_cancellation_requested() {
    return Some(Err(provider_task_cancelled_error()))
  }
  let artifacts : Array[String] = []
  provider_task_collect_artifacts_from_json(child_outputs, artifacts)
  for path in provider_task_target_artifacts(artifact_root, task) {
    if !artifacts.contains(path) {
      artifacts.push(path)
    }
  }
  let result = if provider_task_can_complete_from_research_artifacts(task) {
    let research_artifacts = provider_task_existing_research_artifacts(
      artifact_root,
    )
    let missing = provider_task_missing_research_artifacts(research_artifacts)
    if missing.is_empty() {
      provider_task_research_artifact_result(task, research_artifacts)
    } else {
      provider_task_missing_research_artifact_result(
        task, research_artifacts, missing,
      )
    }
  } else {
    provider_task_synthesized_subplan_result(task, execution, artifacts)
  }
  let result = align_provider_task_result(artifact_root, task, result)
  let result = enforce_provider_task_result_semantics(task, context, result)
  if provider_task_cancellation_requested() {
    return Some(Err(provider_task_cancelled_error()))
  }
  let outcome = match
    persist_provider_task_result(command, request, task, result) {
    Ok(outcome) => outcome
    Err(error) => return Some(Err(error))
  }
  Some(
    Ok(
      persisted_provider_task_execution(
        execution, task, result, outcome, resolved_target_id,
      ),
    ),
  )
}

///|
async fn run_provider_task_analysis_runner(
  request : AnalysisRequest,
  inner_runner : async (AnalysisRequest) -> Result[AnalysisExecution, String],
) -> Result[AnalysisExecution, String] {
  let goal = metadata_string_value(request.step_metadata, "extension_goal").unwrap_or(
    request.source_prompt,
  )
  let selected_task_id = metadata_string_value(
    request.step_metadata,
    "extension_task_id",
  )
  let (command, batch) = match
    load_provider_task_task_batch(
      request.cwd,
      request.home,
      request.execution_target,
      goal,
      metadata=request.step_metadata,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let resolved_target_id = command.provider.name
  let task = match provider_task_spec_from_metadata(request.step_metadata) {
    Some(task) => task
    None =>
      match select_provider_task_task(batch, selected_task_id) {
        Ok(task) => task
        Err(error) => return Err(error)
      }
  }
  let task = normalize_provider_task_spec_from_metadata(
    request.step_metadata,
    task,
  )
  let context = match load_provider_task_context(command, goal, task.id) {
    Ok(context) => context
    Err(error) => return Err(error)
  }
  let artifact_root = provider_task_effective_workspace_root(
    command.workspace_root,
    context.workspace_root,
    request.cwd,
  )
  let context = ProviderTaskWorkerContext::{
    ..context,
    workspace_root: artifact_root,
  }
  if provider_task_cancellation_requested() {
    return Err(provider_task_cancelled_error())
  }
  let contract = provider_task_tool_contract(request)
  if provider_task_can_complete_from_research_artifacts(task) {
    let research_artifacts = provider_task_existing_research_artifacts(
      artifact_root,
    )
    if research_artifacts.length() ==
      provider_task_required_research_artifacts().length() {
      let result = provider_task_research_artifact_result(
        task, research_artifacts,
      )
      let result = align_provider_task_result(artifact_root, task, result)
      let result = enforce_provider_task_result_semantics(task, context, result)
      let outcome = match
        persist_provider_task_result(command, request, task, result) {
        Ok(outcome) => outcome
        Err(error) => return Err(error)
      }
      return Ok(
        persisted_provider_task_execution(
          {
            model_name: request.model_name,
            content: "{}",
            conversation_id: None,
            usage: None,
            metadata: {
              "job_id": request.job_id,
              "run_id": request.run_id,
              "step_id": request.step_id,
              "execution_isolation": request.execution_isolation,
              "role_runtime_contract": request.role_runtime_contract,
            },
          },
          task,
          result,
          outcome,
          resolved_target_id,
        ),
      )
    }
  }
  let web_tools_enabled = request.enable_tools && request.web_search
  if provider_task_cancellation_requested() {
    return Err(provider_task_cancelled_error())
  }
  if provider_task_can_complete_from_source_inventory(task) {
    let source_pages = provider_task_existing_source_pages(artifact_root)
    if !source_pages.is_empty() {
      let result = provider_task_source_inventory_result(task, source_pages)
      let result = align_provider_task_result(artifact_root, task, result)
      let result = enforce_provider_task_result_semantics(task, context, result)
      let outcome = match
        persist_provider_task_result(command, request, task, result) {
        Ok(outcome) => outcome
        Err(error) => return Err(error)
      }
      return Ok(
        persisted_provider_task_execution(
          {
            model_name: request.model_name,
            content: "{}",
            conversation_id: None,
            usage: None,
            metadata: {
              "job_id": request.job_id,
              "run_id": request.run_id,
              "step_id": request.step_id,
              "execution_isolation": request.execution_isolation,
              "role_runtime_contract": request.role_runtime_contract,
            },
          },
          task,
          result,
          outcome,
          resolved_target_id,
        ),
      )
    }
  }
  match provider_task_precompiled_envelope(task, context) {
    Some(envelope) =>
      return Ok(
        provider_task_guardrail_split_execution(
          {
            model_name: request.model_name,
            content: "{}",
            conversation_id: None,
            usage: None,
            metadata: {
              "job_id": request.job_id,
              "run_id": request.run_id,
              "step_id": request.step_id,
              "execution_isolation": request.execution_isolation,
              "role_runtime_contract": request.role_runtime_contract,
            },
          },
          request,
          task,
          envelope,
          resolved_target_id,
        ),
      )
    None => ()
  }
  if provider_task_cancellation_requested() {
    return Err(provider_task_cancelled_error())
  }
  let use_local_tool_loop = provider_task_requires_local_tool_loop(task)
  let preferred_skills = provider_task_preferred_skills(request)
  let loaded_skills = loaded_skills_prompt(
    request.cwd,
    request.home,
    preferred_skills,
  )
  let delegated_request = AnalysisRequest::{
    ..request,
    prompt: [provider_task_prompt(request, task, context), loaded_skills]
    .filter(fn(section) { !section.is_blank() })
    .join("\n\n"),
    system_prompt: provider_task_system_prompt(request, task, context),
    source_prompt: goal,
    enable_tools: request.enable_tools && use_local_tool_loop,
    tool_contract: provider_task_tool_contract(request),
    execution_mode: None,
    execution_target: None,
    web_search: request.web_search && use_local_tool_loop,
    preferred_skills,
    step_metadata: provider_task_execution_step_metadata(
      request.step_metadata,
      !use_local_tool_loop,
    ),
  }
  if provider_task_cancellation_requested() {
    return Err(provider_task_cancelled_error())
  }
  let raw_execution = inner_runner(delegated_request)
  let raw_execution = match raw_execution {
    Ok(execution) => execution
    Err(error) => {
      let _ = provider_task_write_research_dossier_if_needed(
        task,
        context,
        web_search_enabled=web_tools_enabled && contract.web_search,
        web_fetch_enabled=web_tools_enabled && contract.web_fetch,
      )
      let research_artifacts = provider_task_existing_research_artifacts(
        artifact_root,
      )
      if provider_task_can_complete_from_research_artifacts(task) &&
        research_artifacts.length() ==
        provider_task_required_research_artifacts().length() {
        let result = provider_task_research_artifact_result(
          task, research_artifacts,
        )
        let result = align_provider_task_result(artifact_root, task, result)
        let result = enforce_provider_task_result_semantics(
          task, context, result,
        )
        let outcome = match
          persist_provider_task_result(command, request, task, result) {
          Ok(outcome) => outcome
          Err(persist_error) => return Err(persist_error)
        }
        return Ok(
          persisted_provider_task_execution(
            {
              model_name: request.model_name,
              content: "{}",
              conversation_id: None,
              usage: None,
              metadata: {
                "job_id": request.job_id,
                "run_id": request.run_id,
                "step_id": request.step_id,
                "execution_isolation": request.execution_isolation,
                "role_runtime_contract": request.role_runtime_contract,
                "provider_fallback": "deterministic_research_dossier_after_model_error",
              },
            },
            task,
            result,
            outcome,
            resolved_target_id,
          ),
        )
      }
      return Err(error)
    }
  }
  if provider_task_cancellation_requested() {
    return Err(provider_task_cancelled_error())
  }
  match
    provider_task_breadth_envelope_from_content(
      batch,
      task,
      raw_execution.content,
    ) {
    Some(envelope) =>
      if adaptive_substeps(envelope).is_empty() {
        return Err(provider_task_guardrail_reject_error(task, envelope))
      } else {
        return Ok(
          provider_task_guardrail_split_execution(
            raw_execution, request, task, envelope, resolved_target_id,
          ),
        )
      }
    None => ()
  }
  let result = match parse_provider_task_result(raw_execution.content) {
    Ok(result) => result
    Err(error) =>
      match
        repair_provider_task_result(request, task, raw_execution, inner_runner) {
        Ok(result) => result
        Err(repair_error) => {
          let debug_path = persist_provider_task_failure_debug(
            request,
            command.workspace_root,
            task,
            raw_execution,
            "\{error}; repair failed: \{repair_error}",
          )
          return Err("\{error} (raw response: \{debug_path})")
        }
      }
  }
  let result = align_provider_task_result(artifact_root, task, result)
  let result = enforce_provider_task_result_semantics(task, context, result)
  if provider_task_cancellation_requested() {
    return Err(provider_task_cancelled_error())
  }
  let outcome = match
    persist_provider_task_result(command, request, task, result) {
    Ok(outcome) => outcome
    Err(error) => return Err(error)
  }
  Ok(
    persisted_provider_task_execution(
      raw_execution, task, result, outcome, resolved_target_id,
    ),
  )
}
