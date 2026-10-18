///|
// Preserve the established public Show text without deprecated container Show.
fn[T : Show] feed_show_optional(value : T?) -> String {
  match value {
    None => "None"
    Some(value) => "Some(\{value})"
  }
}

///|
fn[T : Show] feed_show_array(values : Array[T]) -> String {
  "[" + values.map(value => "\{value}").join(", ") + "]"
}

///|
fn feed_show_json_array(values : Array[Json]) -> String {
  "[" + values.map(feed_show_json).join(", ") + "]"
}

///|
fn feed_show_json(value : Json) -> String {
  match value {
    Null => "Null"
    True => "True"
    False => "False"
    Number(value, repr~) =>
      "Number(\{value}" +
      (match repr {
        None => ""
        Some(repr) => ", repr=Some(\{repr})"
      }) +
      ")"
    String(value) => "String(\{value})"
    Array(values) => "Array(" + feed_show_json_array(values) + ")"
    Object(fields) => {
      let parts : Array[String] = []
      for key, value in fields {
        parts.push(key + ": " + feed_show_json(value))
      }
      "Object({" + parts.join(", ") + "})"
    }
  }
}
