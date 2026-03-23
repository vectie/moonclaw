///|
pub(all) struct JobProfileMatchRules {
  any : Array[String]?
  all : Array[String]?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobProfileStep {
  id : String
  title : String
  kind : String
  prompt_template : String?
  request_template : String?
  child_profile : String?
  execution_mode : String?
  execution_target : String?
  include_parent_outputs : Bool?
  max_depth : Int?
  metadata : Json?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobProfile {
  id : String
  family : String
  label : String?
  role : String?
  priority : Int
  tags : Array[String]
  match_rules : JobProfileMatchRules?
  steps : Array[JobProfileStep]
  metadata : Json
} derive(ToJson, FromJson, Show)

///|
struct JobProfileConfigPayload {
  family : String?
  label : String?
  role : String?
  priority : Int?
  tags : Array[String]?
  match_rules : JobProfileMatchRules?
  steps : Array[JobProfileStep]?
  metadata : Json?
} derive(ToJson, FromJson, Show)

///|
fn parse_string_array(value : Json) -> Array[String]? {
  match value {
    Array(items) => {
      let strings : Array[String] = []
      for item in items {
        match item {
          String(value) => strings.push(value)
          _ => continue
        }
      }
      Some(strings)
    }
    _ => None
  }
}

///|
fn parse_job_profile_match_rules(value : Json) -> JobProfileMatchRules? {
  match value {
    Object(obj) =>
      Some(JobProfileMatchRules::{
        any: match obj.get("any") {
          Some(value) => parse_string_array(value)
          None => None
        },
        all: match obj.get("all") {
          Some(value) => parse_string_array(value)
          None => None
        },
      })
    _ => None
  }
}

///|
fn parse_job_profile_steps(value : Json) -> Array[JobProfileStep]? {
  match value {
    Array(items) => {
      let steps : Array[JobProfileStep] = []
      for item in items {
        match item {
          Object(obj) => {
            let id = match obj.get("id") {
              Some(String(value)) => value
              _ => continue
            }
            let title = match obj.get("title") {
              Some(String(value)) => value
              _ => continue
            }
            let kind = match obj.get("kind") {
              Some(String(value)) => value
              _ => continue
            }
            let prompt_template = match obj.get("prompt_template") {
              Some(String(value)) => Some(value)
              _ => None
            }
            let request_template = match obj.get("request_template") {
              Some(String(value)) => Some(value)
              _ => None
            }
            let child_profile = match obj.get("child_profile") {
              Some(String(value)) => Some(value)
              _ => None
            }
            let execution_mode = match obj.get("execution_mode") {
              Some(String(value)) => Some(value)
              _ => None
            }
            let execution_target = match obj.get("execution_target") {
              Some(String(value)) => Some(value)
              _ => None
            }
            let include_parent_outputs = match
              obj.get("include_parent_outputs") {
              Some(True) => Some(true)
              Some(False) => Some(false)
              _ => None
            }
            let max_depth = match obj.get("max_depth") {
              Some(Number(value, ..)) => Some(value.to_int())
              _ => None
            }
            let metadata = obj.get("metadata")
            steps.push(JobProfileStep::{
              id,
              title,
              kind,
              prompt_template,
              request_template,
              child_profile,
              execution_mode,
              execution_target,
              include_parent_outputs,
              max_depth,
              metadata,
            })
          }
          _ => continue
        }
      }
      Some(steps)
    }
    _ => None
  }
}

///|
fn job_profile_config_path_candidates(cwd : String) -> Array[String] {
  [cwd |> @pathx.join("moonclaw.jobs.json")]
}

///|
async fn load_job_profiles_json(home : String, cwd : String) -> Json? {
  let mut loaded : Json? = None
  let _ = home
  for path in job_profile_config_path_candidates(cwd) {
    let exists = @fsx.exists(path) catch { _ => false }
    if !exists {
      continue
    }
    let text = @fsx.read_file(path) catch { _ => continue }
    let json = @json.parse(text) catch { _ => continue }
    loaded = Some(json)
  }
  loaded
}

///|
fn payload_from_raw_profile(raw : Json) -> JobProfileConfigPayload? {
  match raw {
    Object(obj) => {
      let family = match obj.get("family") {
        Some(String(value)) => Some(value)
        _ => None
      }
      let label = match obj.get("label") {
        Some(String(value)) => Some(value)
        _ => None
      }
      let role = match obj.get("role") {
        Some(String(value)) => Some(value)
        _ => None
      }
      let priority = match obj.get("priority") {
        Some(Number(value, ..)) => Some(value.to_int())
        _ => None
      }
      let tags = match obj.get("tags") {
        Some(value) => parse_string_array(value)
        None => None
      }
      let match_rules = match obj.get("match_rules") {
        Some(value) => parse_job_profile_match_rules(value)
        None =>
          match obj.get("match") {
            Some(value) => parse_job_profile_match_rules(value)
            None => None
          }
      }
      let steps = match obj.get("steps") {
        Some(value) => parse_job_profile_steps(value)
        None => None
      }
      let metadata = match obj.get("metadata") {
        Some(value) => Some(value)
        None => None
      }
      Some(JobProfileConfigPayload::{
        family,
        label,
        role,
        priority,
        tags,
        match_rules,
        steps,
        metadata,
      })
    }
    _ => None
  }
}

///|
fn configured_job_profiles(json : Json?) -> Array[JobProfile] {
  match json {
    Some({ "jobs": { "profiles": Object(profiles), .. }, .. }) => {
      let loaded : Array[JobProfile] = []
      for id, raw in profiles {
        let payload = match payload_from_raw_profile(raw) {
          Some(payload) => payload
          None => continue
        }
        loaded.push(JobProfile::{
          id,
          family: payload.family.unwrap_or(id),
          label: payload.label,
          role: payload.role,
          priority: payload.priority.unwrap_or(0),
          tags: payload.tags.unwrap_or([]),
          match_rules: payload.match_rules,
          steps: payload.steps.unwrap_or([]),
          metadata: payload.metadata.unwrap_or({}),
        })
      }
      loaded
    }
    _ => []
  }
}

///|
fn normalized_profile_term(term : String) -> String {
  term.trim().to_string().to_lower()
}

///|
fn contains_all_terms(text : String, terms : Array[String]) -> Bool {
  for term in terms {
    let normalized = normalized_profile_term(term)
    if normalized.is_blank() {
      continue
    }
    if !text.contains(normalized) {
      return false
    }
  }
  true
}

///|
fn contains_any_term(text : String, terms : Array[String]) -> Bool {
  for term in terms {
    let normalized = normalized_profile_term(term)
    if normalized.is_blank() {
      continue
    }
    if text.contains(normalized) {
      return true
    }
  }
  false
}

///|
fn profile_matches_request(profile : JobProfile, request_text : String) -> Bool {
  match profile.match_rules {
    Some(matcher) => {
      let normalized = request_text.to_lower()
      let all_ok = match matcher.all {
        Some(terms) => contains_all_terms(normalized, terms)
        None => true
      }
      let any_ok = match matcher.any {
        Some(terms) => contains_any_term(normalized, terms)
        None => true
      }
      all_ok && any_ok
    }
    None => false
  }
}

///|
pub async fn list_job_profiles(
  home : String,
  cwd : String,
) -> Array[JobProfile] {
  configured_job_profiles(load_job_profiles_json(home, cwd))
}

///|
pub async fn load_job_profile(
  home : String,
  cwd : String,
  family : String,
) -> JobProfile? {
  let target = family.trim().to_string()
  if target.is_blank() {
    return None
  }
  for profile in list_job_profiles(home, cwd) {
    if profile.id == target || profile.family == target {
      return Some(profile)
    }
  }
  None
}

///|
pub async fn suggest_job_profile_family(
  request_text : String,
  home : String,
  cwd : String,
) -> String? {
  let mut best : JobProfile? = None
  for profile in list_job_profiles(home, cwd) {
    if !profile_matches_request(profile, request_text) {
      continue
    }
    best = match best {
      Some(current) if current.priority >= profile.priority => Some(current)
      _ => Some(profile)
    }
  }
  best.map(fn(profile) { profile.family })
}
