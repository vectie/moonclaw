///|
pub struct ChatService {
  store : SystemStore
  artifacts : ArtifactStore
  memories : MemoryService
}

///|
pub fn ChatService::new(store~ : SystemStore) -> ChatService {
  ChatService::{
    artifacts: ArtifactStore::new(store~),
    memories: MemoryService::new(store~),
    store,
  }
}

///|
fn normalize_term(term : String) -> String {
  term.trim().to_string().to_lower()
}

///|
fn tokenize_question(question : String) -> Array[String] {
  question
  .split(" ")
  .map(fn(term) { normalize_term(term.to_string()) })
  .filter(fn(term) { !term.is_blank() && term.length() > 1 })
  .collect()
}

///|
fn[T] pick_override(request : T?, binding : T?, default : T?) -> T? {
  match request {
    Some(value) => Some(value)
    None =>
      match binding {
        Some(value) => Some(value)
        None => default
      }
  }
}

///|
fn matches_merged_query(
  artifact : ArtifactRecord,
  binding_query : ArtifactQuery?,
  request_query : ArtifactQuery?,
) -> Bool {
  let binding_query = binding_query.unwrap_or(ArtifactQuery::new())
  let request_query = request_query.unwrap_or(ArtifactQuery::new())
  let status = pick_override(
    request_query.status,
    binding_query.status,
    Some(ArtifactStatus::Active),
  )
  let job_id = pick_override(request_query.job_id, binding_query.job_id, None)
  let run_id = pick_override(request_query.run_id, binding_query.run_id, None)
  let artifact_type = pick_override(
    request_query.artifact_type,
    binding_query.artifact_type,
    None,
  )
  let logical_key = pick_override(
    request_query.logical_key,
    binding_query.logical_key,
    None,
  )
  let scope = pick_override(request_query.scope, binding_query.scope, None)

  match job_id {
    Some(job_id) if artifact.job_id != job_id => return false
    _ => ()
  }
  match run_id {
    Some(run_id) if artifact.run_id != run_id => return false
    _ => ()
  }
  match artifact_type {
    Some(artifact_type) if artifact.artifact_type != artifact_type =>
      return false
    _ => ()
  }
  match logical_key {
    Some(logical_key) if artifact.logical_key != Some(logical_key) =>
      return false
    _ => ()
  }
  match scope {
    Some(scope) if !artifact.scope.contains(scope) => return false
    _ => ()
  }
  match status {
    Some(status) if artifact.status != status => false
    _ => true
  }
}

///|
fn snippet_for_content(content : String, terms : Array[String]) -> String {
  let lowered = content.to_lower()
  for term in terms {
    if lowered.find(term) is Some(index) {
      let start = if index > 48 { index - 48 } else { 0 }
      let end = if index + 160 < content.length() {
        index + 160
      } else {
        content.length()
      }
      return content[start:end].trim().to_string()
    }
  }
  if content.length() <= 180 {
    content.trim().to_string()
  } else {
    content[:180].trim().to_string()
  }
}

///|
fn score_artifact(
  artifact : ArtifactRecord,
  content : String,
  terms : Array[String],
) -> Int {
  let haystack = "\{artifact.metadata.stringify()} \{content}".to_lower()
  terms.fold(init=0, fn(score, term) {
    if haystack.contains(term) {
      score + 1
    } else {
      score
    }
  })
}

///|
pub async fn ChatService::retrieve(
  self : ChatService,
  question : String,
  query? : ArtifactQuery = ArtifactQuery::new(
    status=Some(ArtifactStatus::Active),
  ),
  max_hits? : Int = 5,
) -> Array[RetrievalHit] {
  self.retrieve_merged(question, Some(query), None, max_hits)
}

///|
async fn ChatService::retrieve_merged(
  self : ChatService,
  question : String,
  request_query : ArtifactQuery?,
  binding_query : ArtifactQuery?,
  max_hits : Int,
) -> Array[RetrievalHit] {
  let terms = tokenize_question(question)
  let hits : Array[RetrievalHit] = []
  for artifact in self.store.list_artifacts() {
    if !matches_merged_query(artifact, binding_query, request_query) {
      continue
    }
    let content = match self.artifacts.read_text(artifact.id) {
      Some(content) => content
      None => continue
    }
    let score = score_artifact(artifact, content, terms)
    if score <= 0 {
      continue
    }
    hits.push(RetrievalHit::{
      artifact_id: artifact.id,
      artifact_type: artifact.artifact_type,
      logical_key: artifact.logical_key,
      score,
      snippet: snippet_for_content(content, terms),
      path: artifact.path,
      scope: artifact.scope,
    })
  }
  hits.sort_by(fn(left, right) {
    if left.score == right.score {
      left.artifact_id.compare(right.artifact_id)
    } else {
      right.score.compare(left.score)
    }
  })
  let limit = if max_hits > 0 && max_hits < hits.length() {
    max_hits
  } else {
    hits.length()
  }
  hits[:limit].to_array()
}

///|
fn answer_from_hits(
  question : String,
  hits : Array[RetrievalHit],
  memory_hits : Array[MemorySearchHit],
) -> String {
  guard !(hits.is_empty() && memory_hits.is_empty()) else {
    return "No matching artifacts found for: \{question}"
  }
  let lines = [
    "Found \{hits.length()} relevant artifact(s) and \{memory_hits.length()} memory record(s) for: \{question}",
  ]
  for index in 0..<hits.length() {
    let hit = hits[index]
    let label = hit.logical_key.unwrap_or(hit.artifact_id)
    lines.push("[\{index + 1}] \{label}: \{hit.snippet}")
  }
  let base_index = hits.length()
  for index in 0..<memory_hits.length() {
    let hit = memory_hits[index]
    let label = hit.title.unwrap_or(hit.memory_id)
    lines.push("[\{base_index + index + 1}] memory \{label}: \{hit.snippet}")
  }
  lines.join("\n")
}

///|
pub async fn ChatService::ask(
  self : ChatService,
  params : JobAskParams,
) -> Result[ChatAnswer, String] {
  let binding = match params.binding_id {
    Some(binding_id) =>
      match self.store.get_chat_binding(binding_id) {
        Some(binding) => Some(binding)
        None => return Err("Unknown chat binding: \{binding_id}")
      }
    None => None
  }
  let hits = self.retrieve_merged(
    params.question,
    params.artifact_query,
    binding.map(fn(binding) { binding.artifact_query }),
    params.max_hits.unwrap_or(5),
  )
  let memory_scope = binding.bind(fn(binding) { binding.scope.get(0) })
  let memory_hits = self.memories.search(
    params.question,
    query=MemoryQuery::new(
      scope=memory_scope,
      status=Some(MemoryStatus::Active),
    ),
    max_hits=params.max_hits.unwrap_or(5),
  )
  let citations = hits.map(fn(hit) {
    ChatCitation::{
      artifact_id: hit.artifact_id,
      artifact_type: hit.artifact_type,
      logical_key: hit.logical_key,
      snippet: hit.snippet,
      path: hit.path,
      scope: hit.scope,
    }
  })
  Ok(ChatAnswer::{
    binding_id: binding.map(fn(binding) { binding.id }),
    question: params.question,
    answer: answer_from_hits(params.question, hits, memory_hits),
    citations,
    hits,
    memory_hits,
  })
}
