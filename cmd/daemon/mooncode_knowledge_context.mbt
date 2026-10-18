///|
async fn mooncode_knowledge_retrieve(
  book_root : String,
  query : String,
) -> Json {
  let path = @pathx.join(book_root, "book/knowledge/library.json")
  let text = @book_runtime.read_resource(path).unwrap_or("[]")
  let parsed = @json.parse(text) catch { _ => Json::array([]) }
  let records = match parsed {
    Array(records) => records
    _ => []
  }
  let query = query.trim().to_owned().to_lower()
  let terms = query
    .split(" ")
    .filter(term => term != "")
    .map(term => term.to_owned())
    .collect()
  let config = mooncode_knowledge_embedding_config(book_root)
  let key = mooncode_embedding_key(config)
  let mut semantic_error = ""
  let mut query_vector : Array[Double] = []
  if query != "" &&
    records.any(record => {
      mooncode_json_string(record, "embedding_key", default="") == key
    }) {
    let result = mooncode_embed_knowledge(config, [query]) catch {
      _ => Err("Could not connect to the embedding provider")
    }
    match result {
      Ok(vectors) => query_vector = vectors[0]
      Err(message) => semantic_error = message
    }
  }
  let hits : Array[Json] = []
  for record in records {
    if query == "" || !mooncode_json_bool(record, "enabled", default=true) {
      continue
    }
    let path = mooncode_json_string(record, "path", default="")
    let title = mooncode_json_string(record, "title", default=path)
    for chunk in mooncode_json_array_items(record, "chunks") {
      let content = mooncode_json_string(chunk, "text", default="")
      let lowered = content.to_lower()
      let mut score = if lowered.contains(query) { 8 } else { 0 }
      for term in terms {
        if lowered.contains(term) {
          score += 2
        }
        if title.to_lower().contains(term) {
          score += 1
        }
      }
      let mut similarity = 0.0
      if !query_vector.is_empty() &&
        mooncode_json_string(record, "embedding_key", default="") == key {
        let vector = mooncode_embedding_vector(
          mooncode_journal_json_field(chunk, "embedding").unwrap_or(
            Json::null(),
          ),
        ).unwrap_or([])
        similarity = mooncode_embedding_similarity(query_vector, vector)
      }
      if score == 0 && similarity <= 0.2 {
        continue
      }
      let start = mooncode_json_int(chunk, "start_line", default=1)
      let end = mooncode_json_int(chunk, "end_line", default=start)
      hits.push({
        "path": path,
        "title": title,
        "text": content,
        "score": if query_vector.is_empty() {
          score.to_double()
        } else {
          0.45 * score.to_double() / (score.to_double() + 8.0) +
          0.55 * similarity
        },
        "source_id": mooncode_json_string(record, "id", default=""),
        "start_line": start,
        "end_line": end,
        "similarity": similarity,
        "citation": "[" + title + ", extracted lines \{start}–\{end}]",
      })
    }
  }
  hits.sort_by((a, b) => {
    mooncode_knowledge_result_score(b).compare(
      mooncode_knowledge_result_score(a),
    )
  })
  let hits = if hits.length() > 12 { hits[:12].to_owned() } else { hits }
  {
    "ok": true,
    "retrieval": if query_vector.is_empty() {
      "ranked-text"
    } else {
      "hybrid"
    },
    "semantic_error": semantic_error,
    "hits": Json::array(hits),
  }
}

///|
fn mooncode_knowledge_result_score(value : Json) -> Double {
  match mooncode_journal_json_field(value, "score") {
    Some(Number(score, ..)) => score
    _ => 0.0
  }
}
