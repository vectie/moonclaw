///|
pub(all) enum CapabilityStatus {
  Available
  Planned
  Missing
} derive(ToJson, FromJson, Show, Eq)

///|
pub(all) struct CapabilityRecord {
  id : String
  family : String
  status : CapabilityStatus
  preferred_template : String?
  fallback_template : String?
} derive(ToJson, FromJson, Show)

///|
fn registered_capabilities() -> Array[CapabilityRecord] {
  [
    CapabilityRecord::{
      id: "research.arxiv_sync",
      family: "research",
      status: Available,
      preferred_template: Some("research.topic_watch"),
      fallback_template: Some("generic.analysis"),
    },
    CapabilityRecord::{
      id: "research.paper_fetch",
      family: "research",
      status: Available,
      preferred_template: Some("research.topic_watch"),
      fallback_template: Some("generic.analysis"),
    },
    CapabilityRecord::{
      id: "research.paper_parse",
      family: "research",
      status: Available,
      preferred_template: Some("research.topic_watch"),
      fallback_template: Some("generic.analysis"),
    },
    CapabilityRecord::{
      id: "research.paper_analyze",
      family: "research",
      status: Available,
      preferred_template: Some("research.topic_watch"),
      fallback_template: Some("generic.analysis"),
    },
    CapabilityRecord::{
      id: "analysis.plan",
      family: "generic",
      status: Available,
      preferred_template: Some("generic.analysis"),
      fallback_template: Some("generic.analysis"),
    },
    CapabilityRecord::{
      id: "analysis.execute",
      family: "generic",
      status: Available,
      preferred_template: Some("generic.analysis"),
      fallback_template: Some("generic.analysis"),
    },
    CapabilityRecord::{
      id: "analysis.report",
      family: "generic",
      status: Available,
      preferred_template: Some("generic.analysis"),
      fallback_template: Some("generic.analysis"),
    },
    CapabilityRecord::{
      id: "analysis.summarize",
      family: "generic",
      status: Available,
      preferred_template: Some("generic.analysis"),
      fallback_template: Some("generic.analysis"),
    },
    CapabilityRecord::{
      id: "workflow.delegate",
      family: "generic",
      status: Available,
      preferred_template: Some("generic.delegated"),
      fallback_template: Some("generic.analysis"),
    },
  ]
}

///|
pub fn capability_registry() -> Array[CapabilityRecord] {
  registered_capabilities()
}

///|
pub fn capability_record(id : String) -> CapabilityRecord? {
  for capability in registered_capabilities() {
    if capability.id == id {
      return Some(capability)
    }
  }
  None
}

///|
pub fn capability_available(id : String) -> Bool {
  match capability_record(id) {
    Some(capability) => capability.status is Available
    None => false
  }
}

///|
pub fn preferred_templates_for_capabilities(
  ids : Array[String],
) -> Array[String] {
  let templates : Array[String] = []
  for id in ids {
    match capability_record(id) {
      Some(capability) =>
        match capability.preferred_template {
          Some(template) if !template.is_blank() &&
            !templates.contains(template) => templates.push(template)
          _ => ()
        }
      None => ()
    }
  }
  templates
}

///|
pub fn missing_capabilities(ids : Array[String]) -> Array[String] {
  ids.filter(fn(id) { !capability_available(id) })
}
