///|
fn human_test_loaded(
  id : String,
  content : String,
  digest : String,
) -> LoadedArtifact {
  {
    ..artifact_test_result(id, content),
    revision_source: Some({
      run_id: "run-human",
      parent_digest: digest,
      parent_version: 1,
    }),
  }
}

///|
fn human_test_open(
  model : Model,
  id : String,
  content : String,
  digest : String,
) -> Model {
  let pending = artifact_test_update(model, OpenArtifact(id))
  artifact_test_update(
    pending,
    ArtifactLoaded(
      id,
      pending.artifact_request_generation,
      Ok(human_test_loaded(id, content, digest)),
    ),
  )
}

///|
test "human draft survives close navigation failed save and stale A B A responses" {
  let a = human_test_open(init_model(), "a", "source A", "sha256:a")
  let edited = artifact_test_update(a, SetArtifactEditorDraft("human A"))
  let closed = artifact_test_update(edited, CloseArtifactModal)
  let b = human_test_open(closed, "b", "source B", "sha256:b")
  let reopened = human_test_open(b, "a", "changed source A", "sha256:new")
  assert_eq(reopened.artifact_editor_draft, "human A")
  let late = artifact_test_update(
    reopened,
    ArtifactLoaded(
      "a",
      a.artifact_request_generation,
      Ok(human_test_loaded("a", "stale A", "sha256:a")),
    ),
  )
  assert_eq(late.artifact_editor_draft, "human A")
  let key = human_revision_key(late, late.artifact_modal.unwrap())
  let draft = late.artifact_drafts[key]
  assert_eq(draft.source_content, "source A")
  assert_eq(draft.parent_digest, "sha256:a")
  let pending = artifact_test_update(late, SaveHumanRevision)
  let request = pending.artifact_drafts[key]
  let failed = artifact_test_update(
    pending,
    HumanRevisionSaved(
      key,
      request.generation,
      request.save_id.unwrap(),
      Err("Save confirmation is unavailable"),
    ),
  )
  assert_eq(failed.artifact_editor_draft, "human A")
  let attempted_edit = artifact_test_update(
    failed,
    SetArtifactEditorDraft("different uncertain payload"),
  )
  assert_eq(attempted_edit.artifact_editor_draft, "human A")
  let retry = artifact_test_update(attempted_edit, SaveHumanRevision)
  assert_eq(retry.artifact_drafts[key].save_id, request.save_id)
  let stale = artifact_test_update(
    retry,
    HumanRevisionSaved(
      key,
      request.generation,
      request.save_id.unwrap(),
      Ok(artifact_test_result("old", "ignored").artifact),
    ),
  )
  assert_true(stale.artifact_drafts[key].pending)
  let html = @rabbita.render_to_string(
    @rabbita.static_cell(
      render_artifact_modal(@cmd.Emit(_ => @rabbita.none), reopened),
    ),
  )
  assert_true(html.contains("Save human-revised copy"))
  assert_true(html.contains("Compare original source"))
  assert_true(html.contains("human A"))
  assert_true(html.contains("changed source A"))
  let rebased = artifact_test_update(reopened, RebaseHumanRevision)
  assert_eq(rebased.artifact_drafts[key].parent_digest, "sha256:new")
  assert_eq(rebased.artifact_editor_draft, "human A")
  let no_source_pending = artifact_test_update(closed, OpenArtifact("a"))
  let unavailable = artifact_test_update(
    no_source_pending,
    ArtifactLoaded(
      "a",
      no_source_pending.artifact_request_generation,
      Ok({ ..artifact_test_result("a", "unavailable"), content: None, }),
    ),
  )
  assert_eq(unavailable.artifact_editor_draft, "human A")
}

///|
#cfg(target="js")
extern "js" fn human_test_gateway(
  install : (String) -> Unit,
  edit : (String, String) -> String,
  save : (String, String, String, String, Int) -> @js.Promise,
) -> @js.Promise =
  #| async (install, edit, saveImpl) => {
  #|   const base = process.env.MOONCLAW_HUMAN_HTTP_URL;
  #|   if (!/^http:\/\/127\.0\.0\.1:\d+$/.test(base || "")) throw new Error("Native fixture required");
  #|   const check = (ok, text) => { if (!ok) throw new Error(text); };
  #|   const original = globalThis.fetch;
  #|   try {
  #|     delete globalThis.__moonclawTransport; install(base);
  #|     const transport = globalThis.__moonclawTransport;
  #|     const save = (base, run, parent, payload) => saveImpl(base, run, parent, payload, transport.epoch());
  #|     const endpoint = base + "/v1/jobs/runs/run-human/artifacts/source-human/human-revisions";
  #|     let r = await fetch(endpoint, {method:"POST",body:"{}"}); check(r.status === 401, "missing token"); await r.text();
  #|     transport.setToken(base, "wrong"); r = await fetch(endpoint, {method:"POST",body:"{}"}); check(r.status === 401, "wrong token"); await r.text();
  #|     transport.setToken(base, "fixture-only-token");
  #|     const source = await fetch(base + "/v1/artifacts/source-human"); check(source.ok,"open source");
  #|     const payload = edit(base, await source.text());
  #|     const oldEpoch = transport.epoch(); transport.clear(); transport.setToken(base, "fixture-only-token");
  #|     const priorFetch = globalThis.fetch; let staleCalls = 0; globalThis.fetch = (...args) => { staleCalls++; return priorFetch(...args); };
  #|     check(!!JSON.parse(await saveImpl(base,"run-human","source-human",payload,oldEpoch)).error && staleCalls === 0,"queued write invalidated by token change"); globalThis.fetch = priorFetch;
  #|     check(JSON.parse(payload).content === "Human revised 世界\u0000\n", "compiled editor draft");
  #|     const denied = await fetch(endpoint, {method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({...JSON.parse(payload), actor_kind:"executor"})}); check(denied.status === 400, "caller metadata refused"); await denied.text();
  #|     const transportFetch = globalThis.fetch; let committed;
  #|     globalThis.fetch = async (...args) => { const response = await transportFetch(...args); if (String(args[0]) === endpoint && args[1]?.method === "POST") { committed = await response.json(); throw new Error("Fixture drops the acknowledgement after durable commit"); } return response; };
  #|     const uncertain = JSON.parse(await save(base,"run-human","source-human",payload)); check(!!uncertain.error && committed?.artifact, "lost acknowledgement preserves committed copy");
  #|     globalThis.fetch = transportFetch;
  #|     const saved = JSON.parse(await save(base,"run-human","source-human",payload)); check(saved.artifact?.artifact_type === "human_revision" && saved.artifact.id === committed.artifact.id && saved.artifact.created_at === committed.artifact.created_at, "real saved copy recovered");
  #|     const replay = JSON.parse(await save(base,"run-human","source-human",payload)); check(replay.artifact?.id === saved.artifact.id && replay.artifact?.created_at === saved.artifact.created_at, "lost acknowledgement exact replay");
  #|     const conflict = JSON.parse(await save(base,"run-human","source-human",JSON.stringify({...JSON.parse(payload),content:"conflict"}))); check(conflict.error?.includes("different"), "conflicting same ID");
  #|     const wrongRun = JSON.parse(await save(base,"wrong-run","source-human",payload)); check(!!wrongRun.error, "wrong run");
  #|     const binary = await fetch(base + "/v1/jobs/runs/run-human/artifacts/binary-human/human-revisions", {method:"POST",headers:{"Content-Type":"application/json"},body:payload}); check(binary.status === 409, "binary refused"); await binary.text();
  #|     const bytes = await fetch(base + "/v1/jobs/runs/run-human/artifacts/" + saved.artifact.id + "/download"); check(bytes.ok, "download saved exact ID"); check(new TextDecoder().decode(await bytes.arrayBuffer()) === JSON.parse(payload).content,"saved exact UTF8 bytes");
  #|     const unchanged = await fetch(base + "/v1/jobs/runs/run-human/artifacts/source-human/download"); check(await unchanged.text() === "Original source 报告\u0000\n", "source unchanged");
  #|     return "ACTUAL_HUMAN_GATEWAY_UI_PASSED";
  #|   } finally { globalThis.__moonclawTransport?.clear(); delete globalThis.__moonclawTransport; globalThis.fetch = original; }
  #| }

///|
#skip("Run through the real native authenticated human revision gateway fixture")
test "compiled editor saves human revision through real native HTTP" {
  @js.async_test(() => {
    let result : String = human_test_gateway(
        configure_gateway_transport,
        (base, raw) => {
          let json = @json.parse(raw) catch { _ => return "invalid" }
          guard parse_loaded_artifact_payload(json) is Ok(loaded) &&
            loaded.revision_source is Some(source) else {
            return "invalid"
          }
          let pending = artifact_test_update(
            { ..init_model(), gateway_base: base, },
            OpenArtifact(loaded.artifact.id),
          )
          let displayed = artifact_test_update(
            pending,
            ArtifactLoaded(
              loaded.artifact.id,
              pending.artifact_request_generation,
              Ok(loaded),
            ),
          )
          let edited = artifact_test_update(
            displayed,
            SetArtifactEditorDraft("Human revised 世界\u0000\n"),
          )
          let reopened = human_test_open(
            artifact_test_update(edited, CloseArtifactModal),
            loaded.artifact.id,
            loaded.content.unwrap(),
            source.parent_digest,
          )
          let saving = artifact_test_update(reopened, SaveHumanRevision)
          let draft = saving.artifact_drafts[human_revision_key(saving, loaded)]
          let payload : Json = {
            "save_id": draft.save_id.unwrap(),
            "expected_parent_digest": draft.parent_digest,
            "content": draft.content,
          }
          payload.stringify()
        },
        browser_save_human_revision,
      )
      .wait()
      .cast()
    assert_eq(result, "ACTUAL_HUMAN_GATEWAY_UI_PASSED")
    println(result)
  })
}
