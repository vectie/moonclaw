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
