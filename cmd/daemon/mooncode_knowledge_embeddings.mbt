///|
fn mooncode_knowledge_embedding_config(book_root : String) -> Json raise {
  let path = @moonsuite.product_artifact_for_workspace_root(
    book_root, "moonclaw", "knowledge-embeddings.json",
  )
  let text = @book_runtime.read_resource(path).unwrap_or("{}")
  @json.parse(text) catch {
    _ => {}
  }
}

///|
fn mooncode_embedding_key(config : Json) -> String {
  mooncode_json_string(config, "url", default="") +
  "|" +
  mooncode_json_string(config, "model", default="")
}

///|
fn mooncode_embedding_vector(value : Json) -> Array[Double]? {
  guard value is Array(values) else { return None }
  let vector : Array[Double] = []
  for value in values {
    guard value is Number(number, ..) else { return None }
    if number.is_nan() || number.is_inf() {
      return None
    }
    vector.push(number)
  }
  if vector.is_empty() {
    None
  } else {
    Some(vector)
  }
}

///|
fn mooncode_embedding_similarity(
  left : Array[Double],
  right : Array[Double],
) -> Double {
  if left.length() != right.length() || left.is_empty() {
    return 0.0
  }
  let mut dot = 0.0
  let mut left_norm = 0.0
  let mut right_norm = 0.0
  for index in 0..<left.length() {
    dot += left[index] * right[index]
    left_norm += left[index] * left[index]
    right_norm += right[index] * right[index]
  }
  if left_norm == 0.0 || right_norm == 0.0 {
    0.0
  } else {
    dot / (left_norm.sqrt() * right_norm.sqrt())
  }
}

///|
async fn mooncode_embed_knowledge(
  config : Json,
  texts : Array[String],
) -> Result[Array[Array[Double]], String] {
  let url = mooncode_json_string(config, "url", default="")
  let model = mooncode_json_string(config, "model", default="")
  if url == "" || model == "" {
    return Err("No embedding provider is configured")
  }
  let headers : Map[String, String] = { "content-type": "application/json" }
  let token = mooncode_json_string(config, "token", default="")
  if token != "" {
    headers["authorization"] = "Bearer " + token
  }
  let request : Json = {
    "model": model,
    "input": texts,
    "encoding_format": "float",
  }
  let (response, body) = @http.post(url, request.stringify(), headers~)
  if response.code != 200 {
    return Err("Embedding provider returned HTTP \{response.code}")
  }
  let parsed = @json.parse(body.text()) catch {
    _ => return Err("Embedding provider returned unreadable JSON")
  }
  let data = mooncode_json_array_items(parsed, "data")
  if data.length() != texts.length() {
    return Err("Embedding provider returned an incomplete batch")
  }
  let ordered : Map[Int32, Array[Double]] = Map([])
  let mut dimensions = 0
  for item in data {
    let index = mooncode_json_int(item, "index", default=-1)
    let value = mooncode_journal_json_field(item, "embedding").unwrap_or(
      Json::null(),
    )
    let vector = match mooncode_embedding_vector(value) {
      Some(vector) => vector
      None => return Err("Embedding provider returned an invalid vector")
    }
    if index < 0 ||
      index >= texts.length() ||
      ordered.contains(index) ||
      (dimensions != 0 && dimensions != vector.length()) {
      return Err("Embedding provider returned inconsistent vectors")
    }
    dimensions = vector.length()
    ordered[index] = vector
  }
  let vectors : Array[Array[Double]] = []
  for index in 0..<texts.length() {
    vectors.push(ordered[index])
  }
  Ok(vectors)
}

///|
async fn Daemon::mooncode_knowledge_service(
  self : Daemon,
  config : @moondesk_sandbox_config.Config,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  self.with_mooncode_integration_request(config, r, (payload, root) => {
    let result : Json = if mooncode_json_string(payload, "action", default="") ==
      "embed" {
      let config = mooncode_knowledge_embedding_config(root)
      let texts = mooncode_json_array_items(payload, "texts").map(value => {
        match value {
          String(text) => text
          _ => ""
        }
      })
      let embedded = mooncode_embed_knowledge(config, texts) catch {
        _ => Err("Could not connect to the embedding provider")
      }
      match embedded {
        Ok(vectors) =>
          {
            "ok": true,
            "embedding_key": mooncode_embedding_key(config),
            "vectors": Json(vectors),
          }
        Err(message) => { "ok": false, "message": message }
      }
    } else {
      mooncode_knowledge_retrieve(
        root,
        mooncode_json_string(payload, "query", default=""),
      )
    }
    w.header().set("Content-Type", "application/json")
    w.write_header(200)
    w.write(result.stringify())
  }) catch {
    HttpError(..) as error => raise error
    _ =>
      raise json_error(403, "Forbidden", {
        "error": { "message": "Book knowledge resource is unavailable" },
      })
  }
}
