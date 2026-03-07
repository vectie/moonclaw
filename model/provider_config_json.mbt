///|
pub impl @json.FromJson for CostConfig with from_json(
  json : Json,
  json_path : @json.JsonPath,
) -> CostConfig {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError(
      (json_path, "CostConfig::from_json: expected object"),
    )
  }
  let input : Double? = {
    guard obj.get("input") is Some(v) else { None }
    Some(@json.from_json(v, path=json_path.add_key("input")))
  }
  let output : Double? = {
    guard obj.get("output") is Some(v) else { None }
    Some(@json.from_json(v, path=json_path.add_key("output")))
  }
  let cacheRead : Double? = {
    guard obj.get("cacheRead") is Some(v) else { None }
    Some(@json.from_json(v, path=json_path.add_key("cacheRead")))
  }
  let cacheWrite : Double? = {
    guard obj.get("cacheWrite") is Some(v) else { None }
    Some(@json.from_json(v, path=json_path.add_key("cacheWrite")))
  }
  { input, output, cacheRead, cacheWrite }
}

///|
pub impl @json.FromJson for ModelConfig with from_json(
  json : Json,
  json_path : @json.JsonPath,
) -> ModelConfig {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError(
      (json_path, "ModelConfig::from_json: expected object"),
    )
  }
  let id : String = {
    guard obj.get("id") is Some(v) else {
      raise @json.JsonDecodeError(
        (json_path, "ModelConfig::from_json: missing 'id' field"),
      )
    }
    @json.from_json(v, path=json_path.add_key("id"))
  }
  let name : String? = {
    guard obj.get("name") is Some(v) else { None }
    Some(@json.from_json(v, path=json_path.add_key("name")))
  }
  let reasoning : Bool? = {
    guard obj.get("reasoning") is Some(v) else { None }
    Some(@json.from_json(v, path=json_path.add_key("reasoning")))
  }
  let input : Array[String]? = {
    guard obj.get("input") is Some(v) else { None }
    Some(@json.from_json(v, path=json_path.add_key("input")))
  }
  let cost : CostConfig? = {
    guard obj.get("cost") is Some(v) else { None }
    Some(@json.from_json(v, path=json_path.add_key("cost")))
  }
  let contextWindow : Int? = {
    guard obj.get("contextWindow") is Some(v) else { None }
    Some(@json.from_json(v, path=json_path.add_key("contextWindow")))
  }
  let maxTokens : Int? = {
    guard obj.get("maxTokens") is Some(v) else { None }
    Some(@json.from_json(v, path=json_path.add_key("maxTokens")))
  }
  { id, name, reasoning, input, cost, contextWindow, maxTokens }
}

///|
pub impl @json.FromJson for ProviderConfig with from_json(
  json : Json,
  json_path : @json.JsonPath,
) -> ProviderConfig {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError(
      (json_path, "ProviderConfig::from_json: expected object"),
    )
  }
  let baseUrl : String? = {
    guard obj.get("baseUrl") is Some(v) else { None }
    Some(@json.from_json(v, path=json_path.add_key("baseUrl")))
  }
  let api : String? = {
    guard obj.get("api") is Some(v) else { None }
    Some(@json.from_json(v, path=json_path.add_key("api")))
  }
  let models : Array[ModelConfig] = {
    guard obj.get("models") is Some(v) else {
      raise @json.JsonDecodeError(
        (json_path, "ProviderConfig::from_json: missing 'models' field"),
      )
    }
    @json.from_json(v, path=json_path.add_key("models"))
  }
  let apiKey : String? = {
    guard obj.get("apiKey") is Some(v) else { None }
    Some(@json.from_json(v, path=json_path.add_key("apiKey")))
  }
  { baseUrl, api, models, apiKey }
}

///|
pub impl @json.FromJson for ProvidersFile with from_json(
  json : Json,
  json_path : @json.JsonPath,
) -> ProvidersFile {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError(
      (json_path, "ProvidersFile::from_json: expected object"),
    )
  }
  let providers : Map[String, ProviderConfig] = {
    guard obj.get("providers") is Some(v) else {
      raise @json.JsonDecodeError(
        (json_path, "ProvidersFile::from_json: missing 'providers' field"),
      )
    }
    @json.from_json(v, path=json_path.add_key("providers"))
  }
  { providers, }
}
