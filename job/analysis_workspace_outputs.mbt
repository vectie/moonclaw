///|
fn workspace_output_slug(text : String) -> String {
  let buf = StringBuilder::new()
  let mut chars_written = 0
  let mut last_dash = true
  for c in text.to_lower() {
    let normalized = match c {
      'a'..='z' => Some(c)
      '0'..='9' => Some(c)
      _ => None
    }
    match normalized {
      Some(c) => {
        if chars_written >= 32 {
          break
        }
        buf.write_char(c)
        chars_written += 1
        last_dash = false
      }
      None =>
        if !last_dash && chars_written < 32 {
          buf.write_char('-')
          chars_written += 1
          last_dash = true
        }
    }
  }
  let slug = buf.to_string().trim(chars="-").to_owned()
  if slug.is_blank() {
    "step"
  } else {
    slug
  }
}

///|
fn workspace_report_file_name(step_id : String, step_title : String) -> String {
  "step-\{step_id}-\{workspace_output_slug(step_title)}.md"
}

///|
fn workspace_result_file_name(step_id : String, step_title : String) -> String {
  "step-\{step_id}-\{workspace_output_slug(step_title)}.json"
}

///|
fn run_workflow_steps(
  store : SystemStore,
  run : JobRun,
) -> Array[WorkflowStepDefinition] {
  let definition = match store.get_definition(run.job_id) {
    Some(definition) => definition
    None => return []
  }
  let workflow_id = match definition.workflow_id {
    Some(workflow_id) => workflow_id
    None => return []
  }
  match store.get_workflow(workflow_id) {
    Some(workflow) => workflow.steps
    None => []
  }
}

///|
fn is_final_workflow_step(
  store : SystemStore,
  run : JobRun,
  step_id : String,
) -> Bool {
  let steps = run_workflow_steps(store, run)
  if steps.is_empty() {
    false
  } else {
    steps[steps.length() - 1].id == step_id
  }
}

///|
pub async fn materialize_analysis_outputs_to_workspace(
  store : SystemStore,
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
  result_payload : Json,
  report_content : String,
) -> Unit {
  let workspace_dir = match context.run.workspace_dir {
    Some(workspace_dir) if !workspace_dir.trim().to_owned().is_blank() =>
      workspace_dir
    _ => return
  }
  let outputs_dir = workspace_dir |> @pathx.join("outputs")
  @fsx.make_directory(outputs_dir, recursive=true) catch {
    _ => return
  }
  let report_file = outputs_dir
    |> @pathx.join(
      config.artifacts.report_file_name.unwrap_or(
        workspace_report_file_name(context.step.id, context.step.id),
      ),
    )
  let result_file = outputs_dir
    |> @pathx.join(
      config.artifacts.result_file_name.unwrap_or(
        workspace_result_file_name(context.step.id, context.step.id),
      ),
    )
  @fsx.write_to_file(report_file, report_content) catch {
    _ => ()
  }
  @fsx.write_to_file(result_file, result_payload.stringify()) catch {
    _ => ()
  }
  match config.artifacts.report_file_name {
    Some(file_name) if !file_name.trim().to_owned().is_blank() =>
      @fsx.write_to_file(
        workspace_dir |> @pathx.join(file_name),
        report_content,
      ) catch {
        _ => ()
      }
    _ => ()
  }
  match config.artifacts.result_file_name {
    Some(file_name) if !file_name.trim().to_owned().is_blank() =>
      @fsx.write_to_file(
        workspace_dir |> @pathx.join(file_name),
        result_payload.stringify(),
      ) catch {
        _ => ()
      }
    _ => ()
  }
  if is_final_workflow_step(store, context.run, context.step.id) {
    let skip_primary = metadata_bool_with_step_metadata(
      config.metadata,
      "skip_primary_workspace_output",
      false,
    )
    if skip_primary {
      return
    }
    @fsx.write_to_file(
      workspace_dir |> @pathx.join("report.md"),
      report_content,
    ) catch {
      _ => ()
    }
    @fsx.write_to_file(
      workspace_dir |> @pathx.join("result.json"),
      result_payload.stringify(),
    ) catch {
      _ => ()
    }
  }
}
