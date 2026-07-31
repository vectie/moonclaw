///|
#warnings("-alert_xss_vulnerable")
fn operator_icon(name : String, size? : Int = 20) -> Html {
  let body = match name {
    "home" =>
      "<path d=\"M3 11l9-8 9 8\"/><path d=\"M5 10v10h14V10M9 20v-6h6v6\"/>"
    "work" => "<path d=\"M4 5h16v12H8l-4 4z\"/><path d=\"M8 9h8M8 13h5\"/>"
    "runs" => "<path d=\"M5 4h14v16H5z\"/><path d=\"M9 9l6 3-6 3z\"/>"
    "remote" =>
      "<rect x=\"3\" y=\"4\" width=\"18\" height=\"12\" rx=\"2\"/><path d=\"M8 20h8M12 16v4M8 9h.01M12 9h.01M16 9h.01\"/>"
    "retry" => "<path d=\"M20 6v6h-6\"/><path d=\"M19 12a7 7 0 10-2 5\"/>"
    "arrow" => "<path d=\"M5 12h14M13 6l6 6-6 6\"/>"
    "ask" =>
      "<circle cx=\"12\" cy=\"12\" r=\"9\"/><path d=\"M9.8 9a2.4 2.4 0 014.6 1c0 2-2.4 2.1-2.4 4M12 18h.01\"/>"
    "plan" => "<path d=\"M5 4h14v16H5zM8 8h8M8 12h8M8 16h5\"/>"
    "review" =>
      "<circle cx=\"12\" cy=\"12\" r=\"9\"/><path d=\"M8.5 12l2.2 2.2 4.8-5\"/>"
    "inspect" => "<circle cx=\"11\" cy=\"11\" r=\"7\"/><path d=\"M16 16l5 5\"/>"
    "settings" =>
      "<path d=\"M4 7h10M18 7h2M4 17h2M10 17h10\"/><circle cx=\"16\" cy=\"7\" r=\"2\"/><circle cx=\"8\" cy=\"17\" r=\"2\"/>"
    "attach" => "<path d=\"M8 12.5l6-6a3 3 0 114 4l-8 8a5 5 0 11-7-7l8-8\"/>"
    _ => "<circle cx=\"12\" cy=\"12\" r=\"9\"/>"
  }
  let markup = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" width=\"" +
    size.to_string() +
    "\" height=\"" +
    size.to_string() +
    "\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\" focusable=\"false\">" +
    body +
    "</svg>"
  @html.span(
    class="operator-icon",
    attrs=@html.Attrs::build().aria_hidden("true").inner_html(markup),
    "",
  )
}
