///|
/// Keep daemon command tests independent of a developer's provider login.
async fn mooncode_test_model_loader(book_root : String) -> @model.Loader {
  let model = @model.Model::new(
    api_key="fixture",
    base_url="http://127.0.0.1:1/v1",
    name="fixture/mooncode",
    model_name="fixture-mooncode",
    safe_zone_tokens=131072,
  )
  let models_path = @moonsuite.product_artifact_for_workspace_root(
    book_root, "moonclaw", "models/models.json",
  )
  @fsx.make_directory(
    @pathx.dirname(models_path),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(models_path, [model].to_json().stringify())
  @model.Loader::new(home=book_root, cwd=book_root)
}
