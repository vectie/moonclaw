///|
/// Opaque, operator-configured bridge to the trusted MoonFort publisher and
/// one-shot executor. Keeping these paths private prevents callers from
/// turning the adapter into a general host-process API after construction.
pub struct Client {
  publisher_path : String
  publisher_args : Array[String]
  executor_path : String
  executor_args : Array[String]
  executor_config_path : String
  receipt_root : String
  live_output_reader_path : String?
  live_output_reader_args : Array[String]
}

///|
/// Closed adapter for MoonFort's reviewed-retention promotion executable.
/// All process authority is fixed at construction from operator-owned config;
/// callers can provide only the bounded JSON protocol body.
pub struct PromotionClient {
  promotion_path : String
  promotion_args : Array[String]
  executor_config_path : String
  receipt_root : String
}

///|
pub(all) struct ProcessResponse {
  status : Int
  stdout : String
} derive(Debug, Eq)

///|
fn canonical_absolute_path(path : String) -> Bool {
  path.has_prefix("/") &&
  !path.contains("//") &&
  !path.contains("\u{0}") &&
  !path.split("/").any(component => component == "." || component == "..") &&
  (path == "/" || !path.has_suffix("/"))
}

///|
async fn validate_regular_file(path : String, label : String) -> Unit {
  guard canonical_absolute_path(path) &&
    @fsx.resolve(path) == path &&
    @fsx.exists_as_file(path) else {
    fail("MoonFort \{label} must be a canonical regular file")
  }
}

///|
pub async fn Client::new(
  publisher_path : String,
  publisher_args : Array[String],
  executor_path : String,
  executor_args : Array[String],
  executor_config_path : String,
  receipt_root : String,
  live_output_reader_path? : String,
  live_output_reader_args? : Array[String] = [],
) -> Client {
  validate_regular_file(publisher_path, "grant publisher")
  validate_regular_file(executor_path, "executor")
  validate_regular_file(executor_config_path, "executor config")
  if live_output_reader_path is Some(path) {
    validate_regular_file(path, "live output reader")
  }
  guard canonical_absolute_path(receipt_root) &&
    @fsx.resolve(receipt_root) == receipt_root else {
    fail("MoonFort receipt root must be canonical and absolute")
  }
  {
    publisher_path,
    publisher_args: publisher_args.copy(),
    executor_path,
    executor_args: executor_args.copy(),
    executor_config_path,
    receipt_root,
    live_output_reader_path,
    live_output_reader_args: live_output_reader_args.copy(),
  }
}

///|
pub async fn Client::read_live_output(
  self : Client,
  request : String,
) -> ProcessResponse? {
  guard self.live_output_reader_path is Some(path) else { return None }
  Some(self.run(path, self.live_output_reader_args, request, 2_000))
}

///|
async fn Client::run(
  self : Client,
  executable : String,
  arguments : Array[String],
  stdin : String,
  timeout : Int,
) -> ProcessResponse {
  guard timeout > 0 else { fail("MoonFort transport timeout must be positive") }
  let process = run_adapter_process(
    executable,
    arguments,
    stdin~,
    timeout~,
    cwd=self.receipt_root,
    env={ "MOONFORT_EXECUTOR_CONFIG": self.executor_config_path },
  )
  { status: process.status, stdout: process.stdout }
}

///|
pub async fn Client::publish_grant(
  self : Client,
  request : String,
) -> ProcessResponse {
  self.run(self.publisher_path, self.publisher_args, request, 5_000)
}

///|
pub async fn Client::invoke_executor(
  self : Client,
  invocation : String,
  transport_timeout : Int,
) -> ProcessResponse {
  self.run(
    self.executor_path,
    self.executor_args,
    invocation,
    transport_timeout,
  )
}

///|
pub async fn PromotionClient::new(
  promotion_path : String,
  promotion_args : Array[String],
  executor_config_path : String,
  receipt_root : String,
) -> PromotionClient {
  validate_regular_file(promotion_path, "retention promoter")
  validate_regular_file(executor_config_path, "executor config")
  guard promotion_args.length() <= 16 &&
    promotion_args.all(argument => {
      !argument.contains("\u{0}") && argument.length() <= 4_096
    }) else {
    fail("MoonFort retention promoter arguments are invalid")
  }
  guard canonical_absolute_path(receipt_root) &&
    @fsx.resolve(receipt_root) == receipt_root else {
    fail("MoonFort receipt root must be canonical and absolute")
  }
  {
    promotion_path,
    promotion_args: promotion_args.copy(),
    executor_config_path,
    receipt_root,
  }
}

///|
pub async fn PromotionClient::promote_retention(
  self : PromotionClient,
  request : String,
) -> ProcessResponse {
  guard @encoding/utf8.encode(request).length() <= 65_536 else {
    fail("MoonFort promotion request exceeds the adapter bound")
  }
  let process = run_adapter_process(
    self.promotion_path,
    self.promotion_args,
    stdin=request,
    timeout=60_000,
    cwd=self.receipt_root,
    env={ "MOONFORT_EXECUTOR_CONFIG": self.executor_config_path },
    stdout_limit=65_536,
  )
  { status: process.status, stdout: process.stdout }
}
