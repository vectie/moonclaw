///|
fn artifact_route_hex(byte : Byte) -> Int? {
  let value = byte.to_int()
  if value >= 48 && value <= 57 {
    Some(value - 48)
  } else if value >= 65 && value <= 70 {
    Some(value - 55)
  } else if value >= 97 && value <= 102 {
    Some(value - 87)
  } else {
    None
  }
}

///|
fn artifact_route_id(segment : String) -> String? {
  let input = @encoding/utf8.encode(segment)
  let bytes : Array[Byte] = []
  let mut index = 0
  while index < input.length() {
    if input[index] == b'%' {
      guard index + 2 < input.length() else { return None }
      guard artifact_route_hex(input[index + 1]) is Some(hi) &&
        artifact_route_hex(input[index + 2]) is Some(lo) else {
        return None
      }
      bytes.push((hi * 16 + lo).to_byte())
      index += 3
    } else {
      bytes.push(input[index])
      index += 1
    }
  }
  let decoded = @encoding/utf8.decode(Bytes::from_array(bytes)) catch {
    _ => return None
  }
  if decoded == "" ||
    decoded == "." ||
    decoded == ".." ||
    decoded.contains("/") ||
    decoded.contains("\\") ||
    decoded.iter().any(c => c.to_int() < 32 || c.to_int() == 127) {
    None
  } else {
    Some(decoded)
  }
}

///|
fn artifact_download_filename(path : String) -> String {
  let parts = path.split("/").last().unwrap_or("artifact.bin").to_owned()
  let basename = parts.split("\\").last().unwrap_or("artifact.bin")
  let safe = StringBuilder()
  for char in basename {
    if char.to_int() < 32 || char.to_int() == 127 || char == '"' || char == ':' {
      safe.write_char('_')
    } else {
      safe.write_char(char)
    }
  }
  let name = safe.to_string().trim().to_owned()
  if name == "" || name == "." || name == ".." {
    "artifact.bin"
  } else {
    name
  }
}

///|
fn artifact_download_disposition(path : String) -> String {
  let name = artifact_download_filename(path)
  let encoded = StringBuilder()
  let hex = "0123456789ABCDEF"
  for byte in @encoding/utf8.encode(name) {
    let value = byte.to_int()
    if (value >= 65 && value <= 90) ||
      (value >= 97 && value <= 122) ||
      (value >= 48 && value <= 57) ||
      value == 45 ||
      value == 46 ||
      value == 95 {
      encoded.write_char(value.unsafe_to_char())
    } else {
      encoded.write_char('%')
      encoded.write_char(hex[value / 16].unsafe_to_char())
      encoded.write_char(hex[value % 16].unsafe_to_char())
    }
  }
  "attachment; filename=\"artifact.bin\"; filename*=UTF-8''" +
  encoded.to_string()
}

///|
async fn Gateway::handle_download_artifact(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  run_id : String,
  artifact_id : String,
) -> Unit {
  guard artifact_route_id(run_id) is Some(run_id) &&
    artifact_route_id(artifact_id) is Some(artifact_id) else {
    raise json_error(400, "BadRequest", {
      "error": {
        "code": "invalid_artifact_identity",
        "message": "Select an exact run and artifact ID from the run’s retained artifacts.",
      },
    })
  }
  let artifacts = @job.ArtifactStore::new(store=self.job_runtime().store())
  let artifact = match artifacts.get(artifact_id) {
    Some(artifact) if artifact.run_id == run_id => artifact
    _ =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "artifact_not_found",
          "message": "No retained artifact with this ID belongs to this run. Refresh the run and select a retained artifact.",
        },
      })
  }
  let bytes = artifacts.read_bytes(run_id, artifact_id) catch {
    _ =>
      raise json_error(409, "Conflict", {
        "error": {
          "code": "artifact_unavailable",
          "message": "Artifact content could not be read (download limit: 64 MiB). Restore the retained file or export it through the trusted operator, then retry. Work was not rerun.",
        },
      })
  }
  guard bytes is Some(bytes) else {
    raise json_error(410, "Gone", {
      "error": {
        "code": "artifact_content_missing",
        "message": "The artifact record remains, but its retained file is missing. Restore that file from a trusted backup and retry. Downloading does not rerun the job.",
      },
    })
  }
  // Always download, never execute active HTML/SVG or trust a metadata header.
  w.header().set("Content-Type", "application/octet-stream")
  w
  .header()
  .set("Content-Disposition", artifact_download_disposition(artifact.path))
  w.header().set("Cache-Control", "no-store")
  w.header().set("X-Content-Type-Options", "nosniff")
  w.write_header(200)
  w.write(bytes)
}
