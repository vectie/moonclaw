///|
test "embedding cosine similarity handles orthogonal and invalid dimensions" {
  assert_eq(mooncode_embedding_similarity([1.0, 0.0], [1.0, 0.0]), 1.0)
  assert_eq(mooncode_embedding_similarity([1.0, 0.0], [0.0, 1.0]), 0.0)
  assert_eq(mooncode_embedding_similarity([1.0], [1.0, 0.0]), 0.0)
  assert_eq(mooncode_embedding_similarity([0.0, 0.0], [1.0, 0.0]), 0.0)
}

///|
async test "configured embeddings preserve batch order and retrieve a paraphrased source" {
  let server = @httpx.Server::new("[::1]", 0)
  defer server.close()
  let router = @httpx.Router::new()
  router.add_handler(Post, "/embeddings", (r, w) => {
    assert_eq(r.headers.get("authorization"), Some("Bearer fixture-token"))
    let request : Json = @httpx.JsonRequestReader::new(r).read()
    assert_eq(
      mooncode_json_string(request, "model", default=""),
      "fixture-embed",
    )
    let input = mooncode_json_array_items(request, "input")
    let result : Json = if input.length() == 2 {
      {
        "data": [
          { "index": 1, "embedding": [0.0, 1.0] },
          { "index": 0, "embedding": [1.0, 0.0] },
        ],
      }
    } else {
      { "data": [{ "index": 0, "embedding": [1.0, 0.0] }] }
    }
    w.header().set("Content-Type", "application/json")
    w.write_header(200)
    w.write(result.stringify())
  })
  @fsx.with_temporary_directory("mooncode-embedding-XXXXXX", root => {
    let root = @fs.realpath(root)
    let config : Json = {
      "url": "http://localhost:\{server.port()}/embeddings",
      "model": "fixture-embed",
      "token": "fixture-token",
    }
    let config_path = @moonsuite.product_artifact_for_workspace_root(
      root, "moonclaw", "knowledge-embeddings.json",
    )
    @fsx.make_directory(
      @pathx.dirname(config_path),
      recursive=true,
      exists_ok=true,
    )
    @fsx.write_to_file(config_path, config.stringify())
    let library_path = @pathx.join(root, "book/knowledge/library.json")
    @fsx.make_directory(
      @pathx.dirname(library_path),
      recursive=true,
      exists_ok=true,
    )
    let records : Json = [
      {
        "id": "vehicles",
        "path": "cars.md",
        "title": "Cars",
        "enabled": true,
        "embedding_key": mooncode_embedding_key(config),
        "chunks": [
          {
            "start_line": 1,
            "end_line": 1,
            "text": "Automobiles transport passengers.",
            "embedding": [1.0, 0.0],
          },
        ],
      },
      {
        "id": "plants",
        "path": "plants.md",
        "title": "Plants",
        "enabled": true,
        "embedding_key": mooncode_embedding_key(config),
        "chunks": [
          {
            "start_line": 1,
            "end_line": 1,
            "text": "Trees need sunlight.",
            "embedding": [0.0, 1.0],
          },
        ],
      },
    ]
    @fsx.write_to_file(library_path, records.stringify())
    @async.with_task_group(group => {
      group.spawn_bg(() => server.serve(router.handler()), no_wait=true)
      let vectors = mooncode_embed_knowledge(config, ["Cars", "Plants"]).unwrap()
      assert_eq(vectors[0][0], 1.0)
      assert_eq(vectors[1][1], 1.0)
      let result = mooncode_knowledge_retrieve(root, "vehicle")
      assert_eq(mooncode_json_string(result, "retrieval", default=""), "hybrid")
      let hits = mooncode_json_array_items(result, "hits")
      assert_eq(hits.length(), 1)
      assert_eq(
        mooncode_json_string(hits[0], "source_id", default=""),
        "vehicles",
      )
      assert_true(
        mooncode_json_string(hits[0], "citation", default="").contains("Cars"),
      )
      assert_false(result.stringify().contains("fixture-token"))
    })
  })
}
