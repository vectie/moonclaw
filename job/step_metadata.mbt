///|
fn metadata_with_step_metadata(metadata : Json, key : String) -> Json? {
  match metadata {
    Object(obj) =>
      match obj.get(key) {
        Some(value) => Some(value)
        None =>
          match obj.get("step_metadata") {
            Some(nested) => metadata_with_step_metadata(nested, key)
            None => None
          }
      }
    _ => None
  }
}

///|
fn metadata_bool_with_step_metadata(
  metadata : Json,
  key : String,
  fallback : Bool,
) -> Bool {
  match metadata_with_step_metadata(metadata, key) {
    Some(True) => true
    Some(False) => false
    _ => fallback
  }
}

///|
fn analysis_adaptive_disabled(config : AnalysisStepConfig) -> Bool {
  metadata_bool_with_step_metadata(config.metadata, "disable_adaptive", false)
}
