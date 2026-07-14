///|
/// Lists available model names provided by the daemon's model registry.
///
/// Endpoint: GET /v1/models
///
/// Response:
/// - 200 OK: JSON `{ "models": [{ "name": String }] }`.
async fn Daemon::list_models(self : Daemon, w : @httpx.ResponseWriter) -> Unit {
  let catalog = self.models.models()
  let response = mooncode_model_listing_json(catalog.get(0), catalog)
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(response.stringify())
}

///|
fn mooncode_model_listing_json(
  default_model : @model.Model?,
  catalog : ArrayView[@model.Model],
) -> Json {
  let models : Array[Json] = []
  let seen : Map[String, Bool] = {}
  let default_name = match default_model {
    Some(model) => {
      let selector = model.selector()
      seen[selector] = true
      models.push({ "name": selector, "default": true })
      selector
    }
    None => ""
  }
  for model in catalog {
    let selector = model.selector()
    if !seen.contains(selector) {
      seen[selector] = true
      models.push({ "name": selector, "default": false })
    }
  }
  {
    "models": Json::array(models),
    "default_model": default_name,
    "ready": default_name != "",
  }
}
