///|
// Expected output captured from the accepted derive(Show) implementation.
test "public feed display preserves accepted Show text" {
  let out = StringBuilder()
  let article = FeedArticle::{
    id: "a\"b",
    title: "A\nB",
    date_published: Some("2026"),
    summary: "text",
    url: None,
  }
  let observation = FeedObservation::{
    label: "before",
    title: "feed",
    format: "json-feed",
    total_items: 1,
    next_url: Some("https://next"),
  }
  let change = FeedChange::{
    kind: "changed",
    id: "1",
    before: None,
    after: Some(article),
    changed_fields: ["title", "url"],
  }
  out.write_string("\{article}\n")
  out.write_string(
    "\{FeedPage::{source:"s",title:"t",articles:[article],offset:0,next_offset:Some(1),next_url:None,total_items:2,matched_items:1,format:"json-feed",query:"q"}}\n",
  )
  out.write_string("\{observation}\n")
  out.write_string("\{change}\n")
  out.write_string(
    "\{FeedComparison::{source:"s",before:observation,after:observation,newly_listed:1,changed:2,no_longer_listed:3,unchanged:4,changes:[change],total_changes:5,matched_changes:6,offset:0,next_offset:None,query:"q",kind:"all"}}\n",
  )
  out.write_string(
    "\{FeedCollection::{title:"feed",providers:[{"a":1}],duplicate_feeds:1,skipped_outlines:2,warnings:["warning"]}}\n",
  )
  out.write_string(
    "\{FeedDiscovery::{page_url:"https://page",base_url:Some("https://base"),providers:[{"a":1}],duplicate_links:1,rejected_links:2,warnings:["warning"]}}\n",
  )

  let expected =
    #|{id: a"b, title: A
    #|B, date_published: Some(2026), summary: text, url: None}
    #|{source: s, title: t, articles: [{id: a"b, title: A
    #|B, date_published: Some(2026), summary: text, url: None}], offset: 0, next_offset: Some(1), next_url: None, total_items: 2, matched_items: 1, format: json-feed, query: q}
    #|{label: before, title: feed, format: json-feed, total_items: 1, next_url: Some(https://next)}
    #|{kind: changed, id: 1, before: None, after: Some({id: a"b, title: A
    #|B, date_published: Some(2026), summary: text, url: None}), changed_fields: [title, url]}
    #|{source: s, before: {label: before, title: feed, format: json-feed, total_items: 1, next_url: Some(https://next)}, after: {label: before, title: feed, format: json-feed, total_items: 1, next_url: Some(https://next)}, newly_listed: 1, changed: 2, no_longer_listed: 3, unchanged: 4, changes: [{kind: changed, id: 1, before: None, after: Some({id: a"b, title: A
    #|B, date_published: Some(2026), summary: text, url: None}), changed_fields: [title, url]}], total_changes: 5, matched_changes: 6, offset: 0, next_offset: None, query: q, kind: all}
    #|{title: feed, providers: [Object({a: Number(1)})], duplicate_feeds: 1, skipped_outlines: 2, warnings: [warning]}
    #|{page_url: https://page, base_url: Some(https://base), providers: [Object({a: Number(1)})], duplicate_links: 1, rejected_links: 2, warnings: [warning]}
  assert_eq(out.to_string(), expected + "\n")
}

///|
test "feed JSON display preserves every legacy constructor" {
  let value = @json.parse("[null,true,false,1.0,\"a\\\"b\",{\"k\":\"v\"}]")
  assert_eq(
    feed_show_json(value),
    "Array([Null, True, False, Number(1), String(a\"b), Object({k: String(v)})])",
  )
}
