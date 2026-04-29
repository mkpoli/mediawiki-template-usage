///|
const SEEK_SET = 0

///|
const SEEK_END = 2

///|
const O_RDONLY = 0

///|
const CONTENT_BATCH_SIZE = 20

///|
const DUMP_READ_CHUNK_SIZE = 65536

///|
const DUMP_PROGRESS_INTERVAL = 1000

///|
pub(all) enum SortBy {
  Api
  TitleAsc
  TitleDesc
} derive(Eq)

///|
pub impl Show for SortBy with output(self, logger) {
  let label = match self {
    Api => "api"
    TitleAsc => "title-asc"
    TitleDesc => "title-desc"
  }
  logger.write_string(label)
}

///|
pub(all) struct Config {
  endpoint : String
  dump_files : Array[String]
  template_name : String
  category_name : String?
  param_filters : Array[TemplateParamFilter]
  limit : Int?
  sort_by : SortBy
  show_content : Bool
  verbose : Bool
} derive(Eq)

///|
pub impl Show for Config with output(self, logger) {
  logger.write_string("Config::{ endpoint: ")
  logger.write_object(self.endpoint)
  logger.write_string(", dump_files: ")
  logger.write_object(self.dump_files)
  logger.write_string(", template_name: ")
  logger.write_object(self.template_name)
  logger.write_string(", category_name: ")
  logger.write_object(self.category_name)
  logger.write_string(", param_filters: ")
  logger.write_object(render_param_filters(self.param_filters))
  logger.write_string(", limit: ")
  logger.write_object(self.limit)
  logger.write_string(", sort_by: ")
  logger.write_object(self.sort_by)
  logger.write_string(", show_content: ")
  logger.write_object(self.show_content)
  logger.write_string(", verbose: ")
  logger.write_object(self.verbose)
  logger.write_string(" }")
}

///|
priv struct UsageResults {
  titles : Array[String]
  page_contents : Map[String, String]?
  query : QueryContext
}

///|
priv struct NamespaceInfo {
  primary_name : String
  canonical_name : String?
  aliases : Array[String]
}

///|
priv struct SourceNamespaces {
  template : NamespaceInfo
  category : NamespaceInfo
}

///|
priv struct QueryContext {
  template_title : String
  template_target : String
  category_title : String?
  category_target : String?
  param_filters : Array[TemplateParamFilter]
}

///|
pub(all) enum TemplateParamKey {
  Positional(Int)
  Named(String)
} derive(Eq)

///|
pub(all) struct TemplateParamFilter {
  key : TemplateParamKey
  value : String
} derive(Eq)

///|
pub impl Show for TemplateParamKey with output(self, logger) {
  match self {
    Positional(index) => {
      logger.write_string("Positional(")
      logger.write_object(index)
      logger.write_string(")")
    }
    Named(name) => {
      logger.write_string("Named(")
      logger.write_object(name)
      logger.write_string(")")
    }
  }
}

///|
pub impl Show for TemplateParamFilter with output(self, logger) {
  logger.write_string("TemplateParamFilter::{ key: ")
  logger.write_object(self.key)
  logger.write_string(", value: ")
  logger.write_object(self.value)
  logger.write_string(" }")
}

///|
pub(all) suberror CliError {
  Message(String)
}

///|
pub impl Show for CliError with output(self, logger) {
  match self {
    Message(message) => logger.write_string(message)
  }
}

///|
#borrow(raw)
extern "c" fn system_ffi(raw : Bytes) -> Int = "system"

///|
#borrow(path)
extern "c" fn open_ffi(path : Bytes, flags : Int, mode : Int) -> Int = "open"

///|
#borrow(buffer)
extern "c" fn read_ffi(fd : Int, buffer : Bytes, size : Int) -> Int = "read"

///|
extern "c" fn close_ffi(fd : Int) -> Int = "close"

///|
extern "c" fn lseek_ffi(fd : Int, offset : Int, whence : Int) -> Int = "lseek"

///|
#borrow(path)
extern "c" fn unlink_ffi(path : Bytes) -> Int = "unlink"

///|
pub async fn run_cli(args : Array[String]) -> Unit {
  try {
    let config = parse_config(args)
    debug_log(config.verbose, "config: " + config.to_string())
    maybe_warn_dump_category_limitations(
      config.dump_files,
      config.category_name,
    )
    match
      fetch_all_template_usages(
        config.endpoint,
        config.dump_files,
        config.template_name,
        config.category_name,
        config.param_filters,
        config.sort_by,
        config.limit,
        config.verbose,
      ) {
      Ok(results) =>
        output_results(
          config.endpoint,
          results.query,
          results.titles,
          results.page_contents,
          config.show_content,
          config.verbose,
        )
      Err(message) => println("error: \{message}")
    }
  } catch {
    err => println(err.to_string())
  }
}

///|
pub fn command() -> @argparse.Command {
  @argparse.Command::new(
    "mediawiki-template-usage",
    about="List pages that transclude a MediaWiki template from a MediaWiki API or local Wikimedia XML dump files.\n\nExamples:\n  Production: ./mediawiki-template-usage enwp \"Citation needed\"\n  Production with category filter: ./mediawiki-template-usage enwp \"Citation needed\" --category \"Living people\"\n  Production with parameter filter: ./mediawiki-template-usage jawiktionary-2026-04-01-p7p579548.xml affix --param \"1=ain\"\n  Production (dump file): ./mediawiki-template-usage jawiktionary-2026-04-01-p7p579548.xml \"Citation needed\"\n  Production (multiple dump files): ./mediawiki-template-usage jawiktionary-2026-04-01-p7p579548.xml \"Citation needed\" --dump-file jawiktionary-2026-04-01-p7p579549.xml\n  Development: moon run cmd/main -- enwp \"Citation needed\"",
    version="0.1.2",
    arg_required_else_help=true,
    flags=[
      @argparse.FlagArg::new(
        "show-content",
        about="Fetch and print only matching template usages for the final results. Best used with --limit.",
      ),
      @argparse.FlagArg::new(
        "verbose",
        short='v',
        about="Print debug details about API requests, payloads, and filtering. `-v` is accepted as an alias.",
      ),
    ],
    options=[
      @argparse.OptionArg::new(
        "limit",
        short='l',
        about="Maximum number of page titles to print.",
        default_values=["10"],
      ),
      @argparse.OptionArg::new(
        "sort-by",
        short='s',
        about="Sort order: api, title-asc, or title-desc. api preserves API or dump order.",
        default_values=["api"],
      ),
      @argparse.OptionArg::new(
        "category",
        short='c',
        about="Only include pages that are in the given category, with or without the source wiki's category prefix. In dump mode this only checks explicit category links in page wikitext; categories generated through template expansion are not available from page XML dumps.",
      ),
      @argparse.OptionArg::new(
        "param",
        about="Only include template usages whose parameter matches KEY=VALUE. Repeat to require multiple parameters. Positional keys are 1-based, for example --param \"1=ain\".",
        action=@argparse.Append,
      ),
      @argparse.OptionArg::new(
        "dump-file",
        about="Additional XML dump file to scan. Repeat to combine multiple dump files.",
        action=@argparse.Append,
      ),
    ],
    positionals=[
      @argparse.PositionArg::new(
        "source",
        about="MediaWiki API endpoint, alias, or XML dump file, for example https://en.wikipedia.org/w/api.php, enwp, commons, wikidata, or jawiktionary-2026-04-01-p7p579548.xml",
        num_args=@argparse.ValueRange::single(),
      ),
      @argparse.PositionArg::new(
        "template",
        about="Template name, with or without the source wiki's template prefix",
        num_args=@argparse.ValueRange::single(),
      ),
    ],
  )
}

///|
pub fn parse_config(args : Array[String]) -> Config raise CliError {
  let matches = command().parse(argv=normalize_cli_args(extract_cli_args(args))) catch {
    err => raise Message(err.to_string())
  }
  let values = matches.values
  guard values.get("source") is Some([raw_endpoint, ..]) else {
    raise Message("missing source argument")
  }
  guard values.get("template") is Some([template_name, ..]) else {
    raise Message("missing template argument")
  }
  let extra_dump_files = resolve_additional_dump_files(
    values.get("dump-file").unwrap_or([]),
  )
  let (endpoint, dump_files) = resolve_source(raw_endpoint, extra_dump_files)
  let category_name = match values.get("category") {
    Some([raw_category, ..]) => Some(raw_category.trim().to_string())
    _ => None
  }
  let param_filters = parse_param_filters(values.get("param").unwrap_or([]))
  let limit = match values.get("limit") {
    Some([raw_limit, ..]) => Some(parse_limit(raw_limit))
    _ => Some(10)
  }
  let sort_by = match values.get("sort-by") {
    Some([raw_sort, ..]) => parse_sort_by(raw_sort)
    _ => Api
  }
  let show_content = matches.flags.get_or_default("show-content", false)
  let verbose = matches.flags.get_or_default("verbose", false)
  {
    endpoint,
    dump_files,
    template_name,
    category_name,
    param_filters,
    limit,
    sort_by,
    show_content,
    verbose,
  }
}

///|
fn render_param_filters(filters : Array[TemplateParamFilter]) -> Array[String] {
  let rendered = []
  for filter in filters {
    rendered.push(render_param_filter(filter))
  }
  rendered
}

///|
fn render_param_filter(filter : TemplateParamFilter) -> String {
  let key = match filter.key {
    Positional(index) => index.to_string()
    Named(name) => name
  }
  key + "=" + filter.value
}

///|
fn parse_param_filters(
  raw_param_filters : Array[String],
) -> Array[TemplateParamFilter] raise CliError {
  let filters = []
  for raw_filter in raw_param_filters {
    filters.push(parse_param_filter(raw_filter))
  }
  filters
}

///|
fn parse_param_filter(
  raw_filter : String,
) -> TemplateParamFilter raise CliError {
  let filter = raw_filter.trim().to_string()
  let separator = find_substring(filter, "=", 0)
  if separator <= 0 || separator >= filter.length() - 1 {
    raise Message("--param must use KEY=VALUE, for example --param \"1=ain\"")
  }
  let raw_key = filter[:separator].to_string().trim().to_string()
  let value = filter[separator + 1:].to_string().trim().to_string()
  if raw_key.is_empty() || value.is_empty() {
    raise Message("--param must use KEY=VALUE, for example --param \"1=ain\"")
  }
  { key: parse_param_key(raw_key), value }
}

///|
fn parse_param_key(raw_key : String) -> TemplateParamKey raise CliError {
  let parsed : Result[Int, _] = try? @string.parse_int(raw_key)
  match parsed {
    Ok(index) => {
      if index <= 0 {
        raise Message("--param positional indexes must be greater than 0")
      }
      Positional(index)
    }
    Err(_) => Named(raw_key.to_lower())
  }
}

///|
fn maybe_warn_dump_category_limitations(
  dump_files : Array[String],
  category_name : String?,
) -> Unit {
  if dump_files.length() == 0 {
    return
  }
  match category_name {
    Some(_) =>
      println(
        "warning: dump category filtering only checks explicit category links in page wikitext; categories generated through template expansion are not available from page XML dumps",
      )
    None => ()
  }
}

///|
pub fn write_string_to_file_for_test(path : String, content : String) -> Unit {
  @fs.write_string_to_file(path, content) catch {
    _ => panic()
  }
}

///|
pub fn remove_file_for_test(path : String) -> Unit {
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
fn output_results(
  endpoint : String,
  query : QueryContext,
  titles : Array[String],
  page_contents : Map[String, String]?,
  show_content : Bool,
  verbose : Bool,
) -> Unit {
  let result_mode = if show_content { " with content" } else { " titles only" }
  debug_log(
    verbose,
    "final result count: " + titles.length().to_string() + result_mode,
  )
  if !show_content {
    for title in titles {
      println(title)
    }
    return
  }
  match page_contents {
    Some(contents) => {
      debug_log(verbose, "using page contents extracted from dump matches")
      print_page_contents(titles, query, contents)
    }
    None => {
      debug_log(
        verbose,
        "fetching page contents in batches of " + CONTENT_BATCH_SIZE.to_string(),
      )
      match fetch_page_contents(endpoint, titles) {
        Ok(contents) => print_page_contents(titles, query, contents)
        Err(message) => println("error: \{message}")
      }
    }
  }
}

///|
fn resolve_endpoint(raw_endpoint : String) -> String raise CliError {
  let endpoint = raw_endpoint.trim().to_string()
  if endpoint.contains("://") {
    return endpoint
  }
  match endpoint {
    "commons" => "https://commons.wikimedia.org/w/api.php"
    "meta" => "https://meta.wikimedia.org/w/api.php"
    "mediawiki" | "mw" => "https://www.mediawiki.org/w/api.php"
    "wikidata" | "wd" => "https://www.wikidata.org/w/api.php"
    _ => {
      if path_is_directory(endpoint) {
        raise Message(
          "dump directories are not supported; specify one or more dump files instead",
        )
      }
      if looks_like_local_path(endpoint) || looks_like_dump_file_name(endpoint) {
        raise Message("dump file '\{endpoint}' does not exist")
      }
      resolve_language_project_alias(endpoint)
    }
  }
}

///|
fn resolve_source(
  raw_source : String,
  extra_dump_files : Array[String],
) -> (String, Array[String]) raise CliError {
  let source = raw_source.trim().to_string()
  if path_is_file(source) {
    return (source, prepend_dump_file(source, extra_dump_files))
  }
  let endpoint = resolve_endpoint(source)
  if extra_dump_files.length() > 0 {
    raise Message(
      "--dump-file can only be used when <source> is also a dump file",
    )
  }
  (endpoint, [])
}

///|
fn resolve_additional_dump_files(
  raw_dump_files : Array[String],
) -> Array[String] raise CliError {
  let dump_files = []
  for raw_dump_file in raw_dump_files {
    dump_files.push(resolve_dump_file(raw_dump_file))
  }
  dump_files
}

///|
fn resolve_dump_file(raw_dump_file : String) -> String raise CliError {
  let dump_file = raw_dump_file.trim().to_string()
  if !dump_file.has_suffix(".xml") {
    raise Message("only plain .xml dump files are supported")
  }
  if path_is_file(dump_file) {
    return dump_file
  }
  if path_is_directory(dump_file) {
    raise Message(
      "dump directories are not supported; specify one or more dump files instead",
    )
  }
  raise Message("dump file '\{dump_file}' does not exist")
}

///|
fn prepend_dump_file(
  dump_file : String,
  extra_dump_files : Array[String],
) -> Array[String] {
  let resolved = [dump_file]
  for extra_dump_file in extra_dump_files {
    resolved.push(extra_dump_file)
  }
  resolved
}

///|
fn looks_like_local_path(path : String) -> Bool {
  path.contains("/") ||
  path.contains("\\") ||
  path.has_prefix(".") ||
  path.has_prefix("~")
}

///|
fn looks_like_dump_file_name(path : String) -> Bool {
  path.has_suffix(".xml")
}

///|
fn resolve_language_project_alias(shorthand : String) -> String raise CliError {
  if shorthand.length() > 2 && shorthand.has_suffix("wp") {
    return build_language_project_endpoint(
      shorthand[:shorthand.length() - 2],
      "wikipedia",
    )
  }
  if shorthand.length() > 4 && shorthand.has_suffix("wikt") {
    return build_language_project_endpoint(
      shorthand[:shorthand.length() - 4],
      "wiktionary",
    )
  }
  if shorthand.length() > 2 && shorthand.has_suffix("wb") {
    return build_language_project_endpoint(
      shorthand[:shorthand.length() - 2],
      "wikibooks",
    )
  }
  if shorthand.length() > 2 && shorthand.has_suffix("wn") {
    return build_language_project_endpoint(
      shorthand[:shorthand.length() - 2],
      "wikinews",
    )
  }
  if shorthand.length() > 2 && shorthand.has_suffix("wq") {
    return build_language_project_endpoint(
      shorthand[:shorthand.length() - 2],
      "wikiquote",
    )
  }
  if shorthand.length() > 2 && shorthand.has_suffix("ws") {
    return build_language_project_endpoint(
      shorthand[:shorthand.length() - 2],
      "wikisource",
    )
  }
  if shorthand.length() > 2 && shorthand.has_suffix("wv") {
    return build_language_project_endpoint(
      shorthand[:shorthand.length() - 2],
      "wikiversity",
    )
  }
  if shorthand.length() > 3 && shorthand.has_suffix("voy") {
    return build_language_project_endpoint(
      shorthand[:shorthand.length() - 3],
      "wikivoyage",
    )
  }
  raise Message(
    "unknown source '\{shorthand}'. Use a full https://.../w/api.php endpoint, an existing dump file, or a known alias like enwp, commons, meta, mediawiki, or wikidata",
  )
}

///|
fn build_language_project_endpoint(
  lang : StringView,
  project : String,
) -> String {
  "https://" + lang.to_string() + "." + project + ".org/w/api.php"
}

///|
fn parse_limit(raw_limit : String) -> Int raise CliError {
  let parsed : Result[Int, _] = try? @string.parse_int(raw_limit)
  match parsed {
    Ok(limit) => {
      if limit <= 0 {
        raise Message("limit must be greater than 0")
      }
      limit
    }
    Err(_) => raise Message("limit must be a positive integer")
  }
}

///|
fn parse_sort_by(raw_sort : String) -> SortBy raise CliError {
  match raw_sort.trim() {
    "api" => Api
    "title-asc" => TitleAsc
    "title-desc" => TitleDesc
    _ => raise Message("sort-by must be one of: api, title-asc, title-desc")
  }
}

///|
fn extract_cli_args(args : Array[String]) -> Array[String] {
  let mut separator_index = -1
  for i = 0; i < args.length(); i = i + 1 {
    if args[i] == "--" {
      separator_index = i
    }
  }
  if separator_index >= 0 {
    copy_args_from(args, separator_index + 1)
  } else if args.length() > 0 {
    copy_args_from(args, 1)
  } else {
    []
  }
}

///|
fn copy_args_from(args : Array[String], start : Int) -> Array[String] {
  let copied = []
  for i = start; i < args.length(); i = i + 1 {
    copied.push(args[i])
  }
  copied
}

///|
fn normalize_cli_args(args : Array[String]) -> Array[String] {
  let normalized = []
  for arg in args {
    if arg == "-v" {
      normalized.push("--verbose")
    } else {
      normalized.push(arg)
    }
  }
  normalized
}

///|
async fn fetch_all_template_usages(
  endpoint : String,
  dump_files : Array[String],
  template_name : String,
  category_name : String?,
  param_filters : Array[TemplateParamFilter],
  sort_by : SortBy,
  limit : Int?,
  verbose : Bool,
) -> Result[UsageResults, String] {
  let namespaces = match load_source_namespaces(endpoint, dump_files, verbose) {
    Ok(namespaces) => namespaces
    Err(message) => return Err(message)
  }
  let query = build_query_context(
    template_name, category_name, param_filters, namespaces,
  )
  let category_suffix = match query.category_title {
    Some(category) => " in " + category
    None => " without category filter"
  }
  debug_log(
    verbose,
    "fetching usages for " + query.template_title + category_suffix,
  )
  if dump_files.length() > 0 {
    let results = match
      fetch_dump_template_usages(
        dump_files,
        query,
        dump_scan_limit(sort_by, limit),
        verbose,
      ) {
      Ok(results) => results
      Err(message) => return Err(message)
    }
    let sorted = sort_titles(results.titles, sort_by)
    let limited = limit_titles(sorted, limit)
    let limit_suffix = match limit {
      Some(value) => ", limit=" + value.to_string()
      None => ", no limit"
    }
    debug_log(
      verbose,
      "collected " +
      results.titles.length().to_string() +
      " dump titles before limit; returning " +
      limited.length().to_string() +
      " after sort=" +
      sort_by.to_string() +
      limit_suffix,
    )
    return Ok({ titles: limited, page_contents: results.page_contents, query })
  }
  let titles = match
    fetch_all_template_usage_titles(endpoint, query, None, [], verbose) {
    Ok(titles) => titles
    Err(message) => return Err(message)
  }
  if query_requires_content_scan(query) {
    debug_log(
      verbose, "fetching page contents to apply template parameter filters",
    )
    let contents = match fetch_page_contents(endpoint, titles) {
      Ok(contents) => contents
      Err(message) => return Err(message)
    }
    let (filtered_titles, filtered_contents) = filter_titles_by_query(
      titles, contents, query,
    )
    let sorted = sort_titles(filtered_titles, sort_by)
    let limited = limit_titles(sorted, limit)
    let limit_suffix = match limit {
      Some(value) => ", limit=" + value.to_string()
      None => ", no limit"
    }
    debug_log(
      verbose,
      "collected " +
      filtered_titles.length().to_string() +
      " titles after parameter filtering; returning " +
      limited.length().to_string() +
      " after sort=" +
      sort_by.to_string() +
      limit_suffix,
    )
    return Ok({ titles: limited, page_contents: Some(filtered_contents), query })
  }
  let sorted = sort_titles(titles, sort_by)
  let limited = limit_titles(sorted, limit)
  let limit_suffix = match limit {
    Some(value) => ", limit=" + value.to_string()
    None => ", no limit"
  }
  debug_log(
    verbose,
    "collected " +
    titles.length().to_string() +
    " titles before limit; returning " +
    limited.length().to_string() +
    " after sort=" +
    sort_by.to_string() +
    limit_suffix,
  )
  Ok({ titles: limited, page_contents: None, query })
}

///|
async fn fetch_dump_template_usages(
  dump_files : Array[String],
  query : QueryContext,
  stop_after : Int?,
  verbose : Bool,
) -> Result[UsageResults, String] {
  debug_log(
    verbose,
    "scanning " +
    dump_files.length().to_string() +
    " dump file(s) for template matches",
  )
  let (titles, page_contents, pages_scanned) = match
    collect_dump_template_usages(dump_files, query, stop_after, verbose) {
    Ok(parsed) => parsed
    Err(message) => return Err(message)
  }
  debug_log(
    verbose,
    "scanned " +
    pages_scanned.to_string() +
    " dump pages; found " +
    titles.length().to_string() +
    " matches after filtering",
  )
  Ok({ titles, page_contents: Some(page_contents), query })
}

///|
async fn collect_dump_template_usages(
  dump_files : Array[String],
  query : QueryContext,
  stop_after : Int?,
  verbose : Bool,
) -> Result[(Array[String], Map[String, String], Int), String] {
  let titles = []
  let page_contents = {}
  let mut pages_scanned = 0
  if stop_after is Some(_) {
    for dump_file in dump_files {
      let scan_result = scan_dump_file(dump_file, query, stop_after, verbose)
      let (file_titles, file_contents, scanned) = match scan_result {
        Ok(result) => result
        Err(message) => return Err(message)
      }
      pages_scanned += scanned
      append_titles(titles, file_titles)
      merge_page_contents(page_contents, file_contents)
      if reached_dump_scan_limit(titles.length(), stop_after) {
        break
      }
    }
    return Ok((titles, page_contents, pages_scanned))
  }
  let parsed = @async.with_task_group(group => {
    let tasks = []
    for dump_file in dump_files {
      tasks.push(
        group.spawn(() => scan_dump_file(dump_file, query, None, verbose)),
      )
    }
    let results = []
    for task in tasks {
      results.push(task.wait())
    }
    results
  }) catch {
    err => return Err(err.to_string())
  }
  for result in parsed {
    let (file_titles, file_contents, scanned) = match result {
      Ok(value) => value
      Err(message) => return Err(message)
    }
    pages_scanned += scanned
    append_titles(titles, file_titles)
    merge_page_contents(page_contents, file_contents)
  }
  Ok((titles, page_contents, pages_scanned))
}

///|
fn dump_scan_limit(sort_by : SortBy, limit : Int?) -> Int? {
  match sort_by {
    Api => limit
    _ => None
  }
}

///|
fn reached_dump_scan_limit(count : Int, stop_after : Int?) -> Bool {
  match stop_after {
    Some(limit) => count >= limit
    None => false
  }
}

///|
fn merge_page_contents(
  target : Map[String, String],
  source : Map[String, String],
) -> Unit {
  for entry in source.iter() {
    target[entry.0] = entry.1
  }
}

///|
async fn scan_dump_file(
  dump_file : String,
  query : QueryContext,
  stop_after : Int?,
  verbose : Bool,
) -> Result[(Array[String], Map[String, String], Int), String] {
  let file = @async_fs.open(dump_file, mode=@async_fs.ReadOnly) catch {
    _ => return Err("failed to open dump file")
  }
  defer file.close()
  let titles : Array[String] = []
  let page_contents : Map[String, String] = {}
  let pending : Array[Byte] = []
  let buffer = FixedArray::make(DUMP_READ_CHUNK_SIZE, b'\x00')
  let mut pages_scanned = 0
  let mut next_progress = DUMP_PROGRESS_INTERVAL
  let mut chunks = 0
  while true {
    let bytes_read = file.read(buffer) catch {
      _ => return Err("failed to read dump file")
    }
    if bytes_read == 0 {
      break
    }
    chunks += 1
    append_bytes_from_fixed_buffer(pending, buffer, bytes_read)
    pages_scanned += process_pending_dump_pages(
      pending, query, titles, page_contents, stop_after,
    )
    while should_log_dump_progress(pages_scanned, next_progress) {
      debug_log(
        verbose,
        "processed " +
        pages_scanned.to_string() +
        " dump pages; found " +
        titles.length().to_string() +
        " matches",
      )
      next_progress += DUMP_PROGRESS_INTERVAL
    }
    if reached_dump_scan_limit(titles.length(), stop_after) {
      break
    }
    if chunks % 8 == 0 {
      @async.pause()
    }
  }
  Ok((titles, page_contents, pages_scanned))
}

///|
fn should_log_dump_progress(pages_scanned : Int, next_progress : Int) -> Bool {
  pages_scanned >= next_progress
}

///|
fn append_bytes_from_buffer(
  pending : Array[Byte],
  buffer : Bytes,
  bytes_read : Int,
) -> Unit {
  for i = 0; i < bytes_read; i = i + 1 {
    pending.push(buffer[i])
  }
}

///|
fn append_bytes_from_fixed_buffer(
  pending : Array[Byte],
  buffer : FixedArray[Byte],
  bytes_read : Int,
) -> Unit {
  for i = 0; i < bytes_read; i = i + 1 {
    pending.push(buffer[i])
  }
}

///|
fn process_pending_dump_pages(
  pending : Array[Byte],
  query : QueryContext,
  titles : Array[String],
  page_contents : Map[String, String],
  stop_after : Int?,
) -> Int {
  let page_start = string_to_utf8_bytes("<page", false).to_array()
  let page_end = string_to_utf8_bytes("</page>", false).to_array()
  let mut processed = 0
  while true {
    let start = find_byte_substring(pending, page_start, 0)
    if start < 0 {
      trim_pending_prefix(pending, page_start.length() - 1)
      break
    }
    if start > 0 {
      drop_pending_prefix(pending, start)
    }
    let end = find_byte_substring(pending, page_end, 0)
    if end < 0 {
      break
    }
    let page_xml = utf8_bytes_to_string(
      Bytes::from_array(copy_byte_range(pending, 0, end + page_end.length())),
    )
    process_dump_page_xml(page_xml, query, titles, page_contents)
    processed += 1
    drop_pending_prefix(pending, end + page_end.length())
    if reached_dump_scan_limit(titles.length(), stop_after) {
      break
    }
  }
  processed
}

///|
fn process_dump_page_xml(
  page_xml : String,
  query : QueryContext,
  titles : Array[String],
  page_contents : Map[String, String],
) -> Unit {
  let page = match parse_dump_page(page_xml) {
    Some(page) => page
    None => return
  }
  if !page_contains_template(
      page.content,
      query.template_target,
      query.param_filters,
    ) {
    return
  }
  if !dump_page_matches_category(page.content, query.category_target) {
    return
  }
  titles.push(page.title)
  page_contents[page.title] = page.content
}

///|
fn trim_pending_prefix(pending : Array[Byte], max_keep : Int) -> Unit {
  if max_keep <= 0 || pending.length() <= max_keep {
    return
  }
  drop_pending_prefix(pending, pending.length() - max_keep)
}

///|
fn drop_pending_prefix(pending : Array[Byte], count : Int) -> Unit {
  if count <= 0 {
    return
  }
  let keep = copy_byte_range(pending, count, pending.length())
  pending.clear()
  for byte in keep {
    pending.push(byte)
  }
}

///|
fn copy_byte_range(
  source : Array[Byte],
  start : Int,
  stop : Int,
) -> Array[Byte] {
  let copied : Array[Byte] = []
  let bounded_start = if start < 0 { 0 } else { start }
  let bounded_stop = if stop < source.length() { stop } else { source.length() }
  for i = bounded_start; i < bounded_stop; i = i + 1 {
    copied.push(source[i])
  }
  copied
}

///|
fn find_byte_substring(
  haystack : Array[Byte],
  needle : Array[Byte],
  start : Int,
) -> Int {
  let haystack_len = haystack.length()
  let needle_len = needle.length()
  if start < 0 || start > haystack_len {
    return -1
  }
  if needle_len == 0 {
    return start
  }
  if needle_len > haystack_len - start {
    return -1
  }
  let last_start = haystack_len - needle_len
  let mut i = start
  while i <= last_start {
    if has_byte_substring_at(haystack, needle, i) {
      return i
    }
    i += 1
  }
  -1
}

///|
fn has_byte_substring_at(
  haystack : Array[Byte],
  needle : Array[Byte],
  start : Int,
) -> Bool {
  let needle_len = needle.length()
  let mut i = 0
  while i < needle_len {
    if haystack[start + i] != needle[i] {
      return false
    }
    i += 1
  }
  true
}

///|

///|
fn parse_dump_xml(
  payload : String,
  query : QueryContext,
) -> Result[(Array[String], Map[String, String]), String] {
  let titles = []
  let page_contents = {}
  for page_xml in split_dump_pages(payload) {
    process_dump_page_xml(page_xml, query, titles, page_contents)
  }
  Ok((titles, page_contents))
}

///|
priv struct DumpPage {
  title : String
  content : String
}

///|
fn split_dump_pages(payload : String) -> Array[String] {
  let pages = []
  let mut search_from = 0
  while true {
    let start = find_substring(payload, "<page", search_from)
    if start < 0 {
      break
    }
    let start_close = find_substring(payload, ">", start)
    if start_close < 0 {
      break
    }
    let end = find_substring(payload, "</page>", start_close + 1)
    if end < 0 {
      break
    }
    pages.push(payload[start:end + 7].to_string())
    search_from = end + 7
  }
  pages
}

///|
fn parse_dump_page(page_xml : String) -> DumpPage? {
  let title = extract_xml_tag_text(page_xml, "title")
  let content = extract_dump_page_content(page_xml)
  guard title is Some(title) else { return None }
  Some({ title, content: content.unwrap_or("") })
}

///|
fn extract_xml_tag_text(payload : String, tag : String) -> String? {
  let start_tag = "<" + tag + ">"
  let end_tag = "</" + tag + ">"
  let start = find_substring(payload, start_tag, 0)
  if start < 0 {
    return None
  }
  let content_start = start + start_tag.length()
  let end = find_substring(payload, end_tag, content_start)
  if end < 0 {
    return None
  }
  Some(decode_xml_entities(payload[content_start:end].to_string()))
}

///|
fn extract_dump_page_content(page_xml : String) -> String? {
  let text_start = find_substring(page_xml, "<text", 0)
  if text_start < 0 {
    return None
  }
  let body_start = find_substring(page_xml, ">", text_start)
  if body_start < 0 {
    return None
  }
  let text_end = find_substring(page_xml, "</text>", body_start + 1)
  if text_end < 0 {
    return None
  }
  Some(decode_xml_entities(page_xml[body_start + 1:text_end].to_string()))
}

///|
fn find_substring(content : String, needle : String, start : Int) -> Int {
  let content_len = content.length()
  let needle_len = needle.length()
  if start < 0 || start > content_len {
    return -1
  }
  if needle_len == 0 {
    return start
  }
  if needle_len > content_len - start {
    return -1
  }
  let last_start = content_len - needle_len
  let mut i = start
  while i <= last_start {
    if has_substring_at(content, needle, i) {
      return i
    }
    i += 1
  }
  -1
}

///|
fn has_substring_at(content : String, needle : String, start : Int) -> Bool {
  let needle_len = needle.length()
  let mut i = 0
  while i < needle_len {
    if content.code_unit_at(start + i) != needle.code_unit_at(i) {
      return false
    }
    i += 1
  }
  true
}

///|
fn decode_xml_entities(text : String) -> String {
  let mut decoded = text
  while decoded.contains("&lt;") {
    decoded = decoded.replace(old="&lt;", new="<")
  }
  while decoded.contains("&gt;") {
    decoded = decoded.replace(old="&gt;", new=">")
  }
  while decoded.contains("&quot;") {
    decoded = decoded.replace(old="&quot;", new="\"")
  }
  while decoded.contains("&apos;") {
    decoded = decoded.replace(old="&apos;", new="'")
  }
  while decoded.contains("&amp;") {
    decoded = decoded.replace(old="&amp;", new="&")
  }
  decoded
}

///|
fn page_contains_template(
  content : String,
  template_target : String,
  param_filters : Array[TemplateParamFilter],
) -> Bool {
  extract_template_usages(content, template_target, param_filters).length() > 0
}

///|
fn dump_page_matches_category(
  content : String,
  category_target : String?,
) -> Bool {
  match category_target {
    Some(category) => content_has_category_link(content, category)
    None => true
  }
}

///|
fn content_has_category_link(
  content : String,
  category_target : String,
) -> Bool {
  let len = content.length()
  let mut i = 0
  while i + 1 < len {
    if is_double_open_bracket(content, i) {
      let end = find_wikilink_end(content, i)
      if end > i {
        let snippet = content[i:end].to_string()
        if normalize_namespace_target(extract_wikilink_target(snippet)) ==
          category_target {
          return true
        }
        i = end
        continue
      }
    }
    i += 1
  }
  false
}

///|
fn extract_wikilink_target(snippet : String) -> String {
  if snippet.length() < 4 {
    return ""
  }
  let body = snippet[2:snippet.length() - 2].to_string().trim().to_string()
  body.split("|").to_array()[0].trim().to_string()
}

///|
fn find_wikilink_end(content : String, start : Int) -> Int {
  let len = content.length()
  let mut i = start + 2
  while i + 1 < len {
    if is_double_close_bracket(content, i) {
      return i + 2
    }
    i += 1
  }
  -1
}

///|
fn normalize_namespace_target(name : String) -> String {
  let normalized = name.replace(old="_", new=" ").trim().to_string()
  let segments = normalized.split(":").to_array()
  if segments.length() <= 1 {
    return normalized.to_lower()
  }
  segments[1:].join(":").trim().to_string().to_lower()
}

///|
fn fetch_all_template_usage_titles(
  endpoint : String,
  query : QueryContext,
  continue_token : String?,
  acc : Array[String],
  verbose : Bool,
) -> Result[Array[String], String] {
  let continue_suffix = match continue_token {
    Some(token) => " with continue=" + token
    None => " (first page)"
  }
  debug_log(verbose, "requesting usage page" + continue_suffix)
  let payload = match
    fetch_template_usage_page(endpoint, query, continue_token, verbose) {
    Ok(payload) => payload
    Err(message) => return Err(message)
  }
  let (titles, next_token) = match
    parse_template_usage_payload(payload, query.category_target, verbose) {
    Ok(result) => result
    Err(message) => return Err(message)
  }
  let next_token_suffix = match next_token {
    Some(token) => "; next continue=" + token
    None => "; no continuation"
  }
  debug_log(
    verbose,
    "parsed " +
    titles.length().to_string() +
    " titles from payload" +
    next_token_suffix,
  )
  for title in titles {
    acc.push(title)
  }
  match next_token {
    Some(token) =>
      fetch_all_template_usage_titles(
        endpoint,
        query,
        Some(token),
        acc,
        verbose,
      )
    None => Ok(acc)
  }
}

///|
fn sort_titles(titles : Array[String], sort_by : SortBy) -> Array[String] {
  if sort_by is Api {
    return titles.copy()
  }
  if titles.length() <= 1 {
    return titles.copy()
  }
  let pivot = titles[titles.length() / 2]
  let less = []
  let equal = []
  let greater = []
  for title in titles {
    let order = compare_titles_for_sort(title, pivot, sort_by)
    if order < 0 {
      less.push(title)
    } else if order > 0 {
      greater.push(title)
    } else {
      equal.push(title)
    }
  }
  concat_titles(
    sort_titles(less, sort_by),
    equal,
    sort_titles(greater, sort_by),
  )
}

///|
fn concat_titles(
  left : Array[String],
  middle : Array[String],
  right : Array[String],
) -> Array[String] {
  let merged = []
  append_titles(merged, left)
  append_titles(merged, middle)
  append_titles(merged, right)
  merged
}

///|
fn append_titles(target : Array[String], source : Array[String]) -> Unit {
  for title in source {
    target.push(title)
  }
}

///|
fn compare_titles_for_sort(
  left : String,
  right : String,
  sort_by : SortBy,
) -> Int {
  match sort_by {
    Api => 0
    TitleAsc => compare_titles(left, right)
    TitleDesc => compare_titles(right, left)
  }
}

///|
fn compare_titles(left : String, right : String) -> Int {
  left.lexical_compare(right)
}

///|
fn limit_titles(titles : Array[String], limit : Int?) -> Array[String] {
  match limit {
    None => titles.copy()
    Some(limit) => {
      let limited = []
      if limit <= 0 {
        return limited
      }
      for title in titles {
        if limited.length() >= limit {
          break
        }
        limited.push(title)
      }
      limited
    }
  }
}

///|
fn fetch_page_contents(
  endpoint : String,
  titles : Array[String],
) -> Result[Map[String, String], String] {
  let contents = {}
  let mut start = 0
  while start < titles.length() {
    let batch = slice_titles(titles, start, start + CONTENT_BATCH_SIZE)
    let payload = match fetch_page_content_batch(endpoint, batch) {
      Ok(payload) => payload
      Err(message) => return Err(message)
    }
    let parsed = match parse_page_content_payload(payload) {
      Ok(parsed) => parsed
      Err(message) => return Err(message)
    }
    for entry in parsed.iter() {
      contents[entry.0] = entry.1
    }
    start += CONTENT_BATCH_SIZE
  }
  Ok(contents)
}

///|
fn slice_titles(
  titles : Array[String],
  start : Int,
  end : Int,
) -> Array[String] {
  let slice = []
  let stop = if end < titles.length() { end } else { titles.length() }
  for i = start; i < stop; i = i + 1 {
    slice.push(titles[i])
  }
  slice
}

///|
fn fetch_page_content_batch(
  endpoint : String,
  titles : Array[String],
) -> Result[String, String] {
  let temp_path = temporary_output_path()
  let command = build_page_content_command(endpoint, titles, temp_path)
  let status = run_shell_command(command)
  if shell_exit_code(status) != 0 {
    ignore(unlink_ffi(string_to_utf8_bytes(temp_path, true)))
    return Err("curl request failed")
  }
  let contents = read_file_to_string(temp_path)
  ignore(unlink_ffi(string_to_utf8_bytes(temp_path, true)))
  contents
}

///|
fn build_page_content_command(
  endpoint : String,
  titles : Array[String],
  temp_path : String,
) -> String {
  let mut command = "curl --silent --show-error --fail --get"
  command += " --user-agent " +
    shell_quote("mediawiki-template-usage/0.1 (local MoonBit CLI)")
  command += " --data-urlencode " + shell_quote("action=query")
  command += " --data-urlencode " + shell_quote("format=json")
  command += " --data-urlencode " + shell_quote("formatversion=2")
  command += " --data-urlencode " + shell_quote("prop=revisions")
  command += " --data-urlencode " + shell_quote("rvprop=content")
  command += " --data-urlencode " + shell_quote("rvslots=main")
  command += " --data-urlencode " + shell_quote("titles=" + titles.join("|"))
  command += " " + shell_quote(endpoint)
  command += " > " + shell_quote(temp_path)
  command
}

///|
fn parse_page_content_payload(
  payload : String,
) -> Result[Map[String, String], String] {
  let parsed : Result[Json, @json.ParseError] = try? @json.parse(payload)
  match parsed {
    Err(error) => Err("invalid JSON response: \{error.to_string()}")
    Ok(json) => extract_page_content_response(json)
  }
}

///|
fn extract_page_content_response(
  json : Json,
) -> Result[Map[String, String], String] {
  guard json is Json::Object(root) else {
    return Err("response root is not an object")
  }
  guard root.get("query") is Some(Json::Object(query)) else {
    return Err("query is not an object")
  }
  guard query.get("pages") is Some(Json::Array(pages)) else {
    return Err("query.pages is not an array")
  }
  let contents = {}
  for page in pages {
    guard page is Json::Object(page_obj) else { continue }
    guard page_obj.get("title") is Some(Json::String(title)) else { continue }
    let content = extract_page_revision_content(page_obj)
    contents[title] = content
  }
  Ok(contents)
}

///|
fn extract_page_revision_content(page_obj : Map[String, Json]) -> String {
  match page_obj.get("revisions") {
    Some(Json::Array([Json::Object(revision), ..])) =>
      match revision.get("slots") {
        Some(Json::Object(slots)) =>
          match slots.get("main") {
            Some(Json::Object(main_slot)) =>
              match main_slot.get("content") {
                Some(Json::String(content)) => content
                _ => ""
              }
            _ => ""
          }
        _ => ""
      }
    _ => ""
  }
}

///|
fn print_page_contents(
  titles : Array[String],
  query : QueryContext,
  contents : Map[String, String],
) -> Unit {
  let mut first = true
  for title in titles {
    let snippets = extract_template_usages(
      contents.get_or_default(title, ""),
      query.template_target,
      query.param_filters,
    )
    if snippets.length() == 0 {
      continue
    }
    if !first {
      println("")
    }
    first = false
    println(render_page_content(title, snippets))
  }
}

///|
fn render_page_content(title : String, snippets : Array[String]) -> String {
  "= " + title + " =\n" + snippets.join("\n\n")
}

///|
fn extract_template_usages(
  content : String,
  template_target : String,
  param_filters : Array[TemplateParamFilter],
) -> Array[String] {
  let snippets = []
  let len = content.length()
  let mut i = 0
  while i + 1 < len {
    if is_double_open_brace(content, i) {
      let end = find_transclusion_end(content, i)
      if end > i {
        let snippet = content[i:end].to_string()
        if transclusion_matches_query(snippet, template_target, param_filters) {
          snippets.push(snippet)
        }
        i = end
        continue
      }
    }
    i += 1
  }
  snippets
}

///|
fn extract_transclusion_target(snippet : String) -> String {
  let parts = split_transclusion_parts(snippet)
  if parts.length() == 0 {
    return ""
  }
  let head = parts[0].trim().to_string()
  strip_transclusion_prefixes(head)
}

///|
fn transclusion_matches_query(
  snippet : String,
  template_target : String,
  param_filters : Array[TemplateParamFilter],
) -> Bool {
  if normalize_namespace_target(extract_transclusion_target(snippet)) !=
    template_target {
    return false
  }
  transclusion_matches_param_filters(snippet, param_filters)
}

///|
fn transclusion_matches_param_filters(
  snippet : String,
  param_filters : Array[TemplateParamFilter],
) -> Bool {
  if param_filters.length() == 0 {
    return true
  }
  let params = extract_transclusion_parameters(snippet)
  for filter in param_filters {
    if !transclusion_has_matching_param(params, filter) {
      return false
    }
  }
  true
}

///|
fn extract_transclusion_parameters(snippet : String) -> Array[String] {
  let parts = split_transclusion_parts(snippet)
  let params = []
  for i = 1; i < parts.length(); i = i + 1 {
    params.push(parts[i])
  }
  params
}

///|
fn transclusion_has_matching_param(
  params : Array[String],
  filter : TemplateParamFilter,
) -> Bool {
  let mut positional_index = 0
  for param in params {
    match split_top_level_assignment(param) {
      Some((name, value)) =>
        match filter.key {
          Named(expected_name) =>
            if name.to_lower() == expected_name && value == filter.value {
              return true
            }
          _ => ()
        }
      None => {
        positional_index += 1
        match filter.key {
          Positional(expected_index) =>
            if positional_index == expected_index && param == filter.value {
              return true
            }
          _ => ()
        }
      }
    }
  }
  false
}

///|
fn split_transclusion_parts(snippet : String) -> Array[String] {
  if snippet.length() < 4 {
    return []
  }
  split_top_level_segments(snippet[2:snippet.length() - 2].to_string(), '|')
}

///|
fn split_top_level_assignment(param : String) -> (String, String)? {
  let separator = find_top_level_delimiter(param, '=')
  if separator < 0 {
    return None
  }
  Some(
    (
      param[:separator].to_string().trim().to_string(),
      param[separator + 1:].to_string().trim().to_string(),
    ),
  )
}

///|
fn split_top_level_segments(
  content : String,
  delimiter : Char,
) -> Array[String] {
  let segments = []
  let len = content.length()
  let delimiter_code = delimiter.to_int()
  let mut brace_depth = 0
  let mut bracket_depth = 0
  let mut start = 0
  let mut i = 0
  while i < len {
    if i + 1 < len && is_double_open_brace(content, i) {
      brace_depth += 1
      i += 2
      continue
    }
    if i + 1 < len && is_double_close_brace(content, i) {
      if brace_depth > 0 {
        brace_depth -= 1
      }
      i += 2
      continue
    }
    if i + 1 < len && is_double_open_bracket(content, i) {
      bracket_depth += 1
      i += 2
      continue
    }
    if i + 1 < len && is_double_close_bracket(content, i) {
      if bracket_depth > 0 {
        bracket_depth -= 1
      }
      i += 2
      continue
    }
    if content.code_unit_at(i).to_int() == delimiter_code &&
      brace_depth == 0 &&
      bracket_depth == 0 {
      segments.push(content[start:i].to_string().trim().to_string())
      start = i + 1
    }
    i += 1
  }
  segments.push(content[start:len].to_string().trim().to_string())
  segments
}

///|
fn find_top_level_delimiter(content : String, delimiter : Char) -> Int {
  let len = content.length()
  let delimiter_code = delimiter.to_int()
  let mut brace_depth = 0
  let mut bracket_depth = 0
  let mut i = 0
  while i < len {
    if i + 1 < len && is_double_open_brace(content, i) {
      brace_depth += 1
      i += 2
      continue
    }
    if i + 1 < len && is_double_close_brace(content, i) {
      if brace_depth > 0 {
        brace_depth -= 1
      }
      i += 2
      continue
    }
    if i + 1 < len && is_double_open_bracket(content, i) {
      bracket_depth += 1
      i += 2
      continue
    }
    if i + 1 < len && is_double_close_bracket(content, i) {
      if bracket_depth > 0 {
        bracket_depth -= 1
      }
      i += 2
      continue
    }
    if content.code_unit_at(i).to_int() == delimiter_code &&
      brace_depth == 0 &&
      bracket_depth == 0 {
      return i
    }
    i += 1
  }
  -1
}

///|
fn strip_transclusion_prefixes(target : String) -> String {
  let normalized = target.trim().to_string()
  let lowered = normalized.to_lower()
  if lowered.has_prefix("subst:") {
    return strip_transclusion_prefixes(normalized[6:].to_string())
  }
  if lowered.has_prefix("safesubst:") {
    return strip_transclusion_prefixes(normalized[10:].to_string())
  }
  normalized
}

///|
fn find_transclusion_end(content : String, start : Int) -> Int {
  let len = content.length()
  let mut depth = 0
  let mut i = start
  while i + 1 < len {
    if is_double_open_brace(content, i) {
      depth += 1
      i += 2
      continue
    }
    if is_double_close_brace(content, i) {
      depth -= 1
      i += 2
      if depth == 0 {
        return i
      }
      continue
    }
    i += 1
  }
  -1
}

///|
fn is_double_open_brace(content : String, index : Int) -> Bool {
  content.code_unit_at(index).to_int() == 123 &&
  content.code_unit_at(index + 1).to_int() == 123
}

///|
fn is_double_open_bracket(content : String, index : Int) -> Bool {
  content.code_unit_at(index).to_int() == 91 &&
  content.code_unit_at(index + 1).to_int() == 91
}

///|
fn is_double_close_brace(content : String, index : Int) -> Bool {
  content.code_unit_at(index).to_int() == 125 &&
  content.code_unit_at(index + 1).to_int() == 125
}

///|
fn is_double_close_bracket(content : String, index : Int) -> Bool {
  content.code_unit_at(index).to_int() == 93 &&
  content.code_unit_at(index + 1).to_int() == 93
}

///|
fn fetch_template_usage_page(
  endpoint : String,
  query : QueryContext,
  continue_token : String?,
  verbose : Bool,
) -> Result[String, String] {
  let temp_path = temporary_output_path()
  let command = build_template_usage_command(
    endpoint, query, continue_token, temp_path,
  )
  debug_log(
    verbose,
    "running request: " +
    describe_template_usage_request(
      endpoint,
      query.template_title,
      query.category_title,
      continue_token,
    ),
  )
  let status = run_shell_command(command)
  if shell_exit_code(status) != 0 {
    debug_log(verbose, "curl exited with status " + status.to_string())
    ignore(unlink_ffi(string_to_utf8_bytes(temp_path, true)))
    return Err("curl request failed")
  }
  let contents = read_file_to_string(temp_path)
  ignore(unlink_ffi(string_to_utf8_bytes(temp_path, true)))
  match contents {
    Ok(payload) => {
      debug_log(
        verbose,
        "received payload with " +
        payload.length().to_string() +
        " characters: " +
        preview_text(payload, 240),
      )
      Ok(payload)
    }
    Err(message) => Err(message)
  }
}

///|
fn build_template_usage_command(
  endpoint : String,
  query : QueryContext,
  continue_token : String?,
  temp_path : String,
) -> String {
  let mut command = "curl --silent --show-error --fail --get"
  command += " --user-agent " +
    shell_quote("mediawiki-template-usage/0.1 (local MoonBit CLI)")
  command += " --data-urlencode " + shell_quote("action=query")
  command += " --data-urlencode " + shell_quote("format=json")
  command += " --data-urlencode " + shell_quote("formatversion=2")
  command += " --data-urlencode " + shell_quote("continue=")
  match query.category_title {
    Some(category_title) => {
      command += " --data-urlencode " + shell_quote("generator=embeddedin")
      command += " --data-urlencode " + shell_quote("geilimit=max")
      command += " --data-urlencode " +
        shell_quote("geititle=" + query.template_title)
      command += " --data-urlencode " + shell_quote("prop=categories")
      command += " --data-urlencode " + shell_quote("cllimit=max")
      command += " --data-urlencode " +
        shell_quote("clcategories=" + category_title)
      match continue_token {
        Some(token) =>
          command += " --data-urlencode " + shell_quote("geicontinue=" + token)
        None => ()
      }
    }
    None => {
      command += " --data-urlencode " + shell_quote("list=embeddedin")
      command += " --data-urlencode " + shell_quote("eilimit=max")
      command += " --data-urlencode " +
        shell_quote("eititle=" + query.template_title)
      match continue_token {
        Some(token) =>
          command += " --data-urlencode " + shell_quote("eicontinue=" + token)
        None => ()
      }
    }
  }
  command += " " + shell_quote(endpoint)
  command += " > " + shell_quote(temp_path)
  command
}

///|
fn parse_template_usage_payload(
  payload : String,
  category_target : String?,
  verbose : Bool,
) -> Result[(Array[String], String?), String] {
  let parsed : Result[Json, @json.ParseError] = try? @json.parse(payload)
  match parsed {
    Err(error) => {
      debug_log(
        verbose,
        "failed to parse JSON payload: " + preview_text(payload, 240),
      )
      Err("invalid JSON response: \{error.to_string()}")
    }
    Ok(json) =>
      match category_target {
        Some(category) =>
          extract_filtered_embeddedin_response(json, category, verbose)
        None => extract_embeddedin_response(json)
      }
  }
}

///|
fn extract_embeddedin_response(
  json : Json,
) -> Result[(Array[String], String?), String] {
  guard json is Json::Object(root) else {
    return Err("response root is not an object")
  }

  let titles = []
  match root.get("query") {
    Some(Json::Object(query)) =>
      match query.get("embeddedin") {
        Some(Json::Array(pages)) =>
          for page in pages {
            guard page is Json::Object(page_obj) else { continue }
            guard page_obj.get("title") is Some(Json::String(title)) else {
              continue
            }
            titles.push(title)
          }
        Some(_) => return Err("query.embeddedin is not an array")
        None => ()
      }
    Some(_) => return Err("query is not an object")
    None => ()
  }

  let next_token = match root.get("continue") {
    Some(Json::Object(cont)) =>
      match cont.get("eicontinue") {
        Some(Json::String(token)) => Some(token)
        Some(_) => return Err("continue.eicontinue is not a string")
        None => None
      }
    Some(_) => return Err("continue is not an object")
    None => None
  }

  Ok((titles, next_token))
}

///|
fn extract_filtered_embeddedin_response(
  json : Json,
  category_target : String,
  verbose : Bool,
) -> Result[(Array[String], String?), String] {
  guard json is Json::Object(root) else {
    return Err("response root is not an object")
  }

  let titles = []
  let mut page_count = 0
  let mut categorized_page_count = 0
  match root.get("query") {
    Some(Json::Object(query)) =>
      match query.get("pages") {
        Some(Json::Array(pages)) =>
          for page in pages {
            page_count += 1
            guard page is Json::Object(page_obj) else { continue }
            guard page_obj.get("title") is Some(Json::String(title)) else {
              continue
            }
            if page_obj.get("categories") is Some(Json::Array(_)) {
              categorized_page_count += 1
            }
            if page_matches_category(page_obj, category_target) {
              titles.push(title)
            }
          }
        Some(_) => return Err("query.pages is not an array")
        None => ()
      }
    Some(_) => return Err("query is not an object")
    None => ()
  }

  let next_token = match root.get("continue") {
    Some(Json::Object(cont)) =>
      match cont.get("geicontinue") {
        Some(Json::String(token)) => Some(token)
        Some(_) => return Err("continue.geicontinue is not a string")
        None => None
      }
    Some(_) => return Err("continue is not an object")
    None => None
  }

  debug_log(
    verbose,
    "category filter kept " +
    titles.length().to_string() +
    " of " +
    page_count.to_string() +
    " pages; " +
    categorized_page_count.to_string() +
    " pages included category data",
  )

  Ok((titles, next_token))
}

///|
fn describe_template_usage_request(
  endpoint : String,
  template_title : String,
  category_name : String?,
  continue_token : String?,
) -> String {
  let description = "endpoint=" + endpoint + ", template=" + template_title
  let description = match category_name {
    Some(category) =>
      description + ", category=" + category + ", mode=generator+categories"
    None => description + ", mode=embeddedin"
  }
  match continue_token {
    Some(token) => description + ", continue=" + token
    None => description
  }
}

///|
fn preview_text(value : String, limit : Int) -> String {
  let compact = value.replace(old="\n", new=" ").replace(old="\r", new=" ")
  if compact.length() <= limit {
    compact
  } else {
    compact[:limit].to_string() + "..."
  }
}

///|
fn debug_log(verbose : Bool, message : String) -> Unit {
  if verbose {
    println("[verbose] " + message)
  }
}

///|
fn page_matches_category(
  page_obj : Map[String, Json],
  category_target : String,
) -> Bool {
  match page_obj.get("categories") {
    Some(Json::Array(categories)) => {
      for category in categories {
        guard category is Json::Object(category_obj) else { continue }
        guard category_obj.get("title") is Some(Json::String(title)) else {
          continue
        }
        if normalize_namespace_target(title) == category_target {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn load_source_namespaces(
  endpoint : String,
  dump_files : Array[String],
  verbose : Bool,
) -> Result[SourceNamespaces, String] {
  if dump_files.length() > 0 {
    return load_dump_namespaces(dump_files[0])
  }
  load_api_namespaces(endpoint, verbose)
}

///|
fn build_query_context(
  raw_template_name : String,
  raw_category_name : String?,
  param_filters : Array[TemplateParamFilter],
  namespaces : SourceNamespaces,
) -> QueryContext {
  let template_title = normalize_namespace_title(
    raw_template_name,
    namespaces.template,
  )
  let category_title = match raw_category_name {
    Some(category) =>
      Some(normalize_namespace_title(category, namespaces.category))
    None => None
  }
  let category_target = match category_title {
    Some(category) => Some(normalize_namespace_target(category))
    None => None
  }
  {
    template_title,
    template_target: normalize_namespace_target(template_title),
    category_title,
    category_target,
    param_filters,
  }
}

///|
fn query_requires_content_scan(query : QueryContext) -> Bool {
  query.param_filters.length() > 0
}

///|
fn filter_titles_by_query(
  titles : Array[String],
  page_contents : Map[String, String],
  query : QueryContext,
) -> (Array[String], Map[String, String]) {
  let filtered_titles = []
  let filtered_contents = {}
  for title in titles {
    let content = page_contents.get_or_default(title, "")
    if page_contains_template(
        content,
        query.template_target,
        query.param_filters,
      ) {
      filtered_titles.push(title)
      filtered_contents[title] = content
    }
  }
  (filtered_titles, filtered_contents)
}

///|
fn normalize_template_name(
  template_name : String,
  namespace_info : NamespaceInfo,
) -> String {
  normalize_namespace_title(template_name, namespace_info)
}

///|
fn normalize_category_name(
  category_name : String,
  namespace_info : NamespaceInfo,
) -> String {
  normalize_namespace_title(category_name, namespace_info)
}

///|
fn normalize_namespace_title(
  name : String,
  namespace_info : NamespaceInfo,
) -> String {
  let trimmed = name.trim().to_string()
  if trimmed.is_empty() {
    return namespace_info.primary_name + ":"
  }
  match strip_known_namespace_prefix(trimmed, namespace_info) {
    Some(remainder) => namespace_info.primary_name + ":" + remainder
    None => namespace_info.primary_name + ":" + trimmed
  }
}

///|
fn strip_known_namespace_prefix(
  name : String,
  namespace_info : NamespaceInfo,
) -> String? {
  let prefixes = namespace_prefixes(namespace_info)
  let normalized = name.replace(old="_", new=" ").trim().to_string()
  for prefix in prefixes {
    let marker = prefix + ":"
    if normalized.has_prefix(marker) {
      return Some(normalized[marker.length():].trim().to_string())
    }
  }
  None
}

///|
fn namespace_prefixes(namespace_info : NamespaceInfo) -> Array[String] {
  let prefixes = [namespace_info.primary_name]
  match namespace_info.canonical_name {
    Some(canonical) => push_unique_string(prefixes, canonical)
    None => ()
  }
  for alias_name in namespace_info.aliases {
    push_unique_string(prefixes, alias_name)
  }
  prefixes
}

///|
fn push_unique_string(values : Array[String], value : String) -> Unit {
  for existing in values {
    if existing == value {
      return
    }
  }
  values.push(value)
}

///|
fn load_api_namespaces(
  endpoint : String,
  verbose : Bool,
) -> Result[SourceNamespaces, String] {
  let payload = match fetch_siteinfo_payload(endpoint, verbose) {
    Ok(payload) => payload
    Err(message) => return Err(message)
  }
  parse_api_namespaces_payload(payload)
}

///|
fn fetch_siteinfo_payload(
  endpoint : String,
  verbose : Bool,
) -> Result[String, String] {
  let temp_path = temporary_output_path()
  let command = build_siteinfo_command(endpoint, temp_path)
  debug_log(verbose, "requesting siteinfo namespaces from " + endpoint)
  let status = run_shell_command(command)
  if shell_exit_code(status) != 0 {
    ignore(unlink_ffi(string_to_utf8_bytes(temp_path, true)))
    return Err("curl request failed")
  }
  let contents = read_file_to_string(temp_path)
  ignore(unlink_ffi(string_to_utf8_bytes(temp_path, true)))
  contents
}

///|
fn build_siteinfo_command(endpoint : String, temp_path : String) -> String {
  let mut command = "curl --silent --show-error --fail --get"
  command += " --user-agent " +
    shell_quote("mediawiki-template-usage/0.1 (local MoonBit CLI)")
  command += " --data-urlencode " + shell_quote("action=query")
  command += " --data-urlencode " + shell_quote("format=json")
  command += " --data-urlencode " + shell_quote("formatversion=2")
  command += " --data-urlencode " + shell_quote("meta=siteinfo")
  command += " --data-urlencode " +
    shell_quote("siprop=namespaces|namespacealiases")
  command += " " + shell_quote(endpoint)
  command += " > " + shell_quote(temp_path)
  command
}

///|
fn parse_api_namespaces_payload(
  payload : String,
) -> Result[SourceNamespaces, String] {
  let parsed : Result[Json, @json.ParseError] = try? @json.parse(payload)
  match parsed {
    Err(error) => Err("invalid JSON response: \{error.to_string()}")
    Ok(json) => extract_api_namespaces(json)
  }
}

///|
fn extract_api_namespaces(json : Json) -> Result[SourceNamespaces, String] {
  guard json is Json::Object(root) else {
    return Err("response root is not an object")
  }
  guard root.get("query") is Some(Json::Object(query)) else {
    return Err("query is not an object")
  }
  guard query.get("namespaces") is Some(Json::Object(namespaces_obj)) else {
    return Err("query.namespaces is not an object")
  }
  let template = match namespace_info_from_api(namespaces_obj, 10) {
    Some(info) => info
    None => return Err("query.namespaces missing namespace 10")
  }
  let category = match namespace_info_from_api(namespaces_obj, 14) {
    Some(info) => info
    None => return Err("query.namespaces missing namespace 14")
  }
  match query.get("namespacealiases") {
    Some(Json::Array(aliases)) => {
      apply_namespace_aliases(template, 10, aliases)
      apply_namespace_aliases(category, 14, aliases)
    }
    Some(_) => return Err("query.namespacealiases is not an array")
    None => ()
  }
  Ok({ template, category })
}

///|
fn namespace_info_from_api(
  namespaces_obj : Map[String, Json],
  id : Int,
) -> NamespaceInfo? {
  match namespaces_obj.get(id.to_string()) {
    Some(Json::Object(namespace_obj)) =>
      Some(namespace_info_from_json(namespace_obj))
    _ => None
  }
}

///|
fn namespace_info_from_json(namespace_obj : Map[String, Json]) -> NamespaceInfo {
  let primary_name = match namespace_obj.get("name") {
    Some(Json::String(name)) => name
    _ => ""
  }
  let canonical_name = match namespace_obj.get("canonical") {
    Some(Json::String(name)) => Some(name)
    _ => None
  }
  { primary_name, canonical_name, aliases: [] }
}

///|
fn apply_namespace_aliases(
  namespace_info : NamespaceInfo,
  id : Int,
  aliases : Array[Json],
) -> Unit {
  let expected_id = id.to_string()
  for alias_entry in aliases {
    guard alias_entry is Json::Object(alias_obj) else { continue }
    let alias_id = match alias_obj.get("id") {
      Some(Json::Number(number, ..)) => number.to_string()
      Some(Json::String(text)) => text
      _ => continue
    }
    if alias_id != expected_id {
      continue
    }
    guard alias_obj.get("alias") is Some(Json::String(alias_name)) else {
      continue
    }
    push_unique_string(namespace_info.aliases, alias_name)
  }
}

///|
fn load_dump_namespaces(dump_file : String) -> Result[SourceNamespaces, String] {
  let payload = match read_dump_siteinfo_section(dump_file) {
    Ok(payload) => payload
    Err(message) => return Err(message)
  }
  parse_dump_namespaces(payload)
}

///|
fn read_dump_siteinfo_section(dump_file : String) -> Result[String, String] {
  let fd = open_ffi(string_to_utf8_bytes(dump_file, true), O_RDONLY, 0)
  if fd < 0 {
    return Err("failed to open dump file")
  }
  let buffer = Bytes::new(DUMP_READ_CHUNK_SIZE)
  let pending : Array[Byte] = []
  let end_marker = string_to_utf8_bytes("</siteinfo>", false).to_array()
  while true {
    let bytes_read = read_ffi(fd, buffer, DUMP_READ_CHUNK_SIZE)
    if bytes_read < 0 {
      ignore(close_ffi(fd))
      return Err("failed to read dump file")
    }
    if bytes_read == 0 {
      break
    }
    append_bytes_from_buffer(pending, buffer, bytes_read)
    let end = find_byte_substring(pending, end_marker, 0)
    if end >= 0 {
      ignore(close_ffi(fd))
      return Ok(
        utf8_bytes_to_string(
          Bytes::from_array(
            copy_byte_range(pending, 0, end + end_marker.length()),
          ),
        ),
      )
    }
  }
  ignore(close_ffi(fd))
  Err("dump file is missing <siteinfo>")
}

///|
fn parse_dump_namespaces(payload : String) -> Result[SourceNamespaces, String] {
  let siteinfo = extract_siteinfo_xml(payload)
  guard siteinfo is Some(siteinfo_xml) else {
    return Err("dump file is missing <siteinfo>")
  }
  let template = match extract_dump_namespace_info(siteinfo_xml, 10) {
    Some(info) => info
    None => return Err("dump siteinfo missing namespace 10")
  }
  let category = match extract_dump_namespace_info(siteinfo_xml, 14) {
    Some(info) => info
    None => return Err("dump siteinfo missing namespace 14")
  }
  Ok({ template, category })
}

///|
fn extract_siteinfo_xml(payload : String) -> String? {
  let start = find_substring(payload, "<siteinfo>", 0)
  if start < 0 {
    return None
  }
  let end = find_substring(payload, "</siteinfo>", start)
  if end < 0 {
    return None
  }
  Some(payload[start:end + 11].to_string())
}

///|
fn extract_dump_namespace_info(
  siteinfo_xml : String,
  id : Int,
) -> NamespaceInfo? {
  let start_tag = "<namespace key=\"" + id.to_string() + "\""
  let start = find_substring(siteinfo_xml, start_tag, 0)
  if start < 0 {
    return None
  }
  let open_end = find_substring(siteinfo_xml, ">", start)
  if open_end < 0 {
    return None
  }
  let end = find_substring(siteinfo_xml, "</namespace>", open_end + 1)
  if end < 0 {
    return None
  }
  let open_tag = siteinfo_xml[start:open_end + 1].to_string()
  let body = decode_xml_entities(siteinfo_xml[open_end + 1:end].to_string())
  let canonical_name = extract_xml_attribute(open_tag, "canonical")
  let aliases = []
  match canonical_name {
    Some(canonical) if canonical != body => aliases.push(canonical)
    _ => ()
  }
  Some({ primary_name: body, canonical_name, aliases })
}

///|
fn extract_xml_attribute(tag : String, name : String) -> String? {
  let marker = name + "=\""
  let start = find_substring(tag, marker, 0)
  if start < 0 {
    return None
  }
  let value_start = start + marker.length()
  let value_end = find_substring(tag, "\"", value_start)
  if value_end < 0 {
    return None
  }
  Some(decode_xml_entities(tag[value_start:value_end].to_string()))
}

///|
fn temporary_output_path() -> String {
  let cwd = @env.current_dir().unwrap_or(".")
  cwd + "/.mediawiki_template_usage_" + @env.now().to_string() + ".json"
}

///|
#cfg(not(platform="windows"))
fn shell_quote(value : String) -> String {
  "'" + value.replace(old="'", new="'\"'\"'") + "'"
}

///|
#cfg(platform="windows")
fn shell_quote(value : String) -> String {
  "\"" + value.replace(old="\"", new="\"\"").replace(old="%", new="%%") + "\""
}

///|
fn run_shell_command(command : String) -> Int {
  system_ffi(string_to_utf8_bytes(command, true))
}

///|
#cfg(not(platform="windows"))
fn shell_exit_code(status : Int) -> Int {
  if status < 0 {
    status
  } else {
    status / 256
  }
}

///|
#cfg(platform="windows")
fn shell_exit_code(status : Int) -> Int {
  status
}

///|
#cfg(not(platform="windows"))
fn path_is_directory(path : String) -> Bool {
  if path.is_empty() {
    return false
  }
  shell_exit_code(run_shell_command("test -d " + shell_quote(path))) == 0
}

///|
#cfg(not(platform="windows"))
fn path_is_file(path : String) -> Bool {
  if path.is_empty() {
    return false
  }
  shell_exit_code(run_shell_command("test -f " + shell_quote(path))) == 0
}

///|
#cfg(platform="windows")
fn path_is_directory(path : String) -> Bool {
  if path.is_empty() {
    return false
  }
  shell_exit_code(
    run_shell_command(
      "if exist " + shell_quote(path + "\\NUL") + " (exit 0) else (exit 1)",
    ),
  ) ==
  0
}

///|
#cfg(platform="windows")
fn path_is_file(path : String) -> Bool {
  if path.is_empty() {
    return false
  }
  shell_exit_code(
    run_shell_command(
      "if exist " + shell_quote(path) + " (exit 0) else (exit 1)",
    ),
  ) ==
  0
}

///|
fn read_file_to_string(path : String) -> Result[String, String] {
  let path_bytes = string_to_utf8_bytes(path, true)
  let fd = open_ffi(path_bytes, O_RDONLY, 0)
  if fd < 0 {
    return Err("failed to open response file")
  }
  let size = lseek_ffi(fd, 0, SEEK_END)
  if size < 0 {
    ignore(close_ffi(fd))
    return Err("failed to stat response file")
  }
  ignore(lseek_ffi(fd, 0, SEEK_SET))
  let buffer = Bytes::new(size)
  let read = read_ffi(fd, buffer, size)
  if read < 0 {
    ignore(close_ffi(fd))
    return Err("failed to read response file")
  }
  ignore(close_ffi(fd))
  Ok(utf8_bytes_to_string(buffer[:read].to_bytes()))
}

///|
fn string_to_utf8_bytes(str : String, append_nul : Bool) -> Bytes {
  let res : Array[Byte] = []
  let len = str.length()
  let mut i = 0
  while i < len {
    let mut c = str.code_unit_at(i).to_int()
    if 0xD800 <= c && c <= 0xDBFF {
      c -= 0xD800
      i += 1
      let low = str.code_unit_at(i).to_int() - 0xDC00
      c = (c << 10) + low + 0x10000
    }
    if c < 0x80 {
      res.push(c.to_byte())
    } else if c < 0x800 {
      res.push((0xC0 + (c >> 6)).to_byte())
      res.push((0x80 + (c & 0x3F)).to_byte())
    } else if c < 0x10000 {
      res.push((0xE0 + (c >> 12)).to_byte())
      res.push((0x80 + ((c >> 6) & 0x3F)).to_byte())
      res.push((0x80 + (c & 0x3F)).to_byte())
    } else {
      res.push((0xF0 + (c >> 18)).to_byte())
      res.push((0x80 + ((c >> 12) & 0x3F)).to_byte())
      res.push((0x80 + ((c >> 6) & 0x3F)).to_byte())
      res.push((0x80 + (c & 0x3F)).to_byte())
    }
    i += 1
  }
  if append_nul {
    res.push(0)
  }
  Bytes::from_array(res)
}

///|
fn utf8_bytes_to_string(bytes : Bytes) -> String {
  let res = StringBuilder::new()
  let len = bytes.length()
  let mut i = 0
  while i < len {
    let mut c = bytes[i].to_int()
    if c == 0 {
      break
    } else if c < 0x80 {
      res.write_char(c.unsafe_to_char())
      i += 1
    } else if c < 0xE0 {
      if i + 1 >= len {
        break
      }
      c = ((c & 0x1F) << 6) | (bytes[i + 1].to_int() & 0x3F)
      res.write_char(c.unsafe_to_char())
      i += 2
    } else if c < 0xF0 {
      if i + 2 >= len {
        break
      }
      c = ((c & 0x0F) << 12) |
        ((bytes[i + 1].to_int() & 0x3F) << 6) |
        (bytes[i + 2].to_int() & 0x3F)
      res.write_char(c.unsafe_to_char())
      i += 3
    } else {
      if i + 3 >= len {
        break
      }
      c = ((c & 0x07) << 18) |
        ((bytes[i + 1].to_int() & 0x3F) << 12) |
        ((bytes[i + 2].to_int() & 0x3F) << 6) |
        (bytes[i + 3].to_int() & 0x3F)
      c -= 0x10000
      res.write_char(((c >> 10) + 0xD800).unsafe_to_char())
      res.write_char(((c & 0x3FF) + 0xDC00).unsafe_to_char())
      i += 4
    }
  }
  res.to_string()
}

///|
