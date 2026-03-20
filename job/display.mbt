///|
fn abs_diff(left : Int64, right : Int64) -> Int64 {
  if left >= right {
    left - right
  } else {
    right - left
  }
}

///|
fn unwrapped_epoch_ms_near(
  timestamp_ms : Int,
  reference_now_ms : Int64,
) -> Int64 {
  let cycle = 4_294_967_296L
  let residue = timestamp_ms.to_int64()
  let unsigned = if residue < 0L { residue + cycle } else { residue }
  let base = reference_now_ms / cycle
  let mut best = unsigned + base * cycle
  let mut best_diff = abs_diff(best, reference_now_ms)
  for offset in [-1L, 1L] {
    let candidate = unsigned + (base + offset) * cycle
    let candidate_diff = abs_diff(candidate, reference_now_ms)
    if candidate_diff < best_diff {
      best = candidate
      best_diff = candidate_diff
    }
  }
  best
}

///|
fn display_zone() -> @time.Zone {
  @time.fixed_zone("Asia/Shanghai", 8 * 60 * 60) catch {
    _ => @time.utc_zone
  }
}

///|
fn compact_title_for_display(text : String) -> String {
  let trimmed = text.trim().to_string()
  if trimmed.length() <= 72 {
    trimmed
  } else {
    "\{trimmed[:69].to_string()}..."
  }
}

///|
fn slugify_id_segment(
  text : String,
  max_words? : Int = 5,
  max_chars? : Int = 32,
) -> String {
  let buf = StringBuilder::new()
  let mut chars_written = 0
  let mut words = 0
  let mut last_dash = true
  for raw_word in text.split(" ") {
    let word = raw_word.trim().to_string()
    if word.is_blank() {
      continue
    }
    if words >= max_words || chars_written >= max_chars {
      break
    }
    for c in word.to_lower().to_array() {
      let normalized = match c {
        'a'..='z' => Some(c)
        '0'..='9' => Some(c)
        _ => None
      }
      match normalized {
        Some(c) => {
          if chars_written >= max_chars {
            break
          }
          buf.write_char(c)
          chars_written += 1
          last_dash = false
        }
        None =>
          if !last_dash && chars_written < max_chars {
            buf.write_char('-')
            chars_written += 1
            last_dash = true
          }
      }
    }
    if !last_dash && chars_written < max_chars {
      buf.write_char('-')
      chars_written += 1
      last_dash = true
    }
    words += 1
  }
  let slug = buf.to_string().trim(chars="-").to_string()
  if slug.is_blank() {
    "job"
  } else {
    slug
  }
}

///|
fn short_id_suffix(seed : String, max_chars? : Int = 6) -> String {
  let buf = StringBuilder::new()
  let mut count = 0
  for c in seed.to_lower().to_array() {
    match c {
      'a'..='z' | '0'..='9' => {
        buf.write_char(c)
        count += 1
        if count >= max_chars {
          break
        }
      }
      _ => ()
    }
  }
  let suffix = buf.to_string()
  if suffix.is_blank() {
    "job"
  } else {
    suffix
  }
}

///|
fn formatted_timestamp_or_fallback(timestamp_ms : Int) -> String {
  let normalized = unwrapped_epoch_ms_near(timestamp_ms, @async.now())
  let seconds = normalized / 1000L
  try @time.unix(seconds, zone=display_zone()) catch {
    _ => timestamp_ms.to_string()
  } noraise {
    zoned =>
      "\{zoned.to_plain_date_time().to_string()} \{zoned.offset().to_string()}"
  }
}

///|
fn compact_timestamp(now_ms : Int) -> String {
  let rendered = formatted_timestamp_or_fallback(now_ms)
  let buf = StringBuilder::new()
  let mut count = 0
  for c in rendered.to_array() {
    match c {
      '0'..='9' => {
        buf.write_char(c)
        count += 1
      }
      ' ' | 'T' =>
        if count == 8 {
          buf.write_char('-')
          count += 1
        }
      _ => ()
    }
    if count >= 15 {
      break
    }
  }
  let value = buf.to_string()
  if value.length() >= 15 {
    value[:15].to_string()
  } else {
    now_ms.to_string()
  }
}

///|
pub fn human_readable_proposal_id(
  request_text : String,
  now_ms : Int,
  seed : String,
) -> String {
  "\{compact_timestamp(now_ms)}-\{slugify_id_segment(request_text)}-\{short_id_suffix(seed)}"
}

///|
pub fn human_readable_run_id(now_ms : Int, seed : String) -> String {
  "run-\{compact_timestamp(now_ms)}-\{short_id_suffix(seed)}"
}

///|
pub fn definition_display_title(definition : JobDefinition) -> String {
  match definition.config {
    { "title": String(title), .. } if !title.trim().to_string().is_blank() =>
      compact_title_for_display(title)
    _ => {
      let proposal_title = match definition.config {
        { "proposal_title": String(title), .. } => title.trim().to_string()
        _ => ""
      }
      if proposal_title.is_blank() {
        definition.id
      } else {
        compact_title_for_display(proposal_title)
      }
    }
  }
}

///|
pub fn format_job_timestamp(timestamp_ms : Int) -> String {
  formatted_timestamp_or_fallback(timestamp_ms)
}
