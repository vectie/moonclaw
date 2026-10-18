///|
async test "configured Loader reader preserves reload and scope while propagating denial" {
  let paths : Array[String] = []
  let fixture = @model.Model::new(
    name="fixture",
    model_name="fixture-model",
    api_key="synthetic",
    base_url="http://127.0.0.1:1",
    safe_zone_tokens=1000,
  )
  let reader : async (StringView) -> String? = path => {
    paths.push(path.to_owned())
    if path.has_suffix("models/models.json") {
      Some(Json([fixture.to_json()]).stringify())
    } else {
      None
    }
  }
  let loader = @model.Loader::new(
    home="/fixture-home",
    cwd="/fixture-cwd",
    resource_reader=reader,
  )
  assert_true(
    loader.get_model(name="fixture") is Some(model) && model.name == "fixture",
  )
  assert_true(paths.any(path => path.has_prefix("/fixture-home/")))
  assert_true(paths.any(path => path.has_prefix("/fixture-cwd/")))
  let denied = Ok(
    loader.with_resource_reader(_ => fail("synthetic resource denial")),
  ) catch {
    error => Err(error)
  }
  assert_true(denied is Err(_))
}
