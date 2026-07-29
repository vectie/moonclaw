///|
test "parse_acp_stream_drain_payload accepts structured error payloads" {
  let result = parse_acp_stream_drain_payload(
    (
      { "entries": [], "closed": true, "error": { "message": "stream_error" } } :
      Json).stringify(),
  )
  match result {
    Err(error) =>
      inspect(
        error,
        content="Live updates disconnected. Check that the MoonClaw gateway is running.",
      )
    Ok(_) => fail("expected structured ACP stream error")
  }
}

///|
test "display_error hides Rabbita request implementation detail" {
  inspect(
    display_error("moonbit-community/rabbita/http.RequestError.RequestError"),
    content="Unable to reach the MoonClaw gateway. Start it at http://127.0.0.1:18123 and reload.",
  )
}

///|
test "browser local upload success accepts an omitted optional error" {
  let result = parse_browser_local_upload_batch(
    (
      {
        "ok": true,
        "files": [
          {
            "id": "picker:page-2.jpg:10:1",
            "name": "page-2.jpg",
            "media_type": "image/jpeg",
            "content": "data:image/jpeg;base64,AA==",
            "source": "picker",
          },
        ],
      } : Json).stringify(),
  )
  match result {
    Ok([upload]) => {
      inspect(upload.name, content="page-2.jpg")
      inspect(upload.media_type, content="image/jpeg")
    }
    Ok(_) => fail("expected one local upload")
    Err(error) => fail(error)
  }
}

///|
test "browser copy success accepts an omitted optional error" {
  match
    parse_browser_copy_result(
      ({ "ok": true, "value": "copied" } : Json).stringify(),
    ) {
    Ok(value) => inspect(value, content="copied")
    Err(error) => fail(error)
  }
}

///|
test "parse_acp_stream_drain_payload still parses normal entries" {
  let result = parse_acp_stream_drain_payload(
    (
      #|{"entries":["{\"id\":\"event-1\",\"event_type\":\"run.Completed\",\"title\":\"Run Completed\",\"detail\":\"done\",\"timestamp\":123,\"target_id\":\"target-1\",\"session_id\":\"session-1\",\"run_id\":\"run-1\",\"status\":\"Completed\",\"data\":{}}"],"closed":false,"error":null}
    ),
  )
  match result {
    Ok((entries, closed)) => {
      inspect(entries.length(), content="1")
      inspect(entries[0].id, content="event-1")
      inspect(closed, content="false")
    }
    Err(error) => fail(error)
  }
}

///|
test "route_from_url parses cowork route and panel query" {
  let url = @url.parse(
    "http://127.0.0.1:18123/ui#/cowork?session=session-1&panel=run",
  )
  inspect(route_from_url(url) is Cowork, content="true")
  inspect(query_value(url, "session") == Some("session-1"), content="true")
  inspect(
    cowork_panel_from_query(query_value(url, "panel")) is CoworkRun,
    content="true",
  )
}

///|
test "cowork_url includes selected session and panel" {
  inspect(
    cowork_url(selected_session_key=Some("cowork:2"), panel=CoworkArtifacts),
    content="#/cowork?session=cowork:2&panel=artifacts",
  )
}
