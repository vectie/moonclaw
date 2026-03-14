///|
fn research_test_run(job_id : String) -> JobRun {
  JobRun::{
    id: "run-research-1",
    job_id,
    trigger: TriggerSource::Manual,
    parent_run_id: None,
    parent_step_id: None,
    depth: 0,
    status: RunStatus::Pending,
    attempt: 1,
    retry_of: None,
    started_at: None,
    completed_at: None,
    summary: None,
    error: None,
  }
}

///|
async fn research_test_engine(
  root : String,
  definition : JobDefinition,
  workflow : WorkflowDefinition,
) -> WorkflowEngine {
  let runtime = RuntimeManager::new(root~)
  runtime.register_definition(definition)
  runtime.register_workflow(workflow)
  runtime.store().save_run(research_test_run(definition.id))
  WorkflowEngine::new(runtime~)
}

///|
fn fake_arxiv_client(papers : Array[ResearchPaper]) -> ArxivClient {
  ArxivClient::new(
    fetch_feed=fn(_request) {
      let entries = papers.map(fn(paper) {
        let updated_at = paper.updated_at.unwrap_or("2026-01-01T00:00:00Z")
        let published_at = paper.published_at.unwrap_or("2026-01-01T00:00:00Z")
        let author_xml = paper.authors
          .map(fn(author) { "<author><name>\{author}</name></author>" })
          .join("")
        let category_xml = paper.categories
          .map(fn(category) { "<category term=\"\{category}\" />" })
          .join("")
        let pdf_xml = match paper.pdf_url {
          Some(url) =>
            "<link title=\"pdf\" href=\"\{url}\" type=\"application/pdf\" />"
          None => ""
        }
        [
          "<entry>",
          "<id>http://arxiv.org/abs/\{paper.id}</id>",
          "<updated>\{updated_at}</updated>",
          "<published>\{published_at}</published>",
          "<title>\{paper.title}</title>",
          "<summary>\{paper.abstract_text}</summary>",
          author_xml,
          category_xml,
          pdf_xml,
          "</entry>",
        ].join("")
      })
      Ok(
        [
          "<feed>",
          "<opensearch:totalResults>\{papers.length()}</opensearch:totalResults>",
          "<opensearch:startIndex>0</opensearch:startIndex>",
          "<opensearch:itemsPerPage>\{papers.length()}</opensearch:itemsPerPage>",
          entries.join(""),
          "</feed>",
        ].join(""),
      )
    },
    fetch_pdf=fn(_url) { Ok(@encoding/utf8.encode("fake pdf bytes")) },
  )
}

///|
fn sample_paper(id : String, title : String) -> ResearchPaper {
  ResearchPaper::{
    id,
    base_id: id.split("v").map(fn(part) { part.to_string() }).collect()[0],
    version: 1,
    title,
    abstract_text: "This paper studies \{title}.",
    authors: ["Ada Lovelace", "Alan Turing"],
    categories: ["cs.AI", "cs.CL"],
    primary_category: Some("cs.AI"),
    published_at: Some("2026-01-01T00:00:00Z"),
    updated_at: Some("2026-01-02T00:00:00Z"),
    abs_url: Some("http://arxiv.org/abs/\{id}"),
    pdf_url: Some("https://arxiv.org/pdf/\{id}.pdf"),
  }
}

///|
test "parse_arxiv_feed extracts paper metadata" {
  let feed = [
    "<feed>", "<opensearch:totalResults>1</opensearch:totalResults>", "<opensearch:startIndex>0</opensearch:startIndex>",
    "<opensearch:itemsPerPage>1</opensearch:itemsPerPage>", "<entry>", "<id>http://arxiv.org/abs/2501.00001v1</id>",
    "<updated>2026-01-02T00:00:00Z</updated>", "<published>2026-01-01T00:00:00Z</published>",
    "<title>Agentic Systems</title>", "<summary>Study of agentic systems.</summary>",
    "<author><name>Ada Lovelace</name></author>", "<author><name>Alan Turing</name></author>",
    "<category term=\"cs.AI\" />", "<category term=\"cs.CL\" />", "<link title=\"pdf\" href=\"https://arxiv.org/pdf/2501.00001v1.pdf\" type=\"application/pdf\" />",
    "</entry>", "</feed>",
  ].join("")
  let parsed = parse_arxiv_feed(feed)
  inspect(parsed.total_results, content="1")
  inspect(parsed.papers.length(), content="1")
  inspect(parsed.papers[0].id, content="2501.00001v1")
  inspect(
    parsed.papers[0].authors.join(","),
    content="Ada Lovelace,Alan Turing",
  )
  inspect(parsed.papers[0].categories.join(","), content="cs.AI,cs.CL")
}

///|
async test "research topic sync persists feed and paper metadata with topic binding" {
  @fsx.with_temporary_directory("job-research-topic-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let bundle = research_topic_sync_bundle(
      job_id="job.research.topic",
      config=ResearchTopicSyncConfig::new(
        topic_id="agents",
        query="agent systems",
        title=Some("Agent Systems"),
        max_results=2,
      ),
      100,
    )
    let engine = research_test_engine(
      root,
      bundle.definition,
      bundle.workflows[0],
    )
    engine.register_handler(
      research_topic_sync_step_handler(
        runtime=engine.runtime,
        client=fake_arxiv_client([
          sample_paper("2501.00001v1", "Agentic Systems"),
          sample_paper("2501.00002v1", "Planning Agents"),
        ]),
        now=fn() { 1000 },
      ),
    )
    let result = match engine.execute_run("run-research-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    inspect(
      result.outputs
      .get("sync")
      .map(fn(output) { output.stringify().contains("paper_ids") })
      .unwrap_or(false),
      content="true",
    )
    let artifacts = engine.runtime.store().list_artifacts()
    inspect(artifacts.length(), content="5")
    inspect(
      artifacts.map(fn(artifact) { artifact.artifact_type }).join(","),
      content="research.topic.feed,research.paper.meta,research.paper.pdf,research.paper.meta,research.paper.pdf",
    )
    inspect(
      engine.runtime.store().get_chat_binding("research.topic.ask:agents")
      is Some(_),
      content="true",
    )
  })
}

///|
async test "research paper fetch handler persists paper artifacts and binding" {
  @fsx.with_temporary_directory("job-research-paper-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let workflow = WorkflowDefinition::{
      id: "workflow.research.fetch",
      kind: "research.fetch",
      steps: [
        WorkflowStepDefinition::{
          id: "fetch",
          kind: "research.paper.fetch",
          config: ResearchPaperFetchConfig::new(
            paper_id=Some("2501.00001v1"),
            max_results=1,
          ).to_json(),
          retry_policy: None,
        },
      ],
      output_bindings: ["fetch"],
    }
    let definition = JobDefinition::{
      id: "job.research.paper",
      kind: "research.paper.fetch",
      enabled: true,
      config: {},
      schedule: None,
      retry_policy: None,
      workflow_id: Some(workflow.id),
      created_at: 1,
      updated_at: 1,
      tags: ["research"],
    }
    let engine = research_test_engine(root, definition, workflow)
    engine.register_handler(
      research_paper_fetch_step_handler(
        runtime=engine.runtime,
        client=fake_arxiv_client([
          sample_paper("2501.00001v1", "Agentic Systems"),
        ]),
        now=fn() { 1000 },
      ),
    )
    let result = match engine.execute_run("run-research-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    inspect(
      result.steps
      .map(fn(step) { "\{step.step_id}:\{step.status.to_json().stringify()}" })
      .join(","),
      content="fetch:\"Succeeded\"",
    )
    let artifacts = engine.runtime.store().list_artifacts()
    inspect(artifacts.length(), content="2")
    inspect(
      artifacts.map(fn(artifact) { artifact.artifact_type }).join(","),
      content="research.paper.meta,research.paper.pdf",
    )
    inspect(
      engine.runtime.store().get_chat_binding("research.paper.ask:2501.00001v1")
      is Some(_),
      content="true",
    )
  })
}

///|
async test "research parse and analyze handlers persist derived artifacts and reports" {
  @fsx.with_temporary_directory("job-research-analyze-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let workflow = WorkflowDefinition::{
      id: "workflow.research.analyze",
      kind: "research.analyze",
      steps: [
        WorkflowStepDefinition::{
          id: "parse",
          kind: "research.paper.parse",
          config: ResearchPaperParseConfig::new(
            paper_id=Some("2501.00001v1"),
            chunk_chars=40,
          ).to_json(),
          retry_policy: None,
        },
        WorkflowStepDefinition::{
          id: "analyze",
          kind: "research.paper.analyze",
          config: ResearchPaperAnalyzeConfig::new(
            paper_id="2501.00001v1",
            analysis_kind="summary",
            policy=AnalysisPolicy::new(max_total_tokens=Some(200)),
          ).to_json(),
          retry_policy: None,
        },
      ],
      output_bindings: ["analyze"],
    }
    let definition = JobDefinition::{
      id: "job.research.analysis",
      kind: "research.paper.analyze",
      enabled: true,
      config: {},
      schedule: None,
      retry_policy: None,
      workflow_id: Some(workflow.id),
      created_at: 1,
      updated_at: 1,
      tags: ["research"],
    }
    let engine = research_test_engine(root, definition, workflow)
    let artifacts = ArtifactStore::new(store=engine.runtime.store())
    ignore(
      artifacts.write(
        ArtifactWriteRequest::new(
          run_id="seed-run",
          job_id="job.research.analysis",
          artifact_type="research.paper.meta",
          logical_key=Some("2501.00001v1"),
          content=sample_paper("2501.00001v1", "Agentic Systems")
            .to_json()
            .stringify(),
          content_type="application/json",
          file_name=Some("paper.json"),
          scope=[research_scope(), research_paper_scope("2501.00001v1")],
          append_only=false,
        ),
        "artifact-paper-meta",
        900,
      ),
    )
    ignore(
      artifacts.write_bytes(
        ArtifactBytesWriteRequest::{
          run_id: "seed-run",
          job_id: "job.research.analysis",
          artifact_type: "research.paper.pdf",
          logical_key: Some("2501.00001v1"),
          content_type: "application/pdf",
          file_name: Some("paper.pdf"),
          metadata: {},
          scope: [research_scope(), research_paper_scope("2501.00001v1")],
          content: @encoding/utf8.encode("pdf bytes"),
          append_only: false,
        },
        "artifact-paper-pdf",
        901,
      ),
    )
    engine.register_handler(
      research_paper_parse_step_handler(
        runtime=engine.runtime,
        extractor=PaperTextExtractor::new(extract=fn(_path, paper) {
          Ok(
            "# \{paper.title}\n\nFirst chunk.\n\nSecond chunk with more detail.",
          )
        }),
        now=fn() { 1001 },
      ),
    )
    engine.register_handler(
      research_paper_analyze_step_handler(
        runtime=engine.runtime,
        executor=AnalysisExecutor::new(run=fn(request) {
          Ok(AnalysisExecution::{
            model_name: request.model_name,
            content: "Structured summary for \{request.step_id}",
            conversation_id: Some("conv-research"),
            usage: Some(@ai.usage(input_tokens=20, output_tokens=30)),
            metadata: {},
          })
        }),
        now=fn() { 1002 },
      ),
    )
    let result = match engine.execute_run("run-research-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    inspect(
      result.steps
      .map(fn(step) { "\{step.step_id}:\{step.status.to_json().stringify()}" })
      .join(","),
      content="parse:\"Succeeded\",analyze:\"Succeeded\"",
    )
    let artifacts = engine.runtime.store().list_artifacts()
    inspect(artifacts.length(), content="6")
    inspect(
      artifacts.map(fn(artifact) { artifact.artifact_type }).join(","),
      content="research.paper.meta,research.paper.pdf,research.paper.text,research.paper.chunks,research.paper.analysis.summary.report,research.paper.analysis.summary.result",
    )
    inspect(
      engine.runtime.store().get_chat_binding("research.paper.ask:2501.00001v1")
      is Some(_),
      content="true",
    )
  })
}
