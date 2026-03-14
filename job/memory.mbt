///|
pub struct MemoryService {
  store : SystemStore
}

///|
pub fn MemoryService::new(store~ : SystemStore) -> MemoryService {
  MemoryService::{ store, }
}

///|
fn normalize_memory_term(term : String) -> String {
  term.trim().to_string().to_lower()
}

///|
fn tokenize_memory_query(question : String) -> Array[String] {
  question
  .split(" ")
  .map(fn(term) { normalize_memory_term(term.to_string()) })
  .filter(fn(term) { !term.is_blank() && term.length() > 1 })
  .collect()
}

///|
fn memory_matches_query(memory : MemoryRecord, query : MemoryQuery) -> Bool {
  match query.kind {
    Some(kind) if memory.kind != kind => return false
    _ => ()
  }
  match query.tag {
    Some(tag) if !memory.tags.contains(tag) => return false
    _ => ()
  }
  match query.scope {
    Some(scope) if !memory.scope.contains(scope) => return false
    _ => ()
  }
  match query.workspace {
    Some(workspace) if memory.workspace != Some(workspace) => return false
    _ => ()
  }
  match query.agent_id {
    Some(agent_id) if memory.agent_id != Some(agent_id) => return false
    _ => ()
  }
  match query.channel_id {
    Some(channel_id) if memory.channel_id != Some(channel_id) => return false
    _ => ()
  }
  match query.account_id {
    Some(account_id) if memory.account_id != Some(account_id) => return false
    _ => ()
  }
  match query.recipient {
    Some(recipient) if memory.recipient != Some(recipient) => return false
    _ => ()
  }
  match query.thread_id {
    Some(thread_id) if memory.thread_id != Some(thread_id) => return false
    _ => ()
  }
  match query.source_artifact_id {
    Some(source_artifact_id) =>
      if memory.source_artifact_id != Some(source_artifact_id) {
        return false
      }
    _ => ()
  }
  match query.status {
    Some(status) if memory.status != status => false
    _ => true
  }
}

///|
fn memory_snippet(content : String, terms : Array[String]) -> String {
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
fn memory_score(memory : MemoryRecord, terms : Array[String]) -> Int {
  let title = memory.title.unwrap_or("")
  let tags = memory.tags.join(" ")
  let haystack = "\{title} \{memory.content} \{tags} \{memory.metadata.stringify()}".to_lower()
  terms.fold(init=0, fn(score, term) {
    if haystack.contains(term) {
      score + 1
    } else {
      score
    }
  })
}

///|
pub async fn MemoryService::remember(
  self : MemoryService,
  request : MemoryWriteRequest,
  id : String,
  now_ms : Int,
) -> MemoryRecord {
  let memory = MemoryRecord::{
    id,
    kind: request.kind,
    title: request.title,
    content: request.content,
    metadata: request.metadata,
    tags: request.tags,
    scope: request.scope,
    workspace: request.workspace,
    agent_id: request.agent_id,
    channel_id: request.channel_id,
    account_id: request.account_id,
    recipient: request.recipient,
    thread_id: request.thread_id,
    source_artifact_id: request.source_artifact_id,
    status: MemoryStatus::Active,
    created_at: now_ms,
    updated_at: now_ms,
    archived_at: None,
  }
  self.store.save_memory(memory)
  memory
}

///|
pub async fn MemoryService::archive(
  self : MemoryService,
  id : String,
  now_ms : Int,
) -> Bool {
  match self.store.get_memory(id) {
    Some(memory) => {
      self.store.save_memory(MemoryRecord::{
        ..memory,
        status: MemoryStatus::Archived,
        updated_at: now_ms,
        archived_at: Some(now_ms),
      })
      true
    }
    None => false
  }
}

///|
pub fn MemoryService::get(self : MemoryService, id : String) -> MemoryRecord? {
  self.store.get_memory(id)
}

///|
pub fn MemoryService::list(
  self : MemoryService,
  query? : MemoryQuery = MemoryQuery::new(status=Some(MemoryStatus::Active)),
) -> Array[MemoryRecord] {
  self.store
  .list_memories()
  .filter(fn(memory) { memory_matches_query(memory, query) })
}

///|
pub fn MemoryService::search(
  self : MemoryService,
  question : String,
  query? : MemoryQuery = MemoryQuery::new(status=Some(MemoryStatus::Active)),
  max_hits? : Int = 5,
) -> Array[MemorySearchHit] {
  let terms = tokenize_memory_query(question)
  let hits : Array[MemorySearchHit] = []
  for memory in self.list(query~) {
    let score = memory_score(memory, terms)
    if score <= 0 {
      continue
    }
    hits.push(MemorySearchHit::{
      memory_id: memory.id,
      kind: memory.kind,
      title: memory.title,
      score,
      snippet: memory_snippet(memory.content, terms),
      tags: memory.tags,
      scope: memory.scope,
      workspace: memory.workspace,
      channel_id: memory.channel_id,
      account_id: memory.account_id,
      recipient: memory.recipient,
      thread_id: memory.thread_id,
    })
  }
  hits.sort_by(fn(left, right) {
    if left.score == right.score {
      left.memory_id.compare(right.memory_id)
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
pub fn render_memory_hits_prompt(
  hits : Array[MemorySearchHit],
  header? : String = "Relevant long-term memory",
) -> String {
  if hits.is_empty() {
    return ""
  }
  let lines = [header + ":"]
  for hit in hits {
    let label = hit.title.unwrap_or(hit.kind)
    let tag_text = hit.tags.join(",")
    let scope_text = hit.scope.join("/")
    let tags = if hit.tags.is_empty() { "" } else { " tags=\{tag_text}" }
    let scope = if hit.scope.is_empty() { "" } else { " scope=\{scope_text}" }
    lines.push("- [\{hit.memory_id}] \{label}\{tags}\{scope}")
    lines.push("  \{hit.snippet}")
  }
  lines.join("\n")
}

///|
pub fn render_memory_records_prompt(
  records : Array[MemoryRecord],
  header? : String = "Relevant long-term memory",
) -> String {
  if records.is_empty() {
    return ""
  }
  let hits = records.map(fn(record) {
    MemorySearchHit::{
      memory_id: record.id,
      kind: record.kind,
      title: record.title,
      score: 0,
      snippet: memory_snippet(record.content, []),
      tags: record.tags,
      scope: record.scope,
      workspace: record.workspace,
      channel_id: record.channel_id,
      account_id: record.account_id,
      recipient: record.recipient,
      thread_id: record.thread_id,
    }
  })
  render_memory_hits_prompt(hits, header~)
}
