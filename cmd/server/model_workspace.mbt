///|
/// Parse the explicit model-resolution root without changing execution cwd.
fn server_model_workspace_arguments(
  args : ArrayView[String],
) -> (String?, Array[String]) raise {
  let mut workspace : String? = None
  let remaining : Array[String] = []
  let mut index = 0
  while index < args.length() {
    if args[index] == "--model-workspace" {
      guard workspace is None &&
        args.get(index + 1) is Some(root) &&
        @pathx.is_absolute(root) &&
        root != "/" &&
        !root.contains("\u0000") else {
        fail("--model-workspace requires one absolute non-root path")
      }
      workspace = Some(root)
      index += 2
    } else {
      remaining.push(args[index])
      index += 1
    }
  }
  (workspace, remaining)
}

///|
async fn server_resolve_model(
  home : String,
  name : String?,
  model_workspace : String?,
  resolve~ : async (String, String?, String?) -> @model.Model?,
) -> @model.Model? {
  resolve(home, model_workspace, name)
}
