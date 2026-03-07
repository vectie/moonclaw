///|
pub struct ModelConfig {
  id : String
  name : String?
  reasoning : Bool?
  input : Array[String]?
  cost : CostConfig?
  contextWindow : Int?
  maxTokens : Int?
} derive(ToJson, Show)

///|
pub struct CostConfig {
  input : Double?
  output : Double?
  cacheRead : Double?
  cacheWrite : Double?
} derive(ToJson, Show)

///|
pub struct ProviderConfig {
  baseUrl : String?
  api : String?
  models : Array[ModelConfig]
  apiKey : String?
} derive(ToJson, Show)

///|
pub struct ProvidersFile {
  providers : Map[String, ProviderConfig]
} derive(ToJson, Show)
