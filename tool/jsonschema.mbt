///|
#derive(Eq, Debug)
pub(all) struct JsonSchema(Json)

///|
pub fn JsonSchema::from_json(schema : Json) -> JsonSchema {
  JsonSchema(schema)
}

///|
pub impl ToJson for JsonSchema with fn to_json(self : JsonSchema) -> Json {
  let JsonSchema(schema) = self
  schema
}

///|
pub extend JsonSchema with Eq::{not_equal, equal}

///|
pub extend JsonSchema with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend JsonSchema with ToJson::{to_json}
