///|
fn fixture() -> String {
  (
    #|{"version":"https://jsonfeed.org/version/1.1","title":"Lunar Observatory","next_url":"https://example.test/feed?page=2","items":[{"id":"1","title":"New telescope","date_published":"2026-10-08T08:00:00Z","summary":"The new telescope is ready.","url":"https://example.test/telescope"},{"id":"2","title":"Night sky","content_text":"A guide to October skies.","external_url":"https://example.test/sky"}]}
  )
}

///|
test "parse titles dates summaries links and local pagination" {
  let first = parse_feed(fixture(), "fixture", limit=1)
  assert_eq(first.title, "Lunar Observatory")
  assert_eq(first.articles[0].date_published, Some("2026-10-08T08:00:00Z"))
  assert_eq(first.articles[0].summary, "The new telescope is ready.")
  assert_eq(first.next_offset, Some(1))
  assert_eq(first.next_url, None)
  let second = parse_feed(fixture(), "fixture", limit=1, offset=1)
  assert_eq(second.articles[0].summary, "A guide to October skies.")
  assert_eq(second.articles[0].url, Some("https://example.test/sky"))
  assert_eq(second.next_offset, None)
  assert_eq(second.next_url, Some("https://example.test/feed?page=2"))
  assert_true((try? parse_feed("{}", "fixture")) is Err(_))
  assert_true((try? parse_feed(fixture(), "fixture", limit=0)) is Err(_))
}

///|
async test "actual HTTP tool and registered offline source journey" {
  let router = @httpx.Router::new()
  let server = @httpx.Server::new("[::1]", 0)
  router.add_handler(Get, "/feed.json", (_, w) => {
    w.header().set("Content-Type", "application/feed+json")
    w.write_header(@status.Ok)
    w.write(
      fixture().replace(
        old="https://example.test/feed?page=2",
        new="http://localhost:\{server.port()}/next.json",
      ),
    )
  })
  router.add_handler(Get, "/next.json", (_, w) => {
    w.write_header(@status.Ok)
    w.write(
      "{\"version\":\"https://jsonfeed.org/version/1\",\"title\":\"Archive\",\"items\":[]}",
    )
  })
  @async.with_task_group(group => {
    group.spawn_bg(() => server.serve(router.handler()), no_wait=true)
    let result = new(".").call({
      "source": "http://localhost:\{server.port()}/feed.json",
      "limit": 1,
    })
    guard result is Ok(page) else { fail("HTTP tool failed: \{result}") }
    assert_eq(page.articles[0].title, "New telescope")
    assert_eq(page.next_offset, Some(1))
    let second = new(".").call({ "source": page.source, "offset": 1 })
    guard second is Ok(second) else { fail("Second local page failed") }
    assert_eq(second.articles[0].title, "Night sky")
    let next = new(".").call({ "source": second.next_url.unwrap() })
    guard next is Ok(next) else { fail("Explicit next URL failed") }
    assert_eq(next.title, "Archive")
    assert_eq(next.articles.length(), 0)
    assert_eq(next.next_url, None)
    assert_false(
      new(".").call({ "source": "http://localhost:\{server.port()}/missing" })
      is Ok(_),
    )
  })
  @fsx.with_temporary_directory("moonclaw-feed-XXXXXX", async fn(dir) {
    @fsx.write_to_file(dir + "/feed.json", fixture())
    @fsx.make_directory(dir + "/.moonsuite")
    @fsx.write_to_file(
      dir + "/.moonsuite/resource-providers.json",
      [
        {
          "name": "observatory",
          "kind": "json-feed",
          "endpoint": "file://feed.json",
        },
      ]
      .to_json()
      .stringify(),
    )
    let result = new(dir).call({
      "source": "provider://observatory",
      "offset": 1,
    })
    guard result is Ok(page) else {
      fail("Registered file tool failed: \{result}")
    }
    assert_eq(page.articles[0].title, "Night sky")
    assert_eq(page.next_offset, None)
    let metadata = @read_resource.new(dir).call({
      "uri": "provider://observatory",
    })
    guard metadata is Ok(metadata) else {
      fail("Provider metadata reading failed")
    }
    assert_true(metadata.text.contains("Endpoint: file://feed.json"))
    assert_false(new(dir).call({ "source": "file://missing.json" }) is Ok(_))
    assert_false(
      new(dir, allow_files=false).call({ "source": "provider://observatory" })
      is Ok(_),
    )
    assert_false(
      new(dir).call({ "source": "file://feed.json", "limit": 1.5 }) is Ok(_),
    )
  })
}
