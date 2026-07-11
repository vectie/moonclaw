///|
pub fn ready_message(base_url : String) -> String {
  "MoonGate available at \{base_url}; MoonClaw routing and usage/statistics bridge enabled"
}

///|
pub fn unavailable_message(base_url : String, error : String) -> String {
  "MoonGate unavailable at \{base_url}; continuing as standalone MoonClaw: \{error}"
}

///|
pub async fn print_status() -> Unit {
  let client = @moonstat.discover()
  match client.health() {
    Ok(_) => @stdio.stdout.write("\{ready_message(client.base_url())}\n")
    Err(error) =>
      @stdio.stdout.write("\{unavailable_message(client.base_url(), error)}\n")
  }
}
