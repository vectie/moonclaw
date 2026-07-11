///|
pub async fn start(args : ArrayView[String]) -> Unit {
  match args {
    ["validate", input_path, output_path] => {
      let text = @fsx.read_file(input_path) catch {
        error => {
          println("MoonClaw evidence read failed: \{error}")
          return
        }
      }
      let parsed = @json.parse(text) catch {
        error => {
          println("MoonClaw evidence parse failed: \{error}")
          return
        }
      }
      let dossier : @evidence_contract.EvidenceDossier = @json.from_json(
        parsed,
      ) catch {
        error => {
          println("MoonClaw evidence contract failed: \{error}")
          return
        }
      }
      let receipt = @evidence_contract.validate_dossier(dossier)
      let rendered = receipt.to_json().stringify(indent=2) + "\n"
      @fsx.write_to_file(output_path, rendered) catch {
        error => {
          println("MoonClaw evidence write failed: \{error}")
          return
        }
      }
      println(rendered)
    }
    _ =>
      println("Usage: moonclaw evidence validate <dossier.json> <receipt.json>")
  }
}
