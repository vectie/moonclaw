///|
struct HumanRevisionDraft {
  gateway_base : String
  run_id : String
  parent_id : String
  content : String
  source_content : String
  parent_digest : String
  save_id : String?
  generation : Int
  pending : Bool
  saved : UiArtifact?
  notice : String?
}

///|
fn human_revision_key(model : Model, loaded : LoadedArtifact) -> String {
  if loaded.revision_source is None {
    for key, draft in model.artifact_drafts {
      if draft.gateway_base == model.gateway_base &&
        draft.parent_id == loaded.artifact.id {
        return key
      }
    }
  }
  let key : Json = [
    model.gateway_base,
    loaded.revision_source.map(s => s.run_id).unwrap_or(""),
    loaded.artifact.id,
  ]
  key.stringify()
}

///|
fn install_human_revision_draft(
  model : Model,
  loaded : LoadedArtifact,
) -> Model {
  guard loaded.revision_source is Some(source) &&
    loaded.content is Some(content) else {
    return match model.artifact_drafts.get(human_revision_key(model, loaded)) {
      Some(draft) => { ..model, artifact_editor_draft: draft.content, }
      None => model
    }
  }
  let key = human_revision_key(model, loaded)
  let drafts = model.artifact_drafts.copy()
  let draft = match drafts.get(key) {
    Some(draft) => draft
    None =>
      HumanRevisionDraft::{
        gateway_base: model.gateway_base,
        run_id: source.run_id,
        parent_id: loaded.artifact.id,
        content,
        source_content: content,
        parent_digest: source.parent_digest,
        save_id: None,
        generation: 0,
        pending: false,
        saved: None,
        notice: None,
      }
  }
  drafts[key] = draft
  { ..model, artifact_drafts: drafts, artifact_editor_draft: draft.content, }
}

///|
fn set_human_revision_draft(model : Model, value : String) -> Model {
  guard model.artifact_modal is Some(loaded) &&
    model.artifact_drafts.get(human_revision_key(model, loaded)) is Some(draft) else {
    return { ..model, artifact_editor_draft: value, }
  }
  // Preserve the exact in-flight or uncertain request until same-ID replay has
  // confirmed it. It must never silently become a different payload.
  if draft.pending || (draft.save_id is Some(_) && draft.saved is None) {
    return model
  }
  let drafts = model.artifact_drafts.copy()
  drafts[human_revision_key(model, loaded)] = {
    ..draft,
    content: value,
    save_id: None,
    saved: None,
    notice: None,
  }
  { ..model, artifact_drafts: drafts, artifact_editor_draft: value, }
}

///|
fn human_revision_editor_locked(model : Model) -> Bool {
  match model.artifact_modal {
    Some(loaded) =>
      match model.artifact_drafts.get(human_revision_key(model, loaded)) {
        Some(draft) =>
          draft.pending || (draft.save_id is Some(_) && draft.saved is None)
        None => false
      }
    None => false
  }
}

///|
#cfg(target="js")
extern "js" fn human_revision_save_id() -> String =
  #| () => Array.from(globalThis.crypto.getRandomValues(new Uint8Array(24)), byte => byte.toString(16).padStart(2, "0")).join("")

///|
// Uses the shipped exact-gateway authenticated fetch transport. No credentials
// or drafts are written to browser storage. A timeout is explicitly uncertain.
#cfg(target="js")
extern "js" fn browser_save_human_revision(
  base : String,
  run : String,
  parent : String,
  payload : String,
  ticket : Int,
) -> @js.Promise =
  #| async (base, run, parent, payload, ticket) => {
  #|   const controller = new AbortController(), timer = setTimeout(() => controller.abort(), 60000);
  #|   try {
  #|     if (globalThis.__moonclawTransport?.epoch() !== ticket || globalThis.__moonclawTransport?.base() !== new URL(base, globalThis.location?.origin || "http://localhost").href.replace(/\/$/, "")) throw new Error("Gateway context changed. Retry this saved request on its original gateway.");
  #|     const response = await fetch(base + "/v1/jobs/runs/" + encodeURIComponent(run) + "/artifacts/" + encodeURIComponent(parent) + "/human-revisions", { method: "POST", headers: { "Content-Type": "application/json" }, body: payload, signal: controller.signal, redirect: "error", cache: "no-store" });
  #|     const value = await response.json();
  #|     if (!response.ok) return JSON.stringify({ error: response.status === 401 ? "Gateway token required or rejected. Configure access, then retry the same save." : value.error?.message || "Save failed. Keep your draft and retry the same save." });
  #|     if (value.save_id !== JSON.parse(payload).save_id || value.artifact?.artifact_type !== "human_revision" || value.artifact?.run_id !== run || value.artifact?.metadata?.parent_artifact_id !== parent) throw new Error("Save acknowledgement did not match this request.");
  #|     return JSON.stringify(value);
  #|   } catch (_) { return JSON.stringify({ error: "Save confirmation is unavailable. Keep your draft and retry the same save ID to recover any committed copy." }); }
  #|   finally { clearTimeout(timer); }
  #| }

///|
fn parse_human_revision_result(raw : String) -> Result[UiArtifact, String] {
  let value = @json.parse(raw) catch {
    _ => return Err("Save confirmation could not be read. Retry the same save.")
  }
  match value {
    { "artifact": artifact, .. } =>
      match (try? @json.from_json(artifact) : Result[UiArtifact, Error]) {
        Ok(artifact) => Ok(artifact)
        Err(_) =>
          Err("Save confirmation could not be read. Retry the same save.")
      }
    { "error": String(message), .. } => Err(message)
    _ => Err("Save confirmation could not be read. Retry the same save.")
  }
}

///|
fn save_human_revision(dispatch : Dispatch[Msg], model : Model) -> (Cmd, Model) {
  guard model.artifact_modal is Some(loaded) &&
    loaded.revision_source is Some(source) else {
    return (@rabbita.none, model)
  }
  let key = human_revision_key(model, loaded)
  guard model.artifact_drafts.get(key) is Some(draft) &&
    !draft.pending &&
    draft.saved is None else {
    return (@rabbita.none, model)
  }
  let id = draft.save_id.unwrap_or_else(human_revision_save_id)
  let generation = draft.generation + 1
  let ticket = gateway_transport_epoch()
  let payload : Json = {
    "save_id": id,
    "expected_parent_digest": draft.parent_digest,
    "content": draft.content,
  }
  let cmd = @rabbita.perform(
    result => dispatch(HumanRevisionSaved(key, generation, id, result)),
    fn() noraise {
      parse_human_revision_result(
        wait_browser_value_json(
          browser_save_human_revision(
            model.gateway_base,
            source.run_id,
            loaded.artifact.id,
            payload.stringify(),
            ticket,
          ),
        ),
      )
    },
  )
  let drafts = model.artifact_drafts.copy()
  drafts[key] = {
    ..draft,
    save_id: Some(id),
    generation,
    pending: true,
    notice: Some("Saving human-revised copy…"),
  }
  (cmd, { ..model, artifact_drafts: drafts, })
}

///|
fn complete_human_revision(
  model : Model,
  key : String,
  generation : Int,
  id : String,
  result : Result[UiArtifact, String],
) -> Model {
  guard model.artifact_drafts.get(key) is Some(draft) &&
    draft.pending &&
    draft.generation == generation &&
    draft.save_id == Some(id) else {
    return model
  }
  let drafts = model.artifact_drafts.copy()
  drafts[key] = match result {
    Ok(saved) =>
      {
        ..draft,
        pending: false,
        saved: Some(saved),
        notice: Some(
          "Human-revised copy saved. The source is unchanged; this is not accepted execution output.",
        ),
      }
    Err(error) =>
      {
        ..draft,
        pending: false,
        notice: Some(error),
        save_id: if error.has_prefix("Parent content changed;") {
          None
        } else {
          draft.save_id
        },
      }
  }
  let add_saved = fn(snapshot : UiSnapshot?) -> UiSnapshot? {
    match (snapshot, result) {
      (Some(snapshot), Ok(saved)) if model.gateway_base == draft.gateway_base &&
        snapshot.run.id == draft.run_id &&
        !snapshot.artifacts.any(a => a.id == saved.id) =>
        Some({ ..snapshot, artifacts: snapshot.artifacts + [saved], })
      _ => snapshot
    }
  }
  {
    ..model,
    artifact_drafts: drafts,
    snapshot: add_saved(model.snapshot),
    cowork_linked_snapshot: add_saved(model.cowork_linked_snapshot),
  }
}

///|
fn rebase_human_revision(model : Model) -> Model {
  guard model.artifact_modal is Some(loaded) &&
    loaded.revision_source is Some(source) &&
    model.artifact_drafts.get(human_revision_key(model, loaded)) is Some(draft) &&
    !draft.pending &&
    draft.save_id is None else {
    return model
  }
  let drafts = model.artifact_drafts.copy()
  drafts[human_revision_key(model, loaded)] = {
    ..draft,
    parent_digest: source.parent_digest,
    source_content: loaded.content.unwrap_or(""),
    notice: None,
  }
  { ..model, artifact_drafts: drafts, }
}

///|
fn render_human_revision_controls(
  dispatch : Dispatch[Msg],
  model : Model,
) -> Html {
  guard model.artifact_modal is Some(loaded) &&
    loaded.revision_source is Some(source) &&
    model.artifact_drafts.get(human_revision_key(model, loaded)) is Some(draft) else {
    return p(
      class="muted",
      "Preview only. Saving requires a retained UTF-8 text or JSON artifact with a verified run and source digest.",
    )
  }
  div([
    p(
      class="muted",
      "Draft retained in this tab across Close and navigation. Save a separate human-revised copy; the original remains unchanged.",
    ),
    p(
      class="mono",
      "Source v" +
      source.parent_version.to_string() +
      " · " +
      draft.parent_digest,
    ),
    @html.details([
      @html.summary("Compare original source"),
      @html.pre(class="mono", draft.source_content),
    ]),
    if source.parent_digest != draft.parent_digest {
      div([
        p(
          "The retained source changed. Your draft is preserved. Compare the reopened source before rebasing.",
        ),
        @html.pre(class="mono", loaded.content.unwrap_or("")),
        button(
          disabled=draft.pending || draft.save_id is Some(_),
          on_click=dispatch(RebaseHumanRevision),
          "Use reopened source as parent",
        ),
      ])
    } else {
      nothing
    },
    button(
      disabled=draft.pending || draft.saved is Some(_),
      on_click=dispatch(SaveHumanRevision),
      if draft.pending {
        "Saving…"
      } else if draft.save_id is Some(_) && draft.saved is None {
        "Retry same save"
      } else {
        "Save human-revised copy"
      },
    ),
    match draft.notice {
      Some(notice) => p(notice)
      None => nothing
    },
    match draft.saved {
      Some(saved) =>
        button(
          on_click=dispatch(OpenArtifact(saved.id)),
          "Open saved human-revised copy",
        )
      None => nothing
    },
  ])
}
