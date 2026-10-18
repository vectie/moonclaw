///|
pub struct ModelConfig {
  id : String
  name : String?
  reasoning : Bool?
  input : Array[String]?
  cost : CostConfig?
  contextWindow : Int32?
  maxTokens : Int32?
} derive(ToJson, Debug)

///|
pub struct CostConfig {
  input : Double?
  output : Double?
  cacheRead : Double?
  cacheWrite : Double?
} derive(ToJson, Debug)

///|
pub struct ProviderConfig {
  baseUrl : String?
  api : String?
  models : Array[ModelConfig]
  apiKey : String?
} derive(ToJson, Debug)

///|
pub struct ProvidersFile {
  providers : Map[String, ProviderConfig]
} derive(ToJson, Debug)

///|
pub extend ModelConfig with ToJson::{to_json}

///|
pub extend ModelConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CostConfig with ToJson::{to_json}

///|
pub extend CostConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ProviderConfig with ToJson::{to_json}

///|
pub extend ProviderConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ProvidersFile with ToJson::{to_json}

///|
pub extend ProvidersFile with @moonbitlang/core/debug.Debug::{to_repr}
