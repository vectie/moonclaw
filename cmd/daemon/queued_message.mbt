///|
#derive(ToJson, @json.FromJson)
priv struct QueuedMessage {
  id : String
  message : Json
}
