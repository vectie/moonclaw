///|
fn cowork_request_test_session(key : String) -> CoworkSessionDetail {
  {
    session: {
      session_key: key,
      session_id: "session-" + key,
      title: "Thread " + key,
      updated_at: 1,
      state: "ready",
      last_message_preview: None,
      channel: None,
      cwd: Some("/workspace"),
      model_override: None,
      provider_override: None,
      has_plan_mode: false,
      linked_proposal_id: None,
      linked_run_id: None,
    },
    messages: [],
    plan_preview: None,
    linked_proposal: None,
    linked_run: None,
  }
}

///|
fn cowork_request_test_upload(id : String) -> CoworkLocalUpload {
  {
    id,
    name: id + ".txt",
    media_type: "text/plain",
    content: "Evidence " + id,
    source: "local",
  }
}

///|
fn cowork_request_test_draft() -> Model {
  {
    ..init_model(),
    route: Cowork,
    cowork_composer: "Prepare the brief",
    cowork_local_uploads: [cowork_request_test_upload("evidence")],
    cowork_context_chips: [
      { id: "context", label: "Source context", content: "Retain this", },
    ],
  }
}

///|
fn cowork_request_test_ready(key : String) -> Model {
  {
    ..cowork_request_test_draft(),
    selected_cowork_session_key: Some(key),
    cowork_detail: Some(cowork_request_test_session(key)),
    cowork_detail_loading: false,
  }
}

///|
fn cowork_request_test_finish(
  pending : Model,
  current : Model,
  key : String,
  consumes? : Bool = true,
) -> Model {
  artifact_test_update(
    current,
    CoworkActionFinished(
      pending.cowork_request_generation,
      key,
      pending.cowork_draft_revision,
      consumes,
      Ok(cowork_request_test_session(key)),
    ),
  )
}

///|
test "cowork start is explicit and retains complete draft until a separate send" {
  let draft = cowork_request_test_draft()
  let html = @rabbita.render_to_string(
    @rabbita.static_cell(
      render_cowork_center(@cmd.Emit(_ => @rabbita.none), draft),
    ),
  )
  assert_true(html.contains("Start conversation"))
  assert_true(html.contains("Your draft and attachments stay here"))
  let no_send = artifact_test_update(draft, SendCoworkMessage)
  assert_false(no_send.cowork_action_loading)
  assert_eq(no_send.cowork_composer, draft.cowork_composer)
  let pending = artifact_test_update(draft, CreateCoworkSession)
  assert_true(pending.cowork_create_pending)
  assert_true(pending.cowork_action_loading)
  assert_eq(
    cowork_composer_content(pending, pending.cowork_composer),
    cowork_composer_content(draft, draft.cowork_composer),
  )
  let created = artifact_test_update(
    pending,
    CoworkSessionCreated(
      pending.cowork_request_generation,
      Ok(cowork_request_test_session("new")),
    ),
  )
  assert_eq(created.selected_cowork_session_key, Some("new"))
  assert_false(created.cowork_action_loading)
  assert_false(created.cowork_create_pending)
  assert_eq(created.cowork_composer, draft.cowork_composer)
  assert_eq(created.cowork_local_uploads.length(), 1)
  assert_eq(created.cowork_context_chips.length(), 1)
  let html = @rabbita.render_to_string(
    @rabbita.static_cell(
      render_cowork_center(@cmd.Emit(_ => @rabbita.none), created),
    ),
  )
  assert_true(html.contains("Send request"))
  assert_true(html.contains("Conversation ready"))
  let sent = artifact_test_update(created, SendCoworkMessage)
  assert_true(sent.cowork_action_loading)
  assert_false(sent.cowork_create_pending)
}

///|
test "cowork creation repeated clicks do not create another request" {
  let pending = artifact_test_update(
    cowork_request_test_draft(),
    CreateCoworkSession,
  )
  let repeated = artifact_test_update(pending, CreateCoworkSession)
  assert_eq(
    repeated.cowork_request_generation,
    pending.cowork_request_generation,
  )
  assert_eq(repeated.cowork_draft_revision, pending.cowork_draft_revision)
  let sent_early = artifact_test_update(repeated, SendCoworkMessage)
  assert_eq(
    sent_early.cowork_request_generation,
    pending.cowork_request_generation,
  )
  let created = artifact_test_update(
    sent_early,
    CoworkSessionCreated(
      pending.cowork_request_generation,
      Ok(cowork_request_test_session("created")),
    ),
  )
  let duplicate = artifact_test_update(
    created,
    CoworkSessionCreated(
      pending.cowork_request_generation,
      Ok(cowork_request_test_session("duplicate")),
    ),
  )
  assert_eq(duplicate.selected_cowork_session_key, Some("created"))
}

///|
test "cowork creation failure and newer typing keep the draft and attachments" {
  let pending = artifact_test_update(
    cowork_request_test_draft(),
    CreateCoworkSession,
  )
  let edited = artifact_test_update(pending, SetCoworkComposer("Newer request"))
  let failed = artifact_test_update(
    edited,
    CoworkSessionCreated(pending.cowork_request_generation, Err("offline")),
  )
  assert_eq(failed.cowork_composer, "Newer request")
  assert_eq(failed.cowork_local_uploads.length(), 1)
  assert_eq(failed.cowork_context_chips.length(), 1)
  assert_false(failed.cowork_action_loading)
  assert_true(failed.cowork_notice.unwrap().contains("not confirmed"))
  let retry = artifact_test_update(failed, CreateCoworkSession)
  let stale = artifact_test_update(
    retry,
    CoworkSessionCreated(
      pending.cowork_request_generation,
      Ok(cowork_request_test_session("old")),
    ),
  )
  assert_true(stale.cowork_create_pending)
  let ready = artifact_test_update(
    stale,
    CoworkSessionCreated(
      retry.cowork_request_generation,
      Ok(cowork_request_test_session("new")),
    ),
  )
  assert_eq(ready.cowork_composer, "Newer request")
  assert_eq(ready.selected_cowork_session_key, Some("new"))
}

///|
test "cowork navigation during creation never selects the late new conversation" {
  let pending = artifact_test_update(
    cowork_request_test_draft(),
    CreateCoworkSession,
  )
  for
    navigation in [
      SelectCoworkSession("chosen"),
      UrlChanged(@url.parse("http://localhost/ui#/jobs")),
    ] {
    let moved = artifact_test_update(pending, navigation)
    let late = artifact_test_update(
      moved,
      CoworkSessionCreated(
        pending.cowork_request_generation,
        Ok(cowork_request_test_session("late")),
      ),
    )
    assert_eq(
      late.selected_cowork_session_key,
      moved.selected_cowork_session_key,
    )
    assert_true(late.route == moved.route)
    assert_false(late.cowork_create_pending)
    assert_false(late.cowork_action_loading)
    let error = artifact_test_update(
      late,
      CoworkSessionCreated(
        pending.cowork_request_generation,
        Err("late failure"),
      ),
    )
    assert_true(error.cowork_action_error is None)
  }
}

///|
test "cowork create URL synchronization retains files context and newer typing" {
  let pending = artifact_test_update(
    cowork_request_test_draft(),
    CreateCoworkSession,
  )
  let edited = artifact_test_update(pending, SetCoworkComposer("Newer request"))
  let created = artifact_test_update(
    edited,
    CoworkSessionCreated(
      pending.cowork_request_generation,
      Ok(cowork_request_test_session("new")),
    ),
  )
  let synced = artifact_test_update(
    created,
    UrlChanged(@url.parse("http://localhost/ui#/cowork?session=new")),
  )
  let loading = artifact_test_update(synced, LoadCoworkSession("new"))
  let ready = artifact_test_update(
    loading,
    CoworkSessionLoaded(
      "new",
      loading.cowork_detail_generation,
      Ok(cowork_request_test_session("new")),
    ),
  )
  assert_eq(ready.cowork_composer, "Newer request")
  assert_eq(ready.cowork_local_uploads.length(), 1)
  assert_eq(ready.cowork_context_chips.length(), 1)
  assert_true(cowork_ready_to_send(ready))
}

///|
test "cowork reversed detail replies keep exact chosen thread including repeat selection" {
  let a = artifact_test_update(
    cowork_request_test_draft(),
    SelectCoworkSession("a"),
  )
  let b = artifact_test_update(a, SelectCoworkSession("b"))
  let ready = artifact_test_update(
    b,
    CoworkSessionLoaded(
      "b",
      b.cowork_detail_generation,
      Ok(cowork_request_test_session("b")),
    ),
  )
  let stale = artifact_test_update(
    ready,
    CoworkSessionLoaded(
      "a",
      a.cowork_detail_generation,
      Ok(cowork_request_test_session("a")),
    ),
  )
  let stale = artifact_test_update(
    stale,
    CoworkSessionLoaded("a", a.cowork_detail_generation, Err("late A")),
  )
  assert_eq(stale.cowork_detail.unwrap().session.session_key, "b")
  assert_true(stale.cowork_detail_error is None)
  let a_again = artifact_test_update(stale, SelectCoworkSession("a"))
  let old_a = artifact_test_update(
    a_again,
    CoworkSessionLoaded(
      "a",
      a.cowork_detail_generation,
      Ok(cowork_request_test_session("a")),
    ),
  )
  assert_true(old_a.cowork_detail is None)
  assert_true(old_a.cowork_detail_loading)
}

///|
test "cowork current send clears only the submitted unchanged draft" {
  let pending = artifact_test_update(
    cowork_request_test_ready("a"),
    SendCoworkMessage,
  )
  let completed = cowork_request_test_finish(pending, pending, "a")
  assert_eq(completed.cowork_composer, "")
  assert_true(completed.cowork_local_uploads.is_empty())
  assert_true(completed.cowork_context_chips.is_empty())
  assert_false(completed.cowork_action_loading)
  let newer = artifact_test_update(completed, SetCoworkComposer("next draft"))
  let duplicate = cowork_request_test_finish(pending, newer, "a")
  assert_eq(duplicate.cowork_composer, "next draft")
}

///|
test "cowork action completion cannot erase newer text files context or reply" {
  let pending = artifact_test_update(
    cowork_request_test_ready("a"),
    SendCoworkMessage,
  )
  let edits = [
    SetCoworkComposer("New request typed while sending"),
    CoworkFilesPicked(Ok([cowork_request_test_upload("new")])),
    AttachCoworkContext("new-context", "New context", "More evidence"),
  ]
  for edit in edits {
    let newer = artifact_test_update(pending, edit)
    assert_true(newer.cowork_draft_revision > pending.cowork_draft_revision)
    let done = cowork_request_test_finish(pending, newer, "a")
    assert_eq(
      cowork_composer_content(done, done.cowork_composer),
      cowork_composer_content(newer, newer.cowork_composer),
    )
    assert_false(done.cowork_action_loading)
  }
}

///|
test "cowork switched session rejects earlier action success and failure" {
  let pending = artifact_test_update(
    cowork_request_test_ready("a"),
    SendCoworkMessage,
  )
  let moved = artifact_test_update(pending, SelectCoworkSession("b"))
  let ready = artifact_test_update(
    moved,
    CoworkSessionLoaded(
      "b",
      moved.cowork_detail_generation,
      Ok(cowork_request_test_session("b")),
    ),
  )
  let newer = artifact_test_update(ready, SetCoworkComposer("B request"))
  let late = cowork_request_test_finish(pending, newer, "a")
  let late = artifact_test_update(
    late,
    CoworkActionFinished(
      pending.cowork_request_generation,
      "a",
      pending.cowork_draft_revision,
      true,
      Err("old error"),
    ),
  )
  assert_eq(late.cowork_detail.unwrap().session.session_key, "b")
  assert_eq(late.cowork_composer, "B request")
  assert_true(late.cowork_action_error is None)
}

///|
test "cowork unrelated settings confirmation and queued actions retain unsent composer" {
  for action in [SaveCoworkConfig, ConfirmCoworkProposal("proposal")] {
    let draft = cowork_request_test_ready("a")
    let pending = artifact_test_update(draft, action)
    let completed = cowork_request_test_finish(
      pending,
      pending,
      "a",
      consumes=false,
    )
    assert_eq(
      cowork_composer_content(completed, completed.cowork_composer),
      cowork_composer_content(draft, draft.cowork_composer),
    )
  }
  let queued = artifact_test_update(
    cowork_request_test_ready("a"),
    QueueCoworkDraft("send"),
  )
  let pending = artifact_test_update(
    queued,
    RunQueuedCoworkDraft(queued.cowork_draft_queue[0].id),
  )
  let completed = cowork_request_test_finish(
    pending,
    pending,
    "a",
    consumes=false,
  )
  assert_eq(completed.cowork_composer, queued.cowork_composer)
  assert_eq(completed.cowork_local_uploads.length(), 1)
}

///|
test "cowork session navigation parks separate in-memory drafts with their attachments" {
  let a = cowork_request_test_ready("a")
  let b = artifact_test_update(a, SelectCoworkSession("b"))
  assert_eq(b.cowork_composer, "")
  assert_true(b.cowork_local_uploads.is_empty())
  let b = artifact_test_update(b, SetCoworkComposer("Only for B"))
  let restored = artifact_test_update(b, SelectCoworkSession("a"))
  assert_eq(restored.cowork_composer, a.cowork_composer)
  assert_eq(restored.cowork_local_uploads.length(), 1)
  assert_eq(restored.cowork_context_chips.length(), 1)
  let restored_b = artifact_test_update(restored, SelectCoworkSession("b"))
  assert_eq(restored_b.cowork_composer, "Only for B")
  assert_true(restored_b.cowork_local_uploads.is_empty())
}

///|
test "cowork current failures and wrong response identity retain unsent input" {
  let pending = artifact_test_update(
    cowork_request_test_ready("a"),
    SendCoworkMessage,
  )
  let failed = artifact_test_update(
    pending,
    CoworkActionFinished(
      pending.cowork_request_generation,
      "a",
      pending.cowork_draft_revision,
      true,
      Err("offline"),
    ),
  )
  assert_eq(failed.cowork_composer, pending.cowork_composer)
  assert_false(failed.cowork_action_loading)
  assert_true(cowork_ready_to_send(failed))
  let wrong = artifact_test_update(
    pending,
    CoworkActionFinished(
      pending.cowork_request_generation,
      "a",
      pending.cowork_draft_revision,
      true,
      Ok(cowork_request_test_session("other")),
    ),
  )
  assert_eq(wrong.cowork_composer, pending.cowork_composer)
  assert_eq(wrong.cowork_detail.unwrap().session.session_key, "a")
  assert_true(wrong.cowork_action_error is Some(_))
}

///|
test "cowork reads cannot replace an active action or its fresher completed detail" {
  let ready = cowork_request_test_ready("a")
  let pending = artifact_test_update(ready, SendCoworkMessage)
  let refreshed = artifact_test_update(pending, LoadCoworkSession("a"))
  assert_false(refreshed.cowork_detail_loading)
  assert_eq(
    refreshed.cowork_detail_generation,
    pending.cowork_detail_generation,
  )
  let done = cowork_request_test_finish(pending, refreshed, "a")
  let stale = artifact_test_update(
    done,
    CoworkSessionLoaded(
      "a",
      ready.cowork_detail_generation,
      Ok({
        ..cowork_request_test_session("a"),
        session: {
          ..cowork_request_test_session("a").session,
          title: "Old title",
        },
      }),
    ),
  )
  assert_eq(stale.cowork_detail.unwrap().session.title, "Thread a")
}

///|
test "cowork early work-thread list cannot relocate a composed new request" {
  let draft = cowork_request_test_draft()
  let refreshed = artifact_test_update(
    draft,
    CoworkSessionsLoaded(Ok([cowork_request_test_session("existing").session])),
  )
  assert_true(refreshed.selected_cowork_session_key is None)
  assert_eq(refreshed.cowork_composer, draft.cowork_composer)
  assert_eq(refreshed.cowork_local_uploads.length(), 1)
}

///|
test "cowork same-thread selection and panel URL changes retain the current draft" {
  let ready = cowork_request_test_ready("a")
  let repeated = artifact_test_update(ready, SelectCoworkSession("a"))
  assert_eq(repeated.cowork_local_uploads.length(), 1)
  assert_eq(repeated.cowork_context_chips.length(), 1)
  let sending = artifact_test_update(ready, SendCoworkMessage)
  let panel = artifact_test_update(
    sending,
    UrlChanged(
      @url.parse("http://localhost/ui#/cowork?session=a&panel=workspace"),
    ),
  )
  assert_true(panel.cowork_detail is Some(_))
  assert_true(panel.cowork_action_loading)
  assert_false(panel.cowork_detail_loading)
  let failed = artifact_test_update(
    panel,
    CoworkActionFinished(
      sending.cowork_request_generation,
      "a",
      sending.cowork_draft_revision,
      true,
      Err("offline"),
    ),
  )
  assert_true(cowork_ready_to_send(failed))
  assert_eq(failed.cowork_local_uploads.length(), 1)
}

///|
test "cowork confirmed creation transfers restored draft out of the origin cache" {
  let original = cowork_request_test_draft()
  let parked = artifact_test_update(original, SelectCoworkSession("other"))
  let restored = artifact_test_update(
    parked,
    UrlChanged(@url.parse("http://localhost/ui#/cowork")),
  )
  let creating = artifact_test_update(restored, CreateCoworkSession)
  let failed = artifact_test_update(
    creating,
    CoworkSessionCreated(creating.cowork_request_generation, Err("unconfirmed")),
  )
  assert_eq(failed.cowork_composer, original.cowork_composer)
  assert_true(
    failed.cowork_saved_drafts.any(draft => draft.session_key is None),
  )
  let creating = artifact_test_update(failed, CreateCoworkSession)
  let created = artifact_test_update(
    creating,
    CoworkSessionCreated(
      creating.cowork_request_generation,
      Ok(cowork_request_test_session("new")),
    ),
  )
  assert_false(
    created.cowork_saved_drafts.any(draft => draft.session_key is None),
  )
  assert_eq(created.cowork_composer, original.cowork_composer)
  let sent = artifact_test_update(created, SendCoworkMessage)
  let done = cowork_request_test_finish(sent, sent, "new")
  let returned = artifact_test_update(
    done,
    UrlChanged(@url.parse("http://localhost/ui#/cowork")),
  )
  assert_eq(returned.cowork_composer, "")
  assert_true(returned.cowork_local_uploads.is_empty())
  assert_true(returned.cowork_context_chips.is_empty())
}

///|
test "cowork confirmed send consumes its unchanged parked draft only" {
  let sent = artifact_test_update(
    cowork_request_test_ready("a"),
    SendCoworkMessage,
  )
  let moved = artifact_test_update(sent, SelectCoworkSession("b"))
  let other = artifact_test_update(moved, SetCoworkComposer("Only B"))
  let other = artifact_test_update(
    other,
    CoworkFilesPicked(Ok([cowork_request_test_upload("b")])),
  )
  let done = cowork_request_test_finish(sent, other, "a")
  assert_eq(done.selected_cowork_session_key, Some("b"))
  assert_eq(done.cowork_composer, "Only B")
  assert_eq(done.cowork_local_uploads[0].id, "b")
  let returned = artifact_test_update(done, SelectCoworkSession("a"))
  assert_eq(returned.cowork_composer, "")
  assert_true(returned.cowork_local_uploads.is_empty())
  assert_true(returned.cowork_pending_requests.is_empty())
}

///|
test "cowork late confirmed success preserves newer edits to the parked owner" {
  let sent = artifact_test_update(
    cowork_request_test_ready("a"),
    SendCoworkMessage,
  )
  let moved = artifact_test_update(sent, SelectCoworkSession("b"))
  let returned = artifact_test_update(moved, SelectCoworkSession("a"))
  let edited = artifact_test_update(
    returned,
    SetCoworkComposer("New A request"),
  )
  let edited = artifact_test_update(
    edited,
    CoworkFilesPicked(Ok([cowork_request_test_upload("new-a")])),
  )
  let parked = artifact_test_update(edited, SelectCoworkSession("b"))
  let done = cowork_request_test_finish(sent, parked, "a")
  let restored = artifact_test_update(done, SelectCoworkSession("a"))
  assert_eq(restored.cowork_composer, "New A request")
  assert_eq(restored.cowork_local_uploads.length(), 2)
  assert_eq(restored.cowork_draft_revision, edited.cowork_draft_revision)
}

///|
test "cowork uncertain and wrong-owner responses never consume parked input" {
  let sent = artifact_test_update(
    cowork_request_test_ready("a"),
    SendCoworkMessage,
  )
  for result in [Err("unconfirmed"), Ok(cowork_request_test_session("wrong"))] {
    let parked = artifact_test_update(sent, SelectCoworkSession("b"))
    let settled = artifact_test_update(
      parked,
      CoworkActionFinished(
        sent.cowork_request_generation,
        "a",
        sent.cowork_draft_revision,
        true,
        result,
      ),
    )
    let restored = artifact_test_update(settled, SelectCoworkSession("a"))
    assert_eq(restored.cowork_composer, sent.cowork_composer)
    assert_eq(restored.cowork_local_uploads.length(), 1)
    assert_eq(restored.cowork_context_chips.length(), 1)
  }
}

///|
test "cowork pending ownership survives away and back without a duplicate send" {
  let sent = artifact_test_update(
    cowork_request_test_ready("a"),
    SendCoworkMessage,
  )
  let moved = artifact_test_update(sent, SelectCoworkSession("b"))
  let returned = artifact_test_update(moved, SelectCoworkSession("a"))
  let ready = artifact_test_update(
    returned,
    CoworkSessionLoaded(
      "a",
      returned.cowork_detail_generation,
      Ok(cowork_request_test_session("a")),
    ),
  )
  assert_false(cowork_ready_to_send(ready))
  let repeated = artifact_test_update(ready, SendCoworkMessage)
  assert_eq(repeated.cowork_pending_requests.length(), 1)
  let done = cowork_request_test_finish(sent, repeated, "a")
  assert_eq(done.cowork_composer, "")
  assert_true(done.cowork_local_uploads.is_empty())
  assert_true(done.cowork_pending_requests.is_empty())
  let newer = artifact_test_update(done, SetCoworkComposer("Genuinely new"))
  let duplicate = cowork_request_test_finish(sent, newer, "a")
  assert_eq(duplicate.cowork_composer, "Genuinely new")
}

///|
test "cowork confirming parked A preserves the separate pending request in B" {
  let a = artifact_test_update(
    cowork_request_test_ready("a"),
    SendCoworkMessage,
  )
  let moved = artifact_test_update(a, SelectCoworkSession("b"))
  let loaded = artifact_test_update(
    moved,
    CoworkSessionLoaded(
      "b",
      moved.cowork_detail_generation,
      Ok(cowork_request_test_session("b")),
    ),
  )
  let drafted = artifact_test_update(loaded, SetCoworkComposer("B request"))
  let b = artifact_test_update(drafted, SendCoworkMessage)
  assert_eq(b.cowork_pending_requests.length(), 2)
  let a_done = cowork_request_test_finish(a, b, "a")
  assert_true(a_done.cowork_action_loading)
  assert_eq(a_done.cowork_request_generation, b.cowork_request_generation)
  assert_eq(a_done.cowork_composer, "B request")
  assert_eq(a_done.cowork_pending_requests.length(), 1)
  let both_done = cowork_request_test_finish(b, a_done, "b")
  assert_false(both_done.cowork_action_loading)
  assert_eq(both_done.cowork_composer, "")
  assert_true(both_done.cowork_pending_requests.is_empty())
}
