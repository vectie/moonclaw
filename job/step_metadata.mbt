///|
fn metadata_with_step_metadata(metadata : Json, key : String) -> Json? {
  match metadata {
    Object(obj) =>
      match obj.get(key) {
        Some(value) => Some(value)
        None =>
          match obj.get("step_metadata") {
            Some(nested) => metadata_with_step_metadata(nested, key)
            None =>
              match obj.get("metadata") {
                Some(nested) => metadata_with_step_metadata(nested, key)
                None => None
              }
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

///|
fn metadata_bool_with_step_metadata_option(
  metadata : Json,
  key : String,
) -> Bool? {
  match metadata_with_step_metadata(metadata, key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
fn metadata_int_with_step_metadata_option(
  metadata : Json,
  key : String,
) -> Int? {
  match metadata_with_step_metadata(metadata, key) {
    Some(Number(value, ..)) => Some(value.to_int())
    _ => None
  }
}

///|
fn waiting_for_input_disabled_from_metadata(metadata : Json) -> Bool? {
  metadata_bool_with_step_metadata_option(metadata, "disable_waiting_for_input")
}

///|
fn best_effort_on_missing_input_from_metadata(metadata : Json) -> Bool? {
  metadata_bool_with_step_metadata_option(
    metadata, "best_effort_on_missing_input",
  )
}
