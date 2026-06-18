///|
pub struct ModelConfig {
  id : String
  name : String?
  reasoning : Bool?
  input : Array[String]?
  cost : CostConfig?
  contextWindow : Int?
  maxTokens : Int?
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
