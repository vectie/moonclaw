///|
pub struct RegisteredResourceProvider {
  name : String
  title : String
  description : String
  kind : String
  endpoint : String?
  docs_uri : String?
  capabilities : Array[String]
  metadata : Json
} derive(ToJson, Debug)

///|
pub fn RegisteredResourceProvider::new(
  name~ : String,
  title? : String = name,
  description? : String = "",
  kind? : String = "generic",
  endpoint? : String? = None,
  docs_uri? : String? = None,
  capabilities? : Array[String] = [],
  metadata? : Json = {},
) -> RegisteredResourceProvider {
  {
    name: name.trim().to_owned(),
    title: title.trim().to_owned(),
    description: description.trim().to_owned(),
    kind: kind.trim().to_owned(),
    endpoint: endpoint.map(fn(value) { value.trim().to_owned() }),
    docs_uri: docs_uri.map(fn(value) { value.trim().to_owned() }),
    capabilities,
    metadata,
  }
}

///|
pub impl @json.FromJson for RegisteredResourceProvider with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> RegisteredResourceProvider raise @json.JsonDecodeError {
  let object = @jsonx.as_object(json, path~)
  let name : String = object.required("name", path~)
  let title : String = object.optional("title", path~).unwrap_or(name)
  let description : String = object.optional("description", path~).unwrap_or("")
  let kind : String = object.optional("kind", path~).unwrap_or("generic")
  let endpoint : String? = object.optional("endpoint", path~)
  let docs_uri : String? = object.optional("docs_uri", path~)
  let capabilities : Array[String] = object
    .optional("capabilities", path~)
    .unwrap_or([])
  let metadata : Json = object.optional("metadata", path~).unwrap_or({})
  RegisteredResourceProvider::new(
    name~,
    title~,
    description~,
    kind~,
    endpoint~,
    docs_uri~,
    capabilities~,
    metadata~,
  )
}

///|
fn provider_manifest_candidates(cwd : String, home : String?) -> Array[String] {
  let candidates : Array[String] = []
  match home {
    Some(home) =>
      candidates.push(
        @moonsuite.product_artifact_for_workspace_root(
          home, "moonclaw", "providers.json",
        ),
      )
    None => ()
  }
  let ancestry : Array[String] = []
  let mut dir = @pathx.normalize(cwd)
  while true {
    ancestry.push(
      @moonsuite.product_artifact_for_workspace_root(
        dir, "moonclaw", "providers.json",
      ),
    )
    let parent : String = [..@pathx.dirname(dir)]
    if parent == dir {
      break
    }
    dir = parent
  }
  let mut index = ancestry.length()
  while index > 0 {
    index -= 1
    candidates.push(ancestry[index])
  }
  candidates
}

///|
fn parse_provider_manifest(
  path : String,
  text : String,
) -> Array[RegisteredResourceProvider] raise {
  let json = @json.parse(text) catch {
    error => fail("invalid provider manifest \{path}: \{error}")
  }
  match json {
    Array(items) =>
      items.map(item => {
        let provider : RegisteredResourceProvider = @json.from_json(item) catch {
          error => fail("invalid provider entry in \{path}: \{error}")
        }
        provider
      })
    { "providers": Array(items), .. } =>
      items.map(item => {
        let provider : RegisteredResourceProvider = @json.from_json(item) catch {
          error => fail("invalid provider entry in \{path}: \{error}")
        }
        provider
      })
    _ =>
      fail(
        "invalid provider manifest \{path}: expected array or {\"providers\": [...] }",
      )
  }
}

///|
pub async fn load_resource_providers(
  cwd : String,
  home? : String?,
) -> Array[RegisteredResourceProvider] {
  let resolved_home = home.unwrap_or(None)
  let providers_by_name : Map[String, RegisteredResourceProvider] = {}
  let order : Array[String] = []
  for candidate in provider_manifest_candidates(cwd, resolved_home) {
    if !(@fsx.exists(candidate) catch { _ => false }) {
      continue
    }
    let text = @fsx.read_file(candidate) catch { _ => continue }
    let providers = parse_provider_manifest(candidate, text) catch { _ => [] }
    for provider in providers {
      guard !provider.name.is_blank() else { continue }
      if !providers_by_name.contains(provider.name) {
        order.push(provider.name)
      }
      providers_by_name.set(provider.name, provider)
    }
  }
  let resolved : Array[RegisteredResourceProvider] = []
  for name in order {
    match providers_by_name.get(name) {
      Some(provider) => resolved.push(provider)
      None => ()
    }
  }
  resolved
}

///|
pub async fn find_resource_provider(
  cwd : String,
  name : String,
  home? : String?,
) -> RegisteredResourceProvider? {
  let resolved_home = home.unwrap_or(None)
  let needle = name.trim().to_owned()
  if needle.is_blank() {
    return None
  }
  for provider in load_resource_providers(cwd, home=resolved_home) {
    if provider.name == needle {
      return Some(provider)
    }
  }
  None
}
