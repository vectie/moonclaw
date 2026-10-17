///|
test "nested OPML collection becomes a deduplicated usable registry" {
  let collection = parse_opml(
    "<?xml version='1.0'?><opml version='2.0'><head><title>Research &amp; news</title></head><body><outline text='Science'><outline text='Space'><outline text='Old title' title='Observatory 🔭' xmlUrl='https://example.test/rss?a=1&amp;b=2'/></outline><outline text='Duplicate' xmlUrl='https://example.test/rss?a=1&amp;b=2'/><outline text='Notes' type='link' url='https://example.test'/><outline text='Unsafe' xmlUrl='file:///private'/><outline xmlUrl='https://example.test/atom'/></outline></body></opml>",
    prefix="research",
  )
  inspect(collection.title, content="Research & news")
  inspect(collection.duplicate_feeds, content="1")
  inspect(collection.skipped_outlines, content="2")
  inspect(collection.providers.length(), content="2")
  @json.json_inspect(collection.providers[0], content={
    "name": "research-1",
    "title": "Observatory 🔭",
    "description": "",
    "kind": "feed",
    "endpoint": "https://example.test/rss?a=1&b=2",
    "capabilities": ["read_feed"],
    "metadata": {
      "import_format": "opml",
      "folders": ["Science", "Space"],
      "read_feed": { "source": "provider://research-1" },
    },
  })
  inspect(collection.warnings.length(), content="1")
  for version in ["1.0", "1.1", "2.0"] {
    let empty = parse_opml("\u{FEFF}<opml version='\{version}'><body/></opml>")
    assert_eq(empty.providers.length(), 0)
  }
}

///|
test "OPML refuses malformed input and reports unsupported subscriptions" {
  for
    body in [
      "<rss version='2.0'/>", "<opml version='3.0'><body/></opml>", "<opml version='2.0'/>",
      "<opml version='2.0'><body></opml>", "<!DOCTYPE opml SYSTEM 'file:///not-read'><opml version='2.0'><body/></opml>",
      "<opml version='2.0'><body><outline xmlUrl='&custom;'/></body></opml>",
    ] {
    assert_true((Ok(parse_opml(body)) catch { error => Err(error) }) is Err(_))
  }
  let body = "<opml version='2.0'><body/></opml>"
  assert_true(
    (Ok(parse_opml(body, prefix="bad/name")) catch { error => Err(error) })
    is Err(_),
  )
  assert_true(
    (Ok(parse_opml(body, prefix="")) catch { error => Err(error) }) is Err(_),
  )
  for
    url in [
      "file:///feed", "javascript:alert(1)", "relative.xml", "https:///feed", "http://",
      "https://example.test/a b", "https://user:secret@example.test/rss",
    ] {
    let collection = parse_opml(
      "<opml version='2.0'><body><outline xmlUrl='\{url}'/></body></opml>",
    )
    assert_eq(collection.providers.length(), 0)
    assert_eq(collection.skipped_outlines, 1)
    assert_eq(collection.warnings.length(), 1)
  }
}

///|
async test "import OPML then read registered HTTP feed and export digest" {
  let router = @httpx.Router::new()
  let server = @httpx.Server::new("[::1]", 0)
  router.add_handler(Get, "/rss", (_, w) => {
    w.write_header(@status.Ok)
    w.write(
      "<rss version='2.0'><channel><title>Observatory</title><item><guid>telescope-1</guid><title>New telescope</title><description>First light results.</description><link>https://example.test/telescope</link></item></channel></rss>",
    )
  })
  @async.with_task_group(group => {
    group.spawn_bg(() => server.serve(router.handler()), no_wait=true)
    @fsx.with_temporary_directory("moonclaw-opml-XXXXXX", async fn(dir) {
      let collection = parse_opml(
        "<opml version='2.0'><body><outline text='Research'><outline text='Observatory' xmlUrl='http://localhost:\{server.port()}/rss'/></outline></body></opml>",
      )
      @fsx.make_directory(dir + "/.moonsuite")
      @fsx.write_to_file(
        dir + "/.moonsuite/resource-providers.json",
        collection.to_json().stringify(),
      )
      let result = new(dir).call({
        "source": "provider://opml-1",
        "query": "telescope",
      })
      guard result is Ok(page) else {
        fail("Imported feed read failed: \{result}")
      }
      inspect(page.articles[0].title, content="New telescope")
      assert_true(page.to_markdown().contains("First light results."))
      let resource = @read_resource.new(dir).call({ "uri": "provider://opml-1" })
      guard resource is Ok(resource) else {
        fail("Imported metadata unavailable")
      }
      assert_true(resource.text.contains("Observatory"))
    })
  })
}
