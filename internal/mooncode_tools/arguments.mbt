///|
/// Validate the JSON Schema subset used by the native catalog, not permissions.
pub fn arguments_error(
  schema : Json,
  value : Json,
  path~ : String = "arguments",
) -> String? {
  let kind = string_field(schema, "type")
  let valid = match (kind, value) {
    ("object", Object(_))
    | ("array", Array(_))
    | ("string", String(_))
    | ("boolean", True)
    | ("boolean", False) => true
    ("integer", Number(n, ..)) =>
      n >= -2147483648.0 && n <= 2147483647.0 && n.to_int().to_double() == n
    ("", _) => true
    _ => false
  }
  if !valid {
    return Some("\{path} must be \{kind}")
  }
  if schema is { "enum": Array(values), .. } && !values.contains(value) {
    return Some("\{path} is not an allowed value")
  }
  if schema is { "minimum": Number(minimum, ..), .. } &&
    value is Number(n, ..) &&
    n < minimum {
    return Some("\{path} must be at least \{minimum}")
  }
  match value {
    Object(fields) => {
      let properties = match schema {
        { "properties": Object(fields), .. } => fields
        _ => Map([])
      }
      if schema is { "required": Array(required), .. } {
        for key in required {
          if key is String(key) && !fields.contains(key) {
            return Some("\{path}.\{key} is required")
          }
        }
      }
      for key, value in fields {
        match properties.get(key) {
          Some(property) =>
            if arguments_error(property, value, path="\{path}.\{key}")
              is Some(error) {
              return Some(error)
            }
          None =>
            if schema is { "additionalProperties": false, .. } {
              return Some("\{path}.\{key} is not supported")
            }
        }
      }
    }
    Array(values) =>
      if schema is { "items": item, .. } {
        for index, value in values {
          if arguments_error(item, value, path="\{path}[\{index}]")
            is Some(error) {
            return Some(error)
          }
        }
      }
    _ => ()
  }
  None
}
