///|
pub(all) struct TemplateDefinition {
  id : String
  family : String
  summary : String
  required_capabilities : Array[String]
  default_skills : Array[String]
  fallback_template : String?
} derive(ToJson, FromJson, Show)

///|
fn registered_templates() -> Array[TemplateDefinition] {
  [
    TemplateDefinition::{
      id: "research.topic_watch",
      family: "research",
      summary: "Track a topic, sync papers, summarize findings, and deliver a report.",
      required_capabilities: [
        "research.arxiv_sync", "research.paper_fetch", "research.paper_parse", "research.paper_analyze",
      ],
      default_skills: [
        "research-paper-summary", "research-novelty-review", "research-report-writer",
      ],
      fallback_template: Some("generic.analysis"),
    },
    TemplateDefinition::{
      id: "research.topic_review",
      family: "research",
      summary: "Review a research topic with retrieval, analysis, and final synthesis.",
      required_capabilities: [
        "research.arxiv_sync", "research.paper_parse", "research.paper_analyze",
      ],
      default_skills: ["research-paper-summary", "research-report-writer"],
      fallback_template: Some("generic.analysis"),
    },
    TemplateDefinition::{
      id: "research.delegated_review",
      family: "research",
      summary: "Research workflow that syncs topic context and delegates deeper subtasks to child workflows.",
      required_capabilities: [
        "research.arxiv_sync", "workflow.delegate", "analysis.report",
      ],
      default_skills: [
        "research-paper-summary", "research-novelty-review", "research-report-writer",
      ],
      fallback_template: Some("generic.delegated"),
    },
    TemplateDefinition::{
      id: "generic.analysis",
      family: "generic",
      summary: "Generic plan/execute/verify/deliver workflow.",
      required_capabilities: [
        "analysis.plan", "analysis.execute", "analysis.report",
      ],
      default_skills: [],
      fallback_template: None,
    },
    TemplateDefinition::{
      id: "generic.delegated",
      family: "generic",
      summary: "Delegated workflow that expands broad requests into child workflows per subtask.",
      required_capabilities: [
        "analysis.plan", "workflow.delegate", "analysis.report",
      ],
      default_skills: [],
      fallback_template: Some("generic.analysis"),
    },
    TemplateDefinition::{
      id: "generic.tool_workflow",
      family: "generic",
      summary: "Generic workflow for requests that need tool-assisted collection or execution before delivery.",
      required_capabilities: [
        "analysis.plan", "analysis.execute", "analysis.report",
      ],
      default_skills: [],
      fallback_template: Some("generic.analysis"),
    },
  ]
}

///|
pub fn template_registry() -> Array[TemplateDefinition] {
  registered_templates()
}

///|
pub fn template_definition(id : String) -> TemplateDefinition? {
  for template in registered_templates() {
    if template.id == id {
      return Some(template)
    }
  }
  None
}

///|
pub fn template_default_skills(id : String) -> Array[String] {
  template_definition(id)
  .map(fn(template) { template.default_skills })
  .unwrap_or([])
}
