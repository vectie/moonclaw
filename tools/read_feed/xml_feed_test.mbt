///|
fn rss_fixture() -> String {
  (
    #|<?xml version="1.0"?><rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:atom="http://www.w3.org/2005/Atom"><channel>
    #|<title>Observatory &amp; Community &#x1f52d;</title><atom:link rel="next" href="archive.xml?page=2&amp;all=yes"/>
    #|<item><guid isPermaLink="false">telescope-1</guid><title>First telescope light</title><link>../news/first-light</link><pubDate>Thu, 08 Oct 2026 08:00:00 GMT</pubDate><description><![CDATA[<p>New <b>telescope</b> &amp; instruments.</p><script>ignore()</script>]]></description></item>
    #|<item><title>Moon calendar</title><link>/calendar</link><dc:date>2026-10-07</dc:date><content:encoded><![CDATA[<p>Moon phases &#128301;.</p>]]></content:encoded></item>
    #|<item><title>Telescope workshop</title><link>workshop</link><description>No prior experience needed.</description></item>
    #|</channel></rss>
  )
}

///|
fn atom_fixture() -> String {
  (
    #|<?xml version='1.0'?><a:feed xmlns:a='http://www.w3.org/2005/Atom' xmlns:other='urn:extension' xml:base='https://research.example.test/updates/'>
    #|<other:title>Not the feed title</other:title><a:title>Research notes</a:title><a:link rel='next' href='archive.atom?offset=3'/>
    #|<a:entry><a:id>urn:climate:1</a:id><a:title>Climate ocean data</a:title><a:published>2026-10-08</a:published><a:updated>2026-10-09</a:updated><a:link rel='self' href='entry.atom'/><a:link href='../papers/ocean?download=1&amp;view=web'/><a:summary type='html'>&lt;p&gt;New &lt;b&gt;climate&lt;/b&gt; data &amp;amp; notebooks.&lt;/p&gt;</a:summary></a:entry>
    #|<a:entry xml:base='../papers/'><a:id>urn:climate:2</a:id><a:title>City resilience</a:title><a:updated>2026-10-07</a:updated><a:link rel='alternate' href='city'/><a:content type='xhtml'><div xmlns='http://www.w3.org/1999/xhtml'><p>Climate map.</p><p>Open code.</p></div></a:content></a:entry>
    #|<a:entry><a:id>urn:quantum:1</a:id><a:title>Quantum sensor</a:title><a:summary>1 &lt; 2 and 3 &gt; 2.</a:summary></a:entry>
    #|</a:feed>
  )
}

///|
test "RSS readable articles filter before pages and preserve publisher archive" {
  let source = "https://observatory.example.test/feeds/latest.xml"
  let first = parse_feed(rss_fixture(), source, query=" TELESCOPE ", limit=1)
  inspect(first.title, content="Observatory & Community 🔭")
  inspect(first.format, content="rss")
  inspect(first.total_items, content="3")
  inspect(first.matched_items, content="2")
  inspect(first.query, content="TELESCOPE")
  inspect(first.articles[0].id, content="telescope-1")
  inspect(first.articles[0].summary, content="New telescope & instruments.")
  inspect(
    first.articles[0].url,
    content=(
      #|Some(https://observatory.example.test/news/first-light)
    ),
  )
  inspect(first.next_offset, content="Some(1)")
  inspect(first.next_url, content="None")
  let second = parse_feed(
    rss_fixture(),
    source,
    query="telescope",
    limit=1,
    offset=1,
  )
  inspect(second.articles[0].title, content="Telescope workshop")
  inspect(second.next_offset, content="None")
  inspect(
    second.next_url,
    content=(
      #|Some(https://observatory.example.test/feeds/archive.xml?page=2&all=yes)
    ),
  )
  let calendar = parse_feed(rss_fixture(), source, query="phases")
  inspect(calendar.articles[0].summary, content="Moon phases 🔭.")
  inspect(
    calendar.articles[0].date_published,
    content=(
      #|Some(2026-10-07)
    ),
  )
  inspect(
    calendar.articles[0].id,
    content="https://observatory.example.test/calendar",
  )
  let no_match = parse_feed(rss_fixture(), source, query="unmatched")
  inspect(no_match.matched_items, content="0")
  inspect(no_match.articles.length(), content="0")
  assert_true(no_match.next_url is Some(_))
}

///|
test "Atom namespace text content relative links and Markdown reading digest" {
  let page = parse_feed(atom_fixture(), "file://research.atom", query="climate")
  inspect(page.title, content="Research notes")
  inspect(page.format, content="atom")
  inspect(page.matched_items, content="2")
  inspect(
    page.articles[0].date_published,
    content=(
      #|Some(2026-10-08)
    ),
  )
  inspect(page.articles[0].summary, content="New climate data & notebooks.")
  inspect(
    page.articles[0].url,
    content=(
      #|Some(https://research.example.test/papers/ocean?download=1&view=web)
    ),
  )
  inspect(
    page.articles[1].date_published,
    content=(
      #|Some(2026-10-07)
    ),
  )
  inspect(page.articles[1].summary, content="Climate map. Open code.")
  inspect(
    page.articles[1].url,
    content=(
      #|Some(https://research.example.test/papers/city)
    ),
  )
  let plain = parse_feed(
    atom_fixture(),
    "file://research.atom",
    query="quantum",
  )
  inspect(plain.articles[0].summary, content="1 < 2 and 3 > 2.")
  let digest = page.to_markdown()
  assert_true(digest.has_prefix("# Research notes\n"))
  assert_true(
    digest.contains("Showing 2 of 2 matching articles (3 in this document)."),
  )
  assert_true(
    digest.contains(
      "[Read article](<https://research.example.test/papers/city>)",
    ),
  )
  assert_false(digest.contains("Quantum sensor"))
}

///|
test "XML feed failures are explicit and JSON filtering retains compatibility" {
  assert_true(
    (Ok(
      parse_feed(
        "<rss version='2.0'><channel><title>Bad</channel></rss>", "file://bad",
      ),
    ) catch {
      error => Err(error)
    })
    is Err(_),
  )
  assert_true(
    (Ok(
      parse_feed(
        "<!DOCTYPE rss SYSTEM 'file:///not-read'><rss version='2.0'/>", "file://bad",
      ),
    ) catch {
      error => Err(error)
    })
    is Err(_),
  )
  assert_true(
    (Ok(parse_feed("<html><title>Not a feed</title></html>", "file://bad")) catch {
      error => Err(error)
    })
    is Err(_),
  )
  assert_true(
    (Ok(
      parse_feed(
        "<feed xmlns='urn:not-atom'><title>Wrong namespace</title></feed>", "file://bad",
      ),
    ) catch {
      error => Err(error)
    })
    is Err(_),
  )
  let json = "{\"version\":\"https://jsonfeed.org/version/1.1\",\"title\":\"News\",\"items\":[{\"id\":\"one\",\"title\":\"Research\",\"content_text\":\"Moon science\"},{\"id\":\"two\",\"title\":\"Weather\"}]}"
  let page = parse_feed(json, "fixture", query="SCIENCE")
  inspect(page.format, content="json-feed")
  inspect(page.total_items, content="2")
  inspect(page.matched_items, content="1")
  inspect(page.articles[0].id, content="one")
  let bom = parse_feed("\u{FEFF}" + json, "fixture", query="science")
  inspect(bom.articles.length(), content="1")
}

///|
test "RSS permalink GUID and ordinary inline markup remain useful" {
  let body = "<rss version='2.0'><channel><title>Lab</title><item><title>MoonBit lab</title><guid>https://lab.example.test/post</guid><description><![CDATA[<p><b title='1 > 0'>Moon</b>Bit &amp; a result.</p>]]></description></item></channel></rss>"
  let page = parse_feed(body, "https://lab.example.test?feed=1")
  inspect(page.articles[0].url, content="Some(https://lab.example.test/post)")
  inspect(page.articles[0].summary, content="MoonBit & a result.")
  let fallback = parse_feed(
    "<rss version='2.0'><channel><title>Lab</title><item><title>Notes</title><description>A brief update.</description></item></channel></rss>",
    "file://notes.rss",
  )
  assert_true(fallback.articles[0].id.has_prefix("file://notes.rss#content-"))
  inspect(fallback.articles[0].url, content="None")
}

///|
async test "actual HTTP RSS filtering and registered Atom export journey" {
  let router = @httpx.Router::new()
  let server = @httpx.Server::new("[::1]", 0)
  router.add_handler(Get, "/feed.xml", (_, w) => {
    w.header().set("Content-Type", "application/rss+xml")
    w.write_header(@status.Ok)
    w.write(rss_fixture())
  })
  router.add_handler(Get, "/archive.xml", (_, w) => {
    w.header().set("Content-Type", "application/atom+xml")
    w.write_header(@status.Ok)
    w.write(atom_fixture())
  })
  @async.with_task_group(group => {
    group.spawn_bg(() => server.serve(router.handler()), no_wait=true)
    let tool = new(".")
    let result = tool.call({
      "source": "http://localhost:\{server.port()}/feed.xml",
      "query": "telescope",
      "limit": 1,
    })
    guard result is Ok(first) else { fail("RSS HTTP failed: \{result}") }
    inspect(first.matched_items, content="2")
    let result = tool.call({
      "source": first.source,
      "query": first.query,
      "limit": 1,
      "offset": first.next_offset.unwrap(),
    })
    guard result is Ok(second) else {
      fail("Filtered next page failed: \{result}")
    }
    inspect(second.articles[0].title, content="Telescope workshop")
    let result = tool.call({
      "source": second.next_url.unwrap(),
      "query": "climate",
    })
    guard result is Ok(archive) else {
      fail("Explicit Atom archive failed: \{result}")
    }
    inspect(archive.format, content="atom")
    inspect(archive.matched_items, content="2")
    assert_true(archive.to_markdown().contains("Climate ocean data"))
  })
  @fsx.with_temporary_directory("moonclaw-xml-feed-XXXXXX", async fn(dir) {
    @fsx.write_to_file(dir + "/research.atom", atom_fixture())
    @fsx.make_directory(dir + "/.moonsuite")
    @fsx.write_to_file(
      dir + "/.moonsuite/resource-providers.json",
      [
        {
          "name": "research",
          "kind": "atom",
          "endpoint": "file://research.atom",
        },
      ]
      .to_json()
      .stringify(),
    )
    let result = new(dir).call({
      "source": "provider://research",
      "query": "climate",
      "offset": 1,
    })
    guard result is Ok(page) else { fail("Registered Atom failed: \{result}") }
    inspect(page.articles[0].id, content="urn:climate:2")
    assert_false(
      new(dir, allow_files=false).call({ "source": "provider://research" })
      is Ok(_),
    )
    assert_false(
      new(dir).call({ "source": "provider://research", "query": 12 }) is Ok(_),
    )
  })
}
