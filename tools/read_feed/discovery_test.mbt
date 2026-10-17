///|
test "HTML feed discovery reads mixed formats and usable provider metadata" {
  let result = discover_feeds(
    "<!doctype html><html><head><meta charset=utf-8><LINK REL='alternate stylesheet' TYPE='Application/RSS+XML; charset=utf-8' HREF='../feeds/main.xml?a=1&amp;b=2#section' TITLE='Research &#x1F52D;'><link rel=alternate type=application/atom+xml href=/atom><link rel=alternate type=application/feed+json href=//feeds.example.test/json><link rel=alternate type=text/html href=/translated></head><body><link rel=alternate type=application/rss+xml href=/not-in-head></body></html>",
    "https://example.test/articles/index.html",
    prefix="research",
  )
  inspect(result.providers.length(), content="3")
  inspect(result.duplicate_links, content="0")
  inspect(result.rejected_links, content="0")
  @json.json_inspect(result.providers[0], content={
    "name": "research-1",
    "title": "Research 🔭",
    "description": "Discovered feed candidate; content has not been fetched or verified",
    "kind": "feed",
    "endpoint": "https://example.test/feeds/main.xml?a=1&b=2",
    "capabilities": ["read_feed"],
    "metadata": {
      "import_format": "html-alternate",
      "page_url": "https://example.test/articles/index.html",
      "declared_type": "application/rss+xml; charset=utf-8",
      "read_feed": { "source": "provider://research-1" },
    },
  })
  assert_true(
    result.providers[1] is { "endpoint": "https://example.test/atom", .. },
  )
  assert_true(
    result.providers[2] is { "endpoint": "https://feeds.example.test/json", .. },
  )
}

///|
test "HTML first base applies globally and first resolved duplicate keeps its title" {
  let result = discover_feeds(
    "<link rel=alternate type=application/rss+xml href=../rss title=First><base href='https://cdn.example.test/news/'><base href='https://ignored.example.test/'><link rel=alternate type=application/atom+xml href='https://cdn.example.test/rss#new' title=Second><link rel=alternate type=application/feed+json href='?format=json&amp;lang=en'>",
    "https://example.test/page",
  )
  inspect(result.base_url, content="Some(https://cdn.example.test/news/)")
  inspect(result.duplicate_links, content="1")
  inspect(result.providers.length(), content="2")
  assert_true(
    result.providers[0]
    is { "endpoint": "https://cdn.example.test/rss", "title": "First", .. },
  )
  assert_true(
    result.providers[1]
    is { "endpoint": "https://cdn.example.test/news/?format=json&lang=en", .. },
  )
}

///|
test "HTML discovery ignores comment raw text and inert template candidates" {
  let fake = "<link rel=alternate type=application/rss+xml href=/fake>"
  let body = "<!DOCTYPE html [<!ENTITY ignored '\{fake}\{fake}'>]><head><!--\{fake}--><script>let s = '\{fake}'; </scripture>still raw \{fake}</script><style>/*\{fake}*/</style><title>\{fake}</title><noscript>\{fake}</noscript><template>\{fake}<template>\{fake}</template>\{fake}</template><link rel=alternate type=application/rss+xml href=/real></head>"
  let result = discover_feeds(body, "https://example.test/")
  inspect(result.providers.length(), content="1")
  assert_true(
    result.providers[0] is { "endpoint": "https://example.test/real", .. },
  )
}

///|
test "HTML relative base and empty first base retain page semantics" {
  let relative = discover_feeds(
    "<base href='../feeds/'><link rel=alternate type=application/rss+xml href=main.xml>",
    "https://example.test/news/page?old=yes",
  )
  inspect(relative.base_url, content="Some(https://example.test/feeds/)")
  assert_true(
    relative.providers[0]
    is { "endpoint": "https://example.test/feeds/main.xml", .. },
  )
  let empty = discover_feeds(
    "<base href=''><base href='https://ignored.test/'><link rel=alternate type=application/rss+xml href='?rss'>",
    "https://example.test/news/page?old=yes",
  )
  assert_true(
    empty.providers[0]
    is { "endpoint": "https://example.test/news/page?rss", .. },
  )
}

///|
test "HTML discovery preserves Unicode offsets and common entity semantics" {
  let result = discover_feeds(
    "<head><title>İ 🌙</title><link title='月&nbsp;&amp; &unknown;' rel='ALTERNATE\tother' type='application/rss+xml' href='/月🌙?a=1&b=2&#38;c=3' HREF='/ignored'></head>",
    "HTTPS://example.test/page#old",
  )
  inspect(result.page_url, content="https://example.test/page")
  assert_true(
    result.providers[0]
    is {
      "endpoint": "https://example.test/月🌙?a=1&b=2&c=3",
      "title": "月 & &unknown;",
      ..
    },
  )
}

///|
test "HTML discovery resolves relative forms without conflating query values" {
  for
    (reference, expected) in [
      ("feed.xml", "https://example.test/a/feed.xml"),
      ("./feed.xml", "https://example.test/a/feed.xml"),
      ("../../feed.xml", "https://example.test/feed.xml"),
      ("/x/../rss", "https://example.test/rss"),
      ("?feed=rss", "https://example.test/a/page?feed=rss"),
      ("//cdn.example.test/rss", "https://cdn.example.test/rss"),
      ("https://other.example.test", "https://other.example.test/"),
      ("../feeds/.", "https://example.test/feeds/"),
      ("../feeds/..", "https://example.test/"),
      ("/a//b", "https://example.test/a//b"),
      ("/feeds/%2e%2e/rss", "https://example.test/feeds/%2e%2e/rss"),
    ] {
    let result = discover_feeds(
      "<link rel=alternate type=application/rss+xml href='\{reference}'>",
      "https://example.test/a/page?old=yes",
    )
    assert_eq(result.providers.length(), 1)
    assert_true(
      result.providers[0] is { "endpoint": String(endpoint), .. } &&
      endpoint == expected,
    )
  }
}

///|
test "HTML discovery rejects unsupported links and invalid base stays visible" {
  let result = discover_feeds(
    "<base href='file:///tmp/'><link rel=alternate type=application/rss+xml href=relative><link rel=alternate type=application/atom+xml href='https://example.test/feed'><link rel=alternate type=application/rss+xml href='https://user:secret@example.test/rss'><link rel=alternate type=application/rss+xml href=javascript:alert(1)><link rel=alternate type=application/rss+xml><link rel=alternate type=application/rss+xml href='#section'><link rel=alternate type=application/rss+xml href='https://example.test/a&#10;b'>",
    "https://example.test/",
  )
  inspect(result.base_url, content="None")
  inspect(result.providers.length(), content="1")
  inspect(result.rejected_links, content="6")
  inspect(result.warnings.length(), content="7")
  assert_false(result.to_json().stringify().contains("secret"))
  assert_false(result.to_json().stringify().contains("file:///tmp"))
}

///|
test "HTML discovery bounded malformed and empty inputs" {
  let long_url = "https://example.test/" + "a".repeat(8192)
  assert_true(
    (Ok(discover_feeds("", long_url)) catch { error => Err(error) }) is Err(_),
  )
  let long_link = discover_feeds(
    "<link rel=alternate type=application/rss+xml href='\{long_url}'>",
    "https://example.test/",
  )
  inspect(long_link.rejected_links, content="1")
  let long_base = discover_feeds(
    "<base href='\{long_url}'><link rel=alternate type=application/rss+xml href=relative>",
    "https://example.test/",
  )
  inspect(long_base.base_url, content="None")
  inspect(long_base.rejected_links, content="1")
  inspect(
    discover_feeds(
      "<head><link rel=icon href=/icon></head>", "https://example.test",
    ).providers.length(),
    content="0",
  )
  for
    body in [
      "<head><!--",
      "<link rel='alternate",
      "<script>unclosed",
      "<link =bad>",
      "<link rel=alternate type=application/rss+xml href=/rss>".repeat(257),
      "x".repeat(4194305),
    ] {
    assert_true(
      (Ok(discover_feeds(body, "https://example.test/")) catch {
        error => Err(error)
      })
      is Err(_),
    )
  }
  for
    url in [
      "file:///tmp/page", "https://user:secret@example.test/", "https:///page", "https://example.test/a b",
      "https://example.test\\host/",
    ] {
    assert_true(
      (Ok(discover_feeds("", url)) catch { error => Err(error) }) is Err(_),
    )
  }
  for prefix in ["", "bad/name", "a".repeat(65)] {
    assert_true(
      (Ok(discover_feeds("", "https://example.test/", prefix~)) catch {
        error => Err(error)
      })
      is Err(_),
    )
  }
  let result = discover_feeds(
    "<link rel=alternate type=application/rss+xml href=/rss>".repeat(256),
    "https://example.test/",
  )
  inspect(result.duplicate_links, content="255")
}

///|
async test "HTML discovered registry reads an explicit local HTTP feed" {
  let router = @httpx.Router::new()
  let server = @httpx.Server::new("[::1]", 0)
  router.add_handler(Get, "/feed", (_, w) => {
    w.write_header(@status.Ok)
    w.write(
      "<rss version='2.0'><channel><title>Lab</title><item><guid>one</guid><title>New results</title><description>Saved page discovery works.</description></item></channel></rss>",
    )
  })
  @async.with_task_group(group => {
    group.spawn_bg(() => server.serve(router.handler()), no_wait=true)
    @fsx.with_temporary_directory("moonclaw-discovery-XXXXXX", async fn(dir) {
      let discovered = discover_feeds(
        "<head><link rel=alternate type=application/rss+xml href=/feed title=Lab></head>",
        "http://localhost:\{server.port()}/news/page",
        prefix="lab",
      )
      @fsx.make_directory(dir + "/.moonsuite")
      @fsx.write_to_file(
        dir + "/.moonsuite/resource-providers.json",
        discovered.to_json().stringify(),
      )
      let result = new(dir).call({
        "source": "provider://lab-1",
        "query": "results",
      })
      guard result is Ok(page) else {
        fail("Discovered provider could not be read: \{result}")
      }
      inspect(page.articles[0].title, content="New results")
      assert_true(page.to_markdown().contains("Saved page discovery works."))
    })
  })
}
