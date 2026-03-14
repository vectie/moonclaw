///|
pub(all) struct ResearchPaper {
  id : String
  base_id : String
  version : Int
  title : String
  abstract_text : String
  authors : Array[String]
  categories : Array[String]
  primary_category : String?
  published_at : String?
  updated_at : String?
  abs_url : String?
  pdf_url : String?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct ResearchChunk {
  id : String
  paper_id : String
  index : Int
  text : String
  heading : String?
  token_estimate : Int
} derive(ToJson, FromJson, Show)

///|
pub(all) struct ResearchTopicSyncConfig {
  topic_id : String
  title : String?
  query : String
  max_results : Int
  download_pdf : Bool
  scope : Array[String]
} derive(ToJson, FromJson, Show)

///|
pub fn ResearchTopicSyncConfig::new(
  topic_id~ : String,
  query~ : String,
  title? : String? = None,
  max_results? : Int = 10,
  download_pdf? : Bool = true,
  scope? : Array[String] = [],
) -> ResearchTopicSyncConfig {
  ResearchTopicSyncConfig::{
    topic_id,
    title,
    query,
    max_results,
    download_pdf,
    scope,
  }
}

///|
pub(all) struct ResearchPaperFetchConfig {
  paper_id : String?
  query : String?
  topic_id : String?
  max_results : Int
  download_pdf : Bool
  scope : Array[String]
} derive(ToJson, FromJson, Show)

///|
pub fn ResearchPaperFetchConfig::new(
  paper_id? : String? = None,
  query? : String? = None,
  topic_id? : String? = None,
  max_results? : Int = 1,
  download_pdf? : Bool = true,
  scope? : Array[String] = [],
) -> ResearchPaperFetchConfig {
  ResearchPaperFetchConfig::{
    paper_id,
    query,
    topic_id,
    max_results,
    download_pdf,
    scope,
  }
}

///|
pub(all) struct ResearchPaperParseConfig {
  paper_id : String?
  chunk_chars : Int
  scope : Array[String]
} derive(ToJson, FromJson, Show)

///|
pub fn ResearchPaperParseConfig::new(
  paper_id? : String? = None,
  chunk_chars? : Int = 2400,
  scope? : Array[String] = [],
) -> ResearchPaperParseConfig {
  ResearchPaperParseConfig::{ paper_id, chunk_chars, scope }
}

///|
pub(all) struct ResearchPaperAnalyzeConfig {
  paper_id : String
  analysis_kind : String
  model : String?
  cwd : String?
  home : String?
  system_prompt : String?
  preferred_skills : Array[String]
  enable_tools : Bool
  web_search : Bool
  policy : AnalysisPolicy
  max_context_chars : Int
  scope : Array[String]
} derive(ToJson, FromJson, Show)

///|
pub fn ResearchPaperAnalyzeConfig::new(
  paper_id~ : String,
  analysis_kind? : String = "summary",
  model? : String? = None,
  cwd? : String? = None,
  home? : String? = None,
  system_prompt? : String? = None,
  preferred_skills? : Array[String] = [],
  enable_tools? : Bool = true,
  web_search? : Bool = false,
  policy? : AnalysisPolicy = AnalysisPolicy::new(),
  max_context_chars? : Int = 16_000,
  scope? : Array[String] = [],
) -> ResearchPaperAnalyzeConfig {
  ResearchPaperAnalyzeConfig::{
    paper_id,
    analysis_kind,
    model,
    cwd,
    home,
    system_prompt,
    preferred_skills,
    enable_tools,
    web_search,
    policy,
    max_context_chars,
    scope,
  }
}

///|
pub(all) struct ArxivSearchRequest {
  query : String?
  id_list : Array[String]
  max_results : Int
  start : Int
  sort_by : String
  sort_order : String
} derive(ToJson, FromJson, Show)

///|
pub fn ArxivSearchRequest::new(
  query? : String? = None,
  id_list? : Array[String] = [],
  max_results? : Int = 10,
  start? : Int = 0,
  sort_by? : String = "submittedDate",
  sort_order? : String = "descending",
) -> ArxivSearchRequest {
  ArxivSearchRequest::{
    query,
    id_list,
    max_results,
    start,
    sort_by,
    sort_order,
  }
}

///|
pub(all) struct ArxivFeedResult {
  papers : Array[ResearchPaper]
  total_results : Int
  start_index : Int
  items_per_page : Int
} derive(ToJson, FromJson, Show)

///|
pub(all) struct ArxivClient {
  fetch_feed : async (ArxivSearchRequest) -> Result[String, String]
  fetch_pdf : async (String) -> Result[Bytes, String]
}

///|
pub fn ArxivClient::new(
  fetch_feed? : async (ArxivSearchRequest) -> Result[String, String] = default_arxiv_fetch_feed,
  fetch_pdf? : async (String) -> Result[Bytes, String] = default_arxiv_fetch_pdf,
) -> ArxivClient {
  ArxivClient::{ fetch_feed, fetch_pdf }
}

///|
pub(all) struct PaperTextExtractor {
  extract : async (String, ResearchPaper) -> Result[String, String]
}

///|
pub fn PaperTextExtractor::new(
  extract~ : async (String, ResearchPaper) -> Result[String, String],
) -> PaperTextExtractor {
  PaperTextExtractor::{ extract, }
}

///|
pub(all) struct ResearchJobBundle {
  definition : JobDefinition
  workflows : Array[WorkflowDefinition]
  bindings : Array[ChatBinding]
} derive(ToJson, FromJson, Show)

///|
pub fn research_scope() -> String {
  "research"
}

///|
pub fn research_topic_scope(topic_id : String) -> String {
  "research.topic:\{topic_id}"
}

///|
pub fn research_paper_scope(paper_id : String) -> String {
  "research.paper:\{paper_id}"
}

///|
fn research_scopes(extra : Array[String]) -> Array[String] {
  let scopes = [research_scope()]
  for scope in extra {
    if !scopes.contains(scope) {
      scopes.push(scope)
    }
  }
  scopes
}

///|
pub fn research_paper_binding(
  paper_id : String,
  now_ms : Int,
  title? : String? = None,
) -> ChatBinding {
  let resolved_title = match title {
    Some(title) => Some(title)
    None => Some("Research paper \{paper_id}")
  }
  ChatBinding::{
    id: "research.paper.ask:\{paper_id}",
    title: resolved_title,
    artifact_query: ArtifactQuery::new(
      scope=Some(research_paper_scope(paper_id)),
    ),
    scope: [research_scope(), research_paper_scope(paper_id)],
    created_at: now_ms,
    updated_at: now_ms,
  }
}

///|
pub fn research_topic_binding(
  topic_id : String,
  now_ms : Int,
  title? : String? = None,
) -> ChatBinding {
  let resolved_title = match title {
    Some(title) => Some(title)
    None => Some("Research topic \{topic_id}")
  }
  ChatBinding::{
    id: "research.topic.ask:\{topic_id}",
    title: resolved_title,
    artifact_query: ArtifactQuery::new(
      scope=Some(research_topic_scope(topic_id)),
    ),
    scope: [research_scope(), research_topic_scope(topic_id)],
    created_at: now_ms,
    updated_at: now_ms,
  }
}

///|
fn normalize_arxiv_id(id : String) -> (String, Int) {
  let pieces = id.split("v").map(fn(piece) { piece.to_string() }).collect()
  if pieces.length() == 2 {
    let version = @strconv.parse_int(pieces[1]) catch { _ => return (id, 1) }
    (pieces[0], version)
  } else {
    (id, 1)
  }
}

///|
fn xml_text(raw : String) -> String {
  let normalized = raw
    .replace(old="&lt;", new="<")
    .replace(old="&gt;", new=">")
    .replace(old="&amp;", new="&")
    .replace(old="&quot;", new="\"")
    .replace(old="&#39;", new="'")
    .replace(old="\n", new=" ")
    .replace(old="\r", new=" ")
  let collapsed = normalized
    .split(" ")
    .map(fn(part) { part.to_string() })
    .collect()
    .filter(fn(part) { !part.is_blank() })
    .join(" ")
  collapsed.trim().to_string()
}

///|
fn between(
  text : String,
  start : String,
  end : String,
  from? : Int = 0,
) -> (String, Int)? {
  guard text[from:].find(start) is Some(start_rel) else { return None }
  let start_idx = from + start_rel + start.length()
  guard text[start_idx:].find(end) is Some(end_rel) else { return None }
  let end_idx = start_idx + end_rel
  Some((text[start_idx:end_idx].to_string(), end_idx + end.length()))
}

///|
fn all_between(text : String, start : String, end : String) -> Array[String] {
  let out : Array[String] = []
  let mut cursor = 0
  while between(text, start, end, from=cursor) is Some((value, next_cursor)) {
    out.push(value)
    cursor = next_cursor
  }
  out
}

///|
fn extract_xml_tag(text : String, tag : String) -> String? {
  between(text, "<\{tag}>", "</\{tag}>").map(fn(pair) { xml_text(pair.0) })
}

///|
fn extract_attr(text : String, name : String) -> String? {
  let pattern = "\{name}=\""
  guard text.find(pattern) is Some(start) else { return None }
  let offset = start + pattern.length()
  guard text[offset:].find("\"") is Some(end) else { return None }
  Some(text[offset:offset + end].to_string())
}

///|
fn extract_link_href(entry : String, title : String) -> String? {
  let segments = entry
    .split("<link ")
    .map(fn(part) { part.to_string() })
    .collect()
  for segment in segments {
    if segment.contains("title=\"\{title}\"") ||
      (segment.contains("type=\"application/pdf\"") && title == "pdf") {
      if extract_attr(segment, "href") is Some(href) {
        return Some(href)
      }
    }
  }
  None
}

///|
fn parse_feed_count(feed : String, tag : String) -> Int {
  match extract_xml_tag(feed, tag) {
    Some(value) => @strconv.parse_int(value) catch { _ => 0 }
    None => 0
  }
}

///|
pub fn parse_arxiv_feed(feed : String) -> ArxivFeedResult {
  let papers : Array[ResearchPaper] = []
  let entries = all_between(feed, "<entry>", "</entry>")
  for entry in entries {
    let id_value = extract_xml_tag(entry, "id").unwrap_or("")
    let arxiv_id = if id_value.find("/") is Some(_) {
      let parts = id_value
        .split("/")
        .map(fn(part) { part.to_string() })
        .collect()
      parts.get(parts.length() - 1).unwrap_or(id_value)
    } else {
      id_value
    }
    let (base_id, version) = normalize_arxiv_id(arxiv_id)
    let title = extract_xml_tag(entry, "title").unwrap_or("")
    let abstract_text = extract_xml_tag(entry, "summary").unwrap_or("")
    let authors = all_between(entry, "<author>", "</author>")
      .map(fn(author_block) {
        extract_xml_tag(author_block, "name").unwrap_or("")
      })
      .filter(fn(author) { !author.is_blank() })
    let categories = entry
      .split("<category ")
      .map(fn(part) { part.to_string() })
      .collect()
      .map(fn(part) { extract_attr(part, "term").unwrap_or("") })
      .filter(fn(category) { !category.is_blank() })
    let primary_category = categories.get(0)
    papers.push(ResearchPaper::{
      id: arxiv_id,
      base_id,
      version,
      title,
      abstract_text,
      authors,
      categories,
      primary_category,
      published_at: extract_xml_tag(entry, "published"),
      updated_at: extract_xml_tag(entry, "updated"),
      abs_url: if id_value.is_blank() {
        None
      } else {
        Some(id_value)
      },
      pdf_url: extract_link_href(entry, "pdf"),
    })
  }
  ArxivFeedResult::{
    papers,
    total_results: parse_feed_count(feed, "opensearch:totalResults"),
    start_index: parse_feed_count(feed, "opensearch:startIndex"),
    items_per_page: parse_feed_count(feed, "opensearch:itemsPerPage"),
  }
}

///|
priv struct ParsedUrl {
  base_url : String
  path : String
}

///|
fn parse_url(url : String) -> ParsedUrl? {
  guard url.find("://") is Some(protocol_end) else { return None }
  let scheme = url[:protocol_end].to_string()
  let rest = url[protocol_end + 3:].to_string()
  let slash_index = rest.find("/").unwrap_or(rest.length())
  let host = rest[:slash_index].to_string()
  let path = if slash_index < rest.length() {
    rest[slash_index:].to_string()
  } else {
    "/"
  }
  Some(ParsedUrl::{ base_url: "\{scheme}://\{host}", path })
}

///|
fn query_encode(text : String) -> String {
  let encoded = text
    .replace(old=" ", new="+")
    .replace(old="\"", new="%22")
    .replace(old=",", new="%2C")
    .replace(old=":", new="%3A")
    .replace(old="/", new="%2F")
  encoded
}

///|
fn arxiv_query_url(request : ArxivSearchRequest) -> String {
  let params : Array[String] = [
    "start=\{request.start}",
    "max_results=\{request.max_results}",
    "sortBy=\{query_encode(request.sort_by)}",
    "sortOrder=\{query_encode(request.sort_order)}",
  ]
  if !request.id_list.is_empty() {
    let ids = request.id_list.join(",")
    params.push("id_list=\{query_encode(ids)}")
  } else if request.query is Some(query) {
    params.push("search_query=\{query_encode(query)}")
  } else {
    params.push("search_query=all")
  }
  let query = params.join("&")
  "https://export.arxiv.org/api/query?\{query}"
}

///|
async fn default_arxiv_fetch_feed(
  request : ArxivSearchRequest,
) -> Result[String, String] {
  let (response, body) = @http.get(arxiv_query_url(request))
  guard response.code is (200..=299) else {
    return Err("arXiv API returned \{response.code}")
  }
  Ok(body.text())
}

///|
async fn default_arxiv_fetch_pdf(url : String) -> Result[Bytes, String] {
  let parsed = match parse_url(url) {
    Some(parsed) => parsed
    None => return Err("Invalid PDF URL: \{url}")
  }
  let client = @http.Client::new(parsed.base_url)
  defer client.close()
  client.request(Get, parsed.path)
  let response = client.end_request()
  guard response.code is (200..=299) else {
    return Err("arXiv PDF download returned \{response.code}")
  }
  Ok(client.read_all().binary())
}

///|
pub async fn ArxivClient::search(
  self : ArxivClient,
  request : ArxivSearchRequest,
) -> Result[ArxivFeedResult, String] {
  let feed = match (self.fetch_feed)(request) {
    Ok(feed) => feed
    Err(error) => return Err(error)
  }
  Ok(parse_arxiv_feed(feed))
}

///|
fn scope_with_topic(
  topic_id : String?,
  paper_id : String?,
  extra : Array[String],
) -> Array[String] {
  let scopes = research_scopes(extra)
  if topic_id is Some(topic_id) &&
    !scopes.contains(research_topic_scope(topic_id)) {
    scopes.push(research_topic_scope(topic_id))
  }
  if paper_id is Some(paper_id) &&
    !scopes.contains(research_paper_scope(paper_id)) {
    scopes.push(research_paper_scope(paper_id))
  }
  scopes
}

///|
fn paper_metadata_artifact_type() -> String {
  "research.paper.meta"
}

///|
fn paper_pdf_artifact_type() -> String {
  "research.paper.pdf"
}

///|
fn paper_text_artifact_type() -> String {
  "research.paper.text"
}

///|
fn paper_chunks_artifact_type() -> String {
  "research.paper.chunks"
}

///|
fn topic_feed_artifact_type() -> String {
  "research.topic.feed"
}

///|
fn analysis_report_type(kind : String) -> String {
  "research.paper.analysis.\{kind}.report"
}

///|
fn analysis_result_type(kind : String) -> String {
  "research.paper.analysis.\{kind}.result"
}

///|
async fn persist_paper_artifacts(
  artifacts : ArtifactStore,
  run : JobRun,
  paper : ResearchPaper,
  topic_id : String?,
  extra_scope : Array[String],
  now_ms : Int,
  client : ArxivClient,
  download_pdf : Bool,
) -> (ArtifactRecord, ArtifactRecord?) {
  let scope = scope_with_topic(topic_id, Some(paper.id), extra_scope)
  let topic_value = topic_id.unwrap_or("")
  let meta = artifacts.write(
    ArtifactWriteRequest::new(
      run_id=run.id,
      job_id=run.job_id,
      artifact_type=paper_metadata_artifact_type(),
      logical_key=Some(paper.id),
      content=paper.to_json().stringify(),
      content_type="application/json",
      file_name=Some("paper.json"),
      metadata={
        "paper_id": paper.id,
        "base_id": paper.base_id,
        "version": paper.version,
        "title": paper.title,
        "topic_id": topic_value,
      },
      scope~,
      append_only=false,
    ),
    "\{run.id}:paper-meta:\{paper.id}",
    now_ms,
  )
  let pdf = if download_pdf {
    match paper.pdf_url {
      Some(pdf_url) =>
        match (client.fetch_pdf)(pdf_url) {
          Ok(bytes) =>
            Some(
              artifacts.write_bytes(
                ArtifactBytesWriteRequest::{
                  run_id: run.id,
                  job_id: run.job_id,
                  artifact_type: paper_pdf_artifact_type(),
                  logical_key: Some(paper.id),
                  content_type: "application/pdf",
                  file_name: Some("paper.pdf"),
                  metadata: {
                    "paper_id": paper.id,
                    "source_url": pdf_url,
                    "topic_id": topic_value,
                  },
                  scope,
                  content: bytes,
                  append_only: false,
                },
                "\{run.id}:paper-pdf:\{paper.id}",
                now_ms,
              ),
            )
          Err(_) => None
        }
      None => None
    }
  } else {
    None
  }
  (meta, pdf)
}

///|
fn latest_artifact_by_type(
  artifacts : ArtifactStore,
  artifact_type : String,
  logical_key : String,
) -> ArtifactRecord? {
  artifacts
  .list()
  .filter(fn(artifact) {
    artifact.artifact_type == artifact_type &&
    artifact.logical_key == Some(logical_key) &&
    artifact.status is ArtifactStatus::Active
  })
  .get(0)
}

///|
async fn load_research_paper(
  artifacts : ArtifactStore,
  paper_id : String,
) -> ResearchPaper? {
  let meta = match
    latest_artifact_by_type(artifacts, paper_metadata_artifact_type(), paper_id) {
    Some(meta) => meta
    None => return None
  }
  let content = match artifacts.read_text(meta.id) {
    Some(content) => content
    None => return None
  }
  let parsed : ResearchPaper = @json.from_json(@json.parse(content)) catch {
    _ => return None
  }
  Some(parsed)
}

///|
fn default_extracted_text(paper : ResearchPaper) -> String {
  let author_text = paper.authors.join(", ")
  let category_text = paper.categories.join(", ")
  [
    "# \{paper.title}",
    if paper.authors.is_empty() {
      ""
    } else {
      "Authors: \{author_text}"
    },
    if paper.categories.is_empty() {
      ""
    } else {
      "Categories: \{category_text}"
    },
    "",
    paper.abstract_text,
  ]
  .filter(fn(line) { !line.is_blank() })
  .join("\n")
}

///|
pub fn default_paper_text_extractor() -> PaperTextExtractor {
  PaperTextExtractor::new(extract=async fn(pdf_path, paper) {
    let process = @spawn.spawn(
      "pdftotext",
      [pdf_path[:], "-"[:]],
      timeout=10_000,
    ) catch {
      _ => return Ok(default_extracted_text(paper))
    }
    if process.status != 0 || process.stdout.is_blank() {
      Ok(default_extracted_text(paper))
    } else {
      Ok(process.stdout.trim().to_string())
    }
  })
}

///|
fn estimate_tokens(text : String) -> Int {
  let chars = text.length()
  if chars == 0 {
    0
  } else {
    chars / 4 + 1
  }
}

///|
fn chunk_text(
  paper_id : String,
  text : String,
  chunk_chars : Int,
) -> Array[ResearchChunk] {
  let paragraphs = text
    .split("\n\n")
    .map(fn(part) { part.trim().to_string() })
    .collect()
  let chunks : Array[ResearchChunk] = []
  let mut current = ""
  let mut index = 0
  for paragraph in paragraphs {
    if paragraph.is_blank() {
      continue
    }
    let candidate = if current.is_blank() {
      paragraph
    } else {
      "\{current}\n\n\{paragraph}"
    }
    if !current.is_blank() && candidate.length() > chunk_chars {
      chunks.push(ResearchChunk::{
        id: "\{paper_id}:chunk:\{index}",
        paper_id,
        index,
        text: current,
        heading: None,
        token_estimate: estimate_tokens(current),
      })
      index += 1
      current = paragraph
    } else {
      current = candidate
    }
  }
  if !current.is_blank() {
    chunks.push(ResearchChunk::{
      id: "\{paper_id}:chunk:\{index}",
      paper_id,
      index,
      text: current,
      heading: None,
      token_estimate: estimate_tokens(current),
    })
  }
  chunks
}

///|
fn resolve_paper_id(
  context : WorkflowStepContext,
  configured : String?,
) -> String? {
  match configured {
    Some(paper_id) => Some(paper_id)
    None => {
      for output in context.outputs.values() {
        match output {
          Object(obj) =>
            match obj.get("paper_id") {
              Some(String(paper_id)) => return Some(paper_id)
              _ => ()
            }
          _ => ()
        }
      }
      None
    }
  }
}

///|
fn research_analysis_prompt(
  paper : ResearchPaper,
  text : String,
  config : ResearchPaperAnalyzeConfig,
) -> String {
  let author_text = paper.authors.join(", ")
  let category_text = paper.categories.join(", ")
  let instruction = match config.analysis_kind {
    "summary" =>
      "Write a structured summary covering the paper's problem, method, results, and practical takeaways."
    "novelty" =>
      "Explain what is novel in this paper, what it changes versus prior work, and where the contribution appears weak or incremental."
    "critique" =>
      "Critically evaluate the paper's assumptions, method quality, evidence strength, and likely failure modes."
    "reproduction" =>
      "Produce a reproduction checklist with datasets, training details, evaluation details, and missing implementation details."
    _ => "Analyze this paper carefully and produce a grounded report."
  }
  let context_text = if text.length() > config.max_context_chars {
    text[:config.max_context_chars].to_string()
  } else {
    text
  }
  [
    instruction,
    "Paper id: \{paper.id}",
    "Title: \{paper.title}",
    if paper.authors.is_empty() {
      ""
    } else {
      "Authors: \{author_text}"
    },
    if paper.categories.is_empty() {
      ""
    } else {
      "Categories: \{category_text}"
    },
    "",
    "Abstract:",
    paper.abstract_text,
    "",
    "Extracted paper text:",
    context_text,
  ]
  .filter(fn(part) { !part.is_blank() })
  .join("\n\n")
}

///|
pub fn research_topic_sync_step_handler(
  runtime~ : RuntimeManager,
  client? : ArxivClient = ArxivClient::new(),
  now? : () -> Int = fn() { @async.now().to_int() },
  kind? : String = "research.topic.sync",
) -> WorkflowStepHandler {
  let store = runtime.store()
  let artifacts = ArtifactStore::new(store~)
  WorkflowStepHandler::new(kind~, run=async fn(context) {
    let config : ResearchTopicSyncConfig = @json.from_json(context.step.config) catch {
      error => return Err("Invalid research topic sync config: \{error}")
    }
    let result = match
      client.search(
        ArxivSearchRequest::new(
          query=Some(config.query),
          max_results=config.max_results,
        ),
      ) {
      Ok(result) => result
      Err(error) => return Err(error)
    }
    let current = now()
    let topic_scope = scope_with_topic(
      Some(config.topic_id),
      None,
      config.scope,
    )
    let feed_artifact = artifacts.write(
      ArtifactWriteRequest::new(
        run_id=context.run.id,
        job_id=context.run.job_id,
        artifact_type=topic_feed_artifact_type(),
        logical_key=Some(config.topic_id),
        content=result.to_json().stringify(),
        content_type="application/json",
        file_name=Some("topic-feed.json"),
        metadata={
          "topic_id": config.topic_id,
          "query": config.query,
          "count": result.papers.length(),
        },
        scope=topic_scope,
        append_only=true,
      ),
      "\{context.run.id}:topic-feed:\{config.topic_id}:\{current}",
      current,
    )
    let paper_ids : Array[String] = []
    for paper in result.papers {
      paper_ids.push(paper.id)
      ignore(
        persist_paper_artifacts(
          artifacts,
          context.run,
          paper,
          Some(config.topic_id),
          config.scope,
          current,
          client,
          config.download_pdf,
        ),
      )
    }
    let binding_title = match config.title {
      Some(title) => Some(title)
      None => Some("Research topic \{config.topic_id}")
    }
    store.save_chat_binding(
      research_topic_binding(config.topic_id, current, title=binding_title),
    )
    Ok(
      WorkflowStepResult::new(
        output={
          "topic_id": config.topic_id,
          "query": config.query,
          "paper_ids": paper_ids,
          "feed_artifact_id": feed_artifact.id,
          "binding_id": "research.topic.ask:\{config.topic_id}",
        },
        summary=Some("Synced \{paper_ids.length()} paper(s) from arXiv"),
        logs=["topic feed artifact written: \{feed_artifact.id}"],
      ),
    )
  })
}

///|
pub fn research_paper_fetch_step_handler(
  runtime~ : RuntimeManager,
  client? : ArxivClient = ArxivClient::new(),
  now? : () -> Int = fn() { @async.now().to_int() },
  kind? : String = "research.paper.fetch",
) -> WorkflowStepHandler {
  let store = runtime.store()
  let artifacts = ArtifactStore::new(store~)
  WorkflowStepHandler::new(kind~, run=async fn(context) {
    let config : ResearchPaperFetchConfig = @json.from_json(context.step.config) catch {
      error => return Err("Invalid research paper fetch config: \{error}")
    }
    let request = if config.paper_id is Some(paper_id) {
      ArxivSearchRequest::new(id_list=[paper_id], max_results=1)
    } else if config.query is Some(query) {
      ArxivSearchRequest::new(query=Some(query), max_results=config.max_results)
    } else {
      return Err("research.paper.fetch requires paper_id or query")
    }
    let result = match client.search(request) {
      Ok(result) => result
      Err(error) => return Err(error)
    }
    guard result.papers.get(0) is Some(paper) else {
      return Err("No paper matched the research.paper.fetch request")
    }
    let current = now()
    let (meta, pdf) = persist_paper_artifacts(
      artifacts,
      context.run,
      paper,
      config.topic_id,
      config.scope,
      current,
      client,
      config.download_pdf,
    )
    let pdf_artifact_id = pdf.map(fn(record) { record.id }).unwrap_or("")
    store.save_chat_binding(
      research_paper_binding(paper.id, current, title=Some(paper.title)),
    )
    Ok(
      WorkflowStepResult::new(
        output={
          "paper_id": paper.id,
          "title": paper.title,
          "meta_artifact_id": meta.id,
          "pdf_artifact_id": pdf_artifact_id,
          "binding_id": "research.paper.ask:\{paper.id}",
        },
        summary=Some("Fetched research paper \{paper.id}"),
        logs=["paper metadata artifact written: \{meta.id}"],
      ),
    )
  })
}

///|
pub fn research_paper_parse_step_handler(
  runtime~ : RuntimeManager,
  extractor? : PaperTextExtractor = default_paper_text_extractor(),
  now? : () -> Int = fn() { @async.now().to_int() },
  kind? : String = "research.paper.parse",
) -> WorkflowStepHandler {
  let store = runtime.store()
  let artifacts = ArtifactStore::new(store~)
  WorkflowStepHandler::new(kind~, run=async fn(context) {
    let config : ResearchPaperParseConfig = @json.from_json(context.step.config) catch {
      error => return Err("Invalid research paper parse config: \{error}")
    }
    let paper_id = match resolve_paper_id(context, config.paper_id) {
      Some(paper_id) => paper_id
      None => return Err("research.paper.parse could not resolve paper_id")
    }
    let paper = match load_research_paper(artifacts, paper_id) {
      Some(paper) => paper
      None => return Err("Missing paper metadata artifact for \{paper_id}")
    }
    let text = match
      latest_artifact_by_type(artifacts, paper_pdf_artifact_type(), paper_id) {
      Some(pdf_artifact) =>
        match (extractor.extract)(pdf_artifact.path, paper) {
          Ok(text) => text
          Err(error) => return Err(error)
        }
      None => default_extracted_text(paper)
    }
    let chunks = chunk_text(paper_id, text, config.chunk_chars)
    let current = now()
    let scope = scope_with_topic(None, Some(paper_id), config.scope)
    let text_artifact = artifacts.write(
      ArtifactWriteRequest::new(
        run_id=context.run.id,
        job_id=context.run.job_id,
        artifact_type=paper_text_artifact_type(),
        logical_key=Some(paper_id),
        content=text,
        content_type="text/plain",
        file_name=Some("paper.txt"),
        metadata={ "paper_id": paper_id, "chunk_chars": config.chunk_chars },
        scope~,
        append_only=false,
      ),
      "\{context.run.id}:paper-text:\{paper_id}",
      current,
    )
    let chunks_artifact = artifacts.write(
      ArtifactWriteRequest::new(
        run_id=context.run.id,
        job_id=context.run.job_id,
        artifact_type=paper_chunks_artifact_type(),
        logical_key=Some(paper_id),
        content=chunks.to_json().stringify(),
        content_type="application/json",
        file_name=Some("chunks.json"),
        metadata={ "paper_id": paper_id, "chunk_count": chunks.length() },
        scope~,
        append_only=false,
      ),
      "\{context.run.id}:paper-chunks:\{paper_id}",
      current,
    )
    store.save_chat_binding(
      research_paper_binding(paper_id, current, title=Some(paper.title)),
    )
    Ok(
      WorkflowStepResult::new(
        output={
          "paper_id": paper_id,
          "text_artifact_id": text_artifact.id,
          "chunks_artifact_id": chunks_artifact.id,
          "chunk_count": chunks.length(),
        },
        summary=Some(
          "Parsed research paper \{paper_id} into \{chunks.length()} chunk(s)",
        ),
        logs=[
          "paper text artifact written: \{text_artifact.id}",
          "paper chunks artifact written: \{chunks_artifact.id}",
        ],
      ),
    )
  })
}

///|
fn find_existing_research_analysis(
  artifacts : ArtifactStore,
  config : ResearchPaperAnalyzeConfig,
) -> ArtifactRecord? {
  if !config.policy.skip_if_artifact_exists {
    return None
  }
  artifacts
  .list(
    query=ArtifactQuery::new(
      artifact_type=Some(analysis_report_type(config.analysis_kind)),
      logical_key=Some("\{config.paper_id}:\{config.analysis_kind}"),
      status=Some(ArtifactStatus::Active),
    ),
  )
  .get(0)
}

///|
pub fn research_paper_analyze_step_handler(
  runtime~ : RuntimeManager,
  executor? : AnalysisExecutor = default_analysis_executor(),
  now? : () -> Int = fn() { @async.now().to_int() },
  kind? : String = "research.paper.analyze",
) -> WorkflowStepHandler {
  let store = runtime.store()
  let artifacts = ArtifactStore::new(store~)
  WorkflowStepHandler::new(kind~, run=async fn(context) {
    let config : ResearchPaperAnalyzeConfig = @json.from_json(
      context.step.config,
    ) catch {
      error => return Err("Invalid research paper analyze config: \{error}")
    }
    if find_existing_research_analysis(artifacts, config) is Some(existing) {
      return Ok(
        WorkflowStepResult::new(
          output={
            "paper_id": config.paper_id,
            "analysis_kind": config.analysis_kind,
            "report_artifact_id": existing.id,
            "status": "skipped",
          },
          summary=Some("Skipped existing research analysis"),
          logs=["existing analysis reused: \{existing.id}"],
        ),
      )
    }
    let paper = match load_research_paper(artifacts, config.paper_id) {
      Some(paper) => paper
      None =>
        return Err("Missing paper metadata artifact for \{config.paper_id}")
    }
    let text_artifact = match
      latest_artifact_by_type(
        artifacts,
        paper_text_artifact_type(),
        config.paper_id,
      ) {
      Some(text_artifact) => text_artifact
      None =>
        return Err("Missing parsed paper text artifact for \{config.paper_id}")
    }
    let text = match artifacts.read_text(text_artifact.id) {
      Some(text) => text
      None =>
        return Err("Unable to read parsed paper text for \{config.paper_id}")
    }
    let request = AnalysisRequest::{
      job_id: context.run.job_id,
      run_id: context.run.id,
      step_id: context.step.id,
      prompt: research_analysis_prompt(paper, text, config),
      model_name: config.model.unwrap_or("default"),
      cwd: config.cwd.unwrap_or("."),
      home: config.home,
      system_prompt: config.system_prompt.unwrap_or(
        default_analysis_system_prompt(),
      ),
      preferred_skills: config.preferred_skills,
      enable_tools: config.enable_tools,
      web_search: config.web_search,
    }
    let execution = match config.policy.timeout_ms {
      Some(timeout_ms) =>
        @async.with_timeout(timeout_ms, () => (executor.run)(request)) catch {
          @async.TimeoutError =>
            return Err(timeout_error_message(context.step.id, timeout_ms))
          error => return Err("Research analysis execution failed: \{error}")
        }
      None =>
        (executor.run)(request) catch {
          error => return Err("Research analysis execution failed: \{error}")
        }
    }
    let execution = match execution {
      Ok(execution) => execution
      Err(error) => return Err(error)
    }
    if policy_budget_exceeded(execution, config.policy) is Some(error) {
      return Err(error)
    }
    let current = now()
    let logical_key = "\{config.paper_id}:\{config.analysis_kind}"
    let scope = scope_with_topic(None, Some(config.paper_id), config.scope)
    let conversation_id = execution.conversation_id.unwrap_or("")
    let usage = usage_json(execution.usage).unwrap_or({})
    let report_artifact = artifacts.write(
      ArtifactWriteRequest::new(
        run_id=context.run.id,
        job_id=context.run.job_id,
        artifact_type=analysis_report_type(config.analysis_kind),
        logical_key=Some(logical_key),
        content=execution.content,
        content_type="text/markdown",
        file_name=Some("\{config.analysis_kind}.md"),
        metadata={
          "paper_id": config.paper_id,
          "analysis_kind": config.analysis_kind,
          "model": execution.model_name,
          "conversation_id": conversation_id,
        },
        scope~,
        append_only=true,
      ),
      "\{context.run.id}:research-analysis-report:\{logical_key}:\{current}",
      current,
    )
    let result_payload : Json = {
      "paper_id": config.paper_id,
      "analysis_kind": config.analysis_kind,
      "content": execution.content,
      "model": execution.model_name,
      "conversation_id": conversation_id,
      "usage": usage,
    }
    let result_artifact = artifacts.write(
      ArtifactWriteRequest::new(
        run_id=context.run.id,
        job_id=context.run.job_id,
        artifact_type=analysis_result_type(config.analysis_kind),
        logical_key=Some(logical_key),
        content=result_payload.stringify(),
        content_type="application/json",
        file_name=Some("\{config.analysis_kind}.json"),
        metadata={
          "paper_id": config.paper_id,
          "analysis_kind": config.analysis_kind,
          "report_artifact_id": report_artifact.id,
        },
        scope~,
        append_only=true,
      ),
      "\{context.run.id}:research-analysis-result:\{logical_key}:\{current}",
      current,
    )
    Ok(
      WorkflowStepResult::new(
        output={
          "paper_id": config.paper_id,
          "analysis_kind": config.analysis_kind,
          "report_artifact_id": report_artifact.id,
          "result_artifact_id": result_artifact.id,
          "usage": usage,
        },
        summary=Some(
          "Completed \{config.analysis_kind} analysis for \{config.paper_id}",
        ),
        metrics=result_metrics(execution),
        logs=[
          "research analysis report written: \{report_artifact.id}",
          "research analysis result written: \{result_artifact.id}",
        ],
      ),
    )
  })
}

///|
fn research_bundle(
  definition : JobDefinition,
  workflow : WorkflowDefinition,
  bindings : Array[ChatBinding],
) -> ResearchJobBundle {
  ResearchJobBundle::{ definition, workflows: [workflow], bindings }
}

///|
pub fn research_topic_sync_bundle(
  job_id~ : String,
  config~ : ResearchTopicSyncConfig,
  now_ms : Int,
  schedule? : SchedulePolicy? = None,
) -> ResearchJobBundle {
  let workflow_id = "\{job_id}.workflow"
  let workflow = WorkflowDefinition::{
    id: workflow_id,
    kind: "research.topic.sync",
    steps: [
      WorkflowStepDefinition::{
        id: "sync",
        kind: "research.topic.sync",
        config: config.to_json(),
        retry_policy: Some(RetryPolicy::{
          max_attempts: 2,
          backoff_ms: Some(60_000),
        }),
      },
    ],
    output_bindings: [],
  }
  let definition = JobDefinition::{
    id: job_id,
    kind: "research.topic.sync",
    enabled: true,
    config: config.to_json(),
    schedule,
    retry_policy: Some(RetryPolicy::{
      max_attempts: 2,
      backoff_ms: Some(60_000),
    }),
    workflow_id: Some(workflow_id),
    created_at: now_ms,
    updated_at: now_ms,
    tags: ["research", "topic-sync", config.topic_id],
  }
  research_bundle(definition, workflow, [
    research_topic_binding(config.topic_id, now_ms, title=config.title),
  ])
}

///|
pub fn research_paper_fetch_bundle(
  job_id~ : String,
  config~ : ResearchPaperFetchConfig,
  now_ms : Int,
) -> ResearchJobBundle {
  let workflow_id = "\{job_id}.workflow"
  let workflow = WorkflowDefinition::{
    id: workflow_id,
    kind: "research.paper.fetch",
    steps: [
      WorkflowStepDefinition::{
        id: "fetch",
        kind: "research.paper.fetch",
        config: config.to_json(),
        retry_policy: Some(RetryPolicy::{
          max_attempts: 2,
          backoff_ms: Some(30_000),
        }),
      },
    ],
    output_bindings: [],
  }
  let tags = ["research", "paper-fetch"]
  research_bundle(
    JobDefinition::{
      id: job_id,
      kind: "research.paper.fetch",
      enabled: true,
      config: config.to_json(),
      schedule: None,
      retry_policy: Some(RetryPolicy::{
        max_attempts: 2,
        backoff_ms: Some(30_000),
      }),
      workflow_id: Some(workflow_id),
      created_at: now_ms,
      updated_at: now_ms,
      tags,
    },
    workflow,
    [],
  )
}

///|
pub fn research_paper_parse_bundle(
  job_id~ : String,
  config~ : ResearchPaperParseConfig,
  now_ms : Int,
) -> ResearchJobBundle {
  let workflow_id = "\{job_id}.workflow"
  let workflow = WorkflowDefinition::{
    id: workflow_id,
    kind: "research.paper.parse",
    steps: [
      WorkflowStepDefinition::{
        id: "parse",
        kind: "research.paper.parse",
        config: config.to_json(),
        retry_policy: Some(RetryPolicy::{ max_attempts: 1, backoff_ms: None }),
      },
    ],
    output_bindings: [],
  }
  research_bundle(
    JobDefinition::{
      id: job_id,
      kind: "research.paper.parse",
      enabled: true,
      config: config.to_json(),
      schedule: None,
      retry_policy: Some(RetryPolicy::{ max_attempts: 1, backoff_ms: None }),
      workflow_id: Some(workflow_id),
      created_at: now_ms,
      updated_at: now_ms,
      tags: ["research", "paper-parse"],
    },
    workflow,
    [],
  )
}

///|
pub fn research_paper_analyze_bundle(
  job_id~ : String,
  config~ : ResearchPaperAnalyzeConfig,
  now_ms : Int,
) -> ResearchJobBundle {
  let workflow_id = "\{job_id}.workflow"
  let workflow = WorkflowDefinition::{
    id: workflow_id,
    kind: "research.paper.analyze",
    steps: [
      WorkflowStepDefinition::{
        id: "analyze",
        kind: "research.paper.analyze",
        config: config.to_json(),
        retry_policy: Some(RetryPolicy::{ max_attempts: 1, backoff_ms: None }),
      },
    ],
    output_bindings: [],
  }
  research_bundle(
    JobDefinition::{
      id: job_id,
      kind: "research.paper.analyze",
      enabled: true,
      config: config.to_json(),
      schedule: None,
      retry_policy: Some(RetryPolicy::{ max_attempts: 1, backoff_ms: None }),
      workflow_id: Some(workflow_id),
      created_at: now_ms,
      updated_at: now_ms,
      tags: ["research", "paper-analyze", config.analysis_kind],
    },
    workflow,
    [research_paper_binding(config.paper_id, now_ms)],
  )
}
