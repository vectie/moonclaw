///|
test "parse_duckduckgo_result includes search URL and per-item provenance" {
  let body =
    #|{
    #|  "AbstractText": "MoonBit is a language.",
    #|  "AbstractURL": "https://www.moonbitlang.com/",
    #|  "Heading": "MoonBit",
    #|  "Results": [
    #|    {
    #|      "Text": "MoonBit docs",
    #|      "FirstURL": "https://docs.moonbitlang.com/"
    #|    }
    #|  ]
    #|}
  let result = parse_duckduckgo_result(
    "moonbit", "https://duckduckgo.com/?q=moonbit", body, 5,
  )
  inspect(result.search_url, content="https://duckduckgo.com/?q=moonbit")
  inspect(result.results.length(), content="2")
  inspect(result.results[0].domain.unwrap_or(""), content="www.moonbitlang.com")
  inspect(result.results[0].rank.to_string(), content="1")
  inspect(
    result.results[1].domain.unwrap_or(""),
    content="docs.moonbitlang.com",
  )
  inspect(result.results[1].rank.to_string(), content="2")
}

///|
test "parse_bing_rss_result provides ranked fallback search results" {
  let body =
    #|<?xml version="1.0"?><rss><channel>
    #|<item><title>NASA &amp; Lunar Robots</title><link>https://www.nasa.gov/lunar-robots/</link><description>Surface mobility &amp; hazards.</description></item>
    #|<item><title>ESA Moon Work</title><link>https://www.esa.int/moon/work</link><description>Payload delivery.</description></item>
    #|</channel></rss>
  let result = parse_bing_rss_result(
    "lunar robots", "https://www.bing.com/search?q=lunar+robots", body, 5,
  )
  inspect(result.source, content="bing-rss")
  inspect(result.results.length(), content="2")
  inspect(result.results[0].title, content="NASA & Lunar Robots")
  inspect(result.results[0].domain.unwrap_or(""), content="www.nasa.gov")
  inspect(result.results[1].rank.to_string(), content="2")
}

///|
test "bing fallback honors site query before applying result limit" {
  let result = WebSearchResult::{
    query: "site:nasa.gov lunar robotics",
    search_url: "https://www.bing.com/search?q=site:nasa.gov+lunar+robotics",
    answer: None,
    results: [
      {
        title: "Noise",
        url: "https://example.com/lunar",
        snippet: "unrelated",
        source: "bing-rss",
        domain: Some("example.com"),
        rank: 1,
      },
      {
        title: "NASA Moon",
        url: "https://science.nasa.gov/moon/",
        snippet: "authoritative",
        source: "bing-rss",
        domain: Some("science.nasa.gov"),
        rank: 9,
      },
    ],
    source: "bing-rss",
  }
  let filtered = limit_bing_results_for_query(
    "site:nasa.gov lunar robotics", result, 1,
  )
  inspect(filtered.results.length(), content="1")
  inspect(filtered.results[0].title, content="NASA Moon")
  inspect(filtered.results[0].rank, content="1")
}
