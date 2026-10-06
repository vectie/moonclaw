///|
fn transport_fixture_completion(content : String) -> ChatCompletion raise {
  @json.from_json({
    "id": "hermetic-serialized-transport",
    "model": "selected-book-fixture",
    "choices": [
      {
        "index": 0,
        "message": { "role": "assistant", "content": content },
        "finish_reason": "stop",
      },
    ],
  })
}

///|
async test "serialized transport observes final MoonGate route body and stream override" {
  let model = @model.new(
    api_key="",
    base_url="https://request-boundary.invalid/openclaw/v1",
    name="selected-book-fixture",
    safe_zone_tokens=16000,
  )
  let mut calls = 0
  let deltas : Array[String] = []
  let response = chat_with_text_deltas(
    model~,
    chat_completion(
      model=model.model_name,
      messages=[user_message(content="exact learned 尾部 tail")],
      stream=false,
    ),
    extra_body={ "fixture_extra": "merged before serialization" },
    on_text_delta=delta => deltas.push(delta),
    transport=(request, on_delta) => {
      calls += 1
      assert_eq(
        request.url,
        "https://request-boundary.invalid/openclaw/v1/chat/completions",
      )
      assert_false(request.headers.contains("Authorization"))
      assert_eq(request.headers["Content-Type"], "application/json")
      assert_true(request.stream)
      let body = @json.parse(request.body)
      guard body
        is {
          "model": String("selected-book-fixture"),
          "messages": [
            {
              "role": String("user"),
              "content": String("exact learned 尾部 tail"),
              ..
            },
          ],
          "stream": True,
          "fixture_extra": String("merged before serialization"),
          ..
        } else {
        fail("Final serialized provider request does not match")
      }
      on_delta("observed complete tail")
      transport_fixture_completion("observed complete tail")
    },
  )
  assert_eq(calls, 1)
  json_inspect(deltas, content=["observed complete tail"])
  assert_eq(response.choices[0].message.content, Some("observed complete tail"))
}

///|
async test "serialized transport retains direct route and caller stream semantics" {
  let model = @model.new(
    api_key="",
    base_url="https://direct.invalid/v1",
    name="native-fixture",
    safe_zone_tokens=16000,
  )
  let _ = chat(
    model~,
    chat_completion(model=model.model_name, messages=[], stream=false),
    transport=(request, _) => {
      assert_eq(request.url, "https://direct.invalid/v1/chat/completions")
      assert_false(request.stream)
      assert_eq(request.headers["Authorization"], "Bearer ")
      guard @json.parse(request.body) is { "stream": False, .. } else {
        fail("Expected unmodified direct stream setting")
      }
      transport_fixture_completion("direct serialized")
    },
  )
}

///|
async test "serialized transport remains inside the existing request timeout" {
  let model = @model.new(
    api_key="",
    base_url="https://request-boundary.invalid/openclaw/v1",
    name="native-fixture",
    safe_zone_tokens=16000,
  )
  let mut calls = 0
  let mut timed_out = false
  try {
    let _ = chat(
      model~,
      chat_completion(model=model.model_name, messages=[]),
      timeout_ms=Some(10),
      transport=(_, _) => {
        calls += 1
        @async.sleep(1000)
        transport_fixture_completion("unreachable")
      },
    )
  } catch {
    HttpError(code=408, ..) => timed_out = true
    error => raise error
  }
  assert_true(timed_out)
  assert_eq(calls, 1)
}

///|
async test "explicit serialized transport never falls through to another provider adapter" {
  let model = @model.new(
    api_key="",
    base_url="https://unused-provider.invalid",
    name="native-fixture",
    safe_zone_tokens=16000,
    model_type=SaaS(Anthropic),
  )
  let mut calls = 0
  let mut rejected = false
  try {
    let _ = chat(model~, chat_completion(model=model.model_name, messages=[]), transport=(
      _,
      _,
    ) => {
      calls += 1
      transport_fixture_completion("unreachable")
    })
  } catch {
    _ => rejected = true
  }
  assert_true(rejected)
  assert_eq(calls, 0)
}
