///|
// Rabbita 0.12.4 uses global fetch but has no request-header API. Install one
// narrowly scoped transport for its requests and the binary download path.
#cfg(target="js")
extern "js" fn configure_gateway_transport(base : String) =
  #| (base) => {
  #|   if (!globalThis.__moonclawTransport) {
  #|     const original = globalThis.fetch.bind(globalThis);
  #|     let gateway = "", token = "", active = null, epoch = 0, downloadEpoch = 0;
  #|     const requests = new Set();
  #|     const cancel = () => { downloadEpoch++; if (active) active.abort(); active = null; };
  #|     const invalidate = () => { epoch++; cancel(); for (const request of requests) request.abort(); requests.clear(); };
  #|     const configure = (base) => {
  #|       const url = new URL(base, globalThis.location?.origin || "http://localhost");
  #|       if (!/^https?:$/.test(url.protocol) || url.username || url.password || url.search || url.hash) throw new Error("Invalid gateway");
  #|       const next = url.href.replace(/\/$/, "");
  #|       if (next !== gateway) { invalidate(); token = ""; gateway = next; }
  #|     };
  #|     globalThis.fetch = (input, options = {}) => {
  #|       const url = new URL(typeof input === "string" || input instanceof URL ? input : input.url, globalThis.location?.origin || "http://localhost");
  #|       if (!url.username && !url.password && url.href.startsWith(gateway + "/v1/")) {
  #|         let headers;
  #|         try {
  #|           headers = new Headers(options.headers || (typeof input === "object" ? input.headers : undefined));
  #|           if (token) headers.set("Authorization", "Bearer " + token);
  #|         } catch (_) { return Promise.reject(new Error("Gateway request could not be prepared. Check gateway access and retry.")); }
  #|         const request = new AbortController(), started = epoch;
  #|         requests.add(request);
  #|         const signals = [request.signal, options.signal || (typeof input === "object" ? input.signal : null)].filter(Boolean);
  #|         return original(input, { ...options, headers, redirect: "error", signal: AbortSignal.any(signals) }).then(response => {
  #|           requests.delete(request);
  #|           if (started !== epoch) throw new Error("Gateway context changed. Refresh to retry.");
  #|           for (const method of ["text", "json", "blob", "arrayBuffer"]) {
  #|             const read = response[method].bind(response);
  #|             response[method] = async () => { const value = await read(); if (started !== epoch) throw new Error("Gateway context changed. Refresh to retry."); return value; };
  #|           }
  #|           return response;
  #|         }).catch(error => { requests.delete(request); throw error; });
  #|       }
  #|       return original(input, options);
  #|     };
  #|     const safeName = (name) => {
  #|       const leaf = name.replace(/\\/g, "/").split("/").pop().replace(/[\x00-\x1f\x7f<>:"|?*]/g, "_").trim().replace(/[. ]+$/, "");
  #|       return !leaf || /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(leaf) ? "artifact.bin" : leaf;
  #|     };
  #|     globalThis.__moonclawTransport = {
  #|       configure, cancel,
  #|       epoch: () => epoch,
  #|       base: () => gateway,
  #|       downloadEpoch: () => downloadEpoch,
  #|       setToken(base, value) {
  #|         configure(base); invalidate(); token = "";
  #|         if (/[^\x20-\x7e]/.test(value)) return false;
  #|         const candidate = value.trim();
  #|         if (!/^[\x21-\x7e]+$/.test(candidate)) return false;
  #|         token = candidate; return true;
  #|       },
  #|       clear() { invalidate(); token = ""; },
  #|       async download(base, run, id, expected = downloadEpoch, kind = "artifacts") {
  #|         if (kind !== "artifacts" && kind !== "command-outputs") return JSON.stringify({ ok: false, value: "", error: "Unknown retained output kind" });
  #|         if (expected !== downloadEpoch) return JSON.stringify({ ok: false, value: "", error: "Download cancelled before it started." });
  #|         configure(base); cancel();
  #|         const controller = new AbortController(); active = controller;
  #|         const timeout = setTimeout(() => controller.abort(), 60000);
  #|         let objectURL = null;
  #|         try {
  #|           const url = gateway + "/v1/jobs/runs/" + encodeURIComponent(run) + "/" + kind + "/" + encodeURIComponent(id) + "/download";
  #|           const response = await globalThis.fetch(url, { signal: controller.signal, redirect: "error", cache: "no-store" });
  #|           if (!response.ok) {
  #|             let message = response.status === 401 ? "Gateway token required or rejected. Enter the token for this gateway and retry." : "Download failed. Refresh this run and retry.";
  #|             try { const body = await response.json(); if (response.status !== 401 && typeof body.error?.message === "string") message = body.error.message; } catch (_) {}
  #|             throw new Error(message);
  #|           }
  #|           const blob = await response.blob();
  #|           if (controller.signal.aborted || active !== controller) throw new Error("Download cancelled. You can retry the same artifact.");
  #|           if (blob.size > 67108864) throw new Error("Artifact exceeds the 64 MiB download limit.");
  #|           const disposition = response.headers.get("Content-Disposition") || "";
  #|           const match = /filename\*=UTF-8''([^;]+)/i.exec(disposition);
  #|           const name = safeName(match ? decodeURIComponent(match[1]) : "artifact.bin");
  #|           objectURL = URL.createObjectURL(blob);
  #|           const link = document.createElement("a");
  #|           link.href = objectURL; link.download = name; document.body.appendChild(link);
  #|           try { link.click(); } finally { link.remove(); }
  #|           const release = objectURL; objectURL = null;
  #|           setTimeout(() => URL.revokeObjectURL(release), 30000);
  #|           return JSON.stringify({ ok: true, value: "Download handed to your browser: " + name });
  #|         } catch (error) {
  #|           return JSON.stringify({ ok: false, value: "", error: controller.signal.aborted ? "Download cancelled or timed out. Retry the same artifact; work was not rerun." : String(error.message || "Download failed. Retry the same artifact.") });
  #|         } finally {
  #|           clearTimeout(timeout); if (objectURL) URL.revokeObjectURL(objectURL); if (active === controller) active = null;
  #|         }
  #|       }
  #|     };
  #|   }
  #|   globalThis.__moonclawTransport.configure(base);
  #| }

///|
#cfg(target="js")
extern "js" fn set_gateway_token(base : String, token : String) -> Bool =
  #| (base, token) => globalThis.__moonclawTransport.setToken(base, token)

///|
#cfg(target="js")
extern "js" fn clear_gateway_token() =
  #| () => globalThis.__moonclawTransport.clear()

///|
#cfg(target="js")
extern "js" fn gateway_transport_epoch() -> Int =
  #| () => globalThis.__moonclawTransport?.epoch() || 0

///|
fn gateway_owned_dispatch(dispatch : Dispatch[Msg]) -> Dispatch[Msg] {
  let epoch = gateway_transport_epoch()
  @cmd.Emit(msg => {
    if gateway_transport_epoch() == epoch {
      dispatch(msg)
    } else {
      @rabbita.none
    }
  })
}

///|
#cfg(target="js")
extern "js" fn cancel_artifact_download() =
  #| () => globalThis.__moonclawTransport?.cancel()

///|
#cfg(target="js")
extern "js" fn artifact_download_ticket() -> Int =
  #| () => globalThis.__moonclawTransport.downloadEpoch()

///|
#cfg(target="js")
extern "js" fn browser_download_artifact(
  base : String,
  run : String,
  id : String,
  ticket : Int,
) -> @js.Promise =
  #| (base, run, id, ticket) => globalThis.__moonclawTransport.download(base, run, id, ticket)

///|
fn download_artifact(
  dispatch : Dispatch[Msg],
  model : Model,
  id : String,
) -> (Cmd, Model) {
  if model.artifact_download_pending is Some(_) {
    return (@rabbita.none, model)
  }
  let snapshot = if model.route is Cowork {
    model.cowork_linked_snapshot
  } else {
    model.snapshot
  }
  guard snapshot is Some(snapshot) && snapshot.artifacts.any(a => a.id == id) else {
    return (
      @rabbita.none,
      {
        ..model,
        artifact_download_notice: Some(
          "Refresh the selected run before downloading this artifact.",
        ),
      },
    )
  }
  let owns_snapshot = match model.route {
    Cowork =>
      model.cowork_detail is Some(detail) &&
      model.selected_cowork_session_key == Some(detail.session.session_key) &&
      detail.linked_run is Some(run) &&
      run.id == snapshot.run.id
    Run(run_id) | RunCanvas(run_id) =>
      snapshot.run.id == run_id && model.selected_run_id == Some(run_id)
    _ => model.selected_run_id == Some(snapshot.run.id)
  }
  guard owns_snapshot else {
    return (
      @rabbita.none,
      {
        ..model,
        artifact_download_notice: Some(
          "Wait for this run’s retained artifacts to load, then retry.",
        ),
      },
    )
  }
  let generation = model.artifact_download_generation + 1
  let ticket = artifact_download_ticket()
  let command = @rabbita.perform(
    result => dispatch(ArtifactDownloadFinished(generation, result)),
    fn() noraise {
      parse_browser_copy_result(
        wait_browser_value_json(
          browser_download_artifact(
            model.gateway_base,
            snapshot.run.id,
            id,
            ticket,
          ),
        ),
      )
    },
  )
  (
    command,
    {
      ..model,
      artifact_download_generation: generation,
      artifact_download_pending: Some(id),
      artifact_download_notice: Some("Downloading retained artifact…"),
    },
  )
}

///|
fn invalidate_artifact_download(model : Model) -> Model {
  cancel_artifact_download()
  {
    ..model,
    artifact_download_generation: model.artifact_download_generation + 1,
    artifact_download_pending: None,
    artifact_download_notice: None,
  }
}

///|
fn render_gateway_access(dispatch : Dispatch[Msg], model : Model) -> Html {
  div([
    p(
      class="muted",
      "Enter this gateway’s token to use protected API requests. It stays in this tab’s memory and is cleared on reload or gateway change.",
    ),
    input(
      input_type=Password,
      auto_complete=Off,
      value=model.gateway_token_draft,
      placeholder="Gateway token",
      attrs=@html.Attrs::build().aria_label("Gateway token"),
      on_input=value => dispatch(SetGatewayTokenDraft(value)),
    ),
    button(on_click=dispatch(ApplyGatewayToken), "Use token"),
    button(on_click=dispatch(ClearGatewayToken), "Clear token"),
    match model.gateway_token_notice {
      Some(message) => p(message)
      None => nothing
    },
  ])
}
