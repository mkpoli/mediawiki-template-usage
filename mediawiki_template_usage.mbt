///|
const SEEK_SET = 0

///|
const SEEK_END = 2

///|
const O_RDONLY = 0

///|
const CONTENT_BATCH_SIZE = 20

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
  template_name : String
  category_name : String?
  limit : Int?
  sort_by : SortBy
  show_content : Bool
  verbose : Bool
} derive(Eq)

///|
pub impl Show for Config with output(self, logger) {
  logger.write_string("Config::{ endpoint: ")
  logger.write_object(self.endpoint)
  logger.write_string(", template_name: ")
  logger.write_object(self.template_name)
  logger.write_string(", category_name: ")
  logger.write_object(self.category_name)
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
pub fn run_cli(args : Array[String]) -> Unit {
  try {
    let config = parse_config(args)
    debug_log(config.verbose, "config: " + config.to_string())
    match
      fetch_all_template_usages(
        config.endpoint,
        config.template_name,
        config.category_name,
        config.sort_by,
        config.limit,
        config.verbose,
      ) {
      Ok(titles) =>
        output_results(
          config.endpoint,
          config.template_name,
          titles,
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
    about="List pages that transclude a MediaWiki template via the embeddedin API.\n\nExamples:\n  Production: ./mediawiki-template-usage enwp \"Citation needed\"\n  Production with category filter: ./mediawiki-template-usage enwp \"Citation needed\" --category \"Living people\"\n  Development: moon run cmd/main -- enwp \"Citation needed\"",
    version="0.1.2",
    arg_required_else_help=true,
    flags=[
      @argparse.FlagArg::new(
        "show-content",
        about="Fetch and print only matching template usages for the final results. Best used with --limit.",
      ),
      @argparse.FlagArg::new(
        "verbose",
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
        about="Sort order: api, title-asc, or title-desc.",
        default_values=["api"],
      ),
      @argparse.OptionArg::new(
        "category",
        short='c',
        about="Only include pages that are in the given category, with or without the Category: prefix.",
      ),
    ],
    positionals=[
      @argparse.PositionArg::new(
        "endpoint",
        about="MediaWiki API endpoint or alias, for example https://en.wikipedia.org/w/api.php, enwp, commons, or wikidata",
        num_args=@argparse.ValueRange::single(),
      ),
      @argparse.PositionArg::new(
        "template",
        about="Template name, with or without the Template: prefix",
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
  guard values.get("endpoint") is Some([raw_endpoint, ..]) else {
    raise Message("missing endpoint argument")
  }
  guard values.get("template") is Some([template_name, ..]) else {
    raise Message("missing template argument")
  }
  let endpoint = resolve_endpoint(raw_endpoint)
  let category_name = match values.get("category") {
    Some([raw_category, ..]) => Some(normalize_category_name(raw_category))
    _ => None
  }
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
    template_name,
    category_name,
    limit,
    sort_by,
    show_content,
    verbose,
  }
}

///|
fn output_results(
  endpoint : String,
  template_name : String,
  titles : Array[String],
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
  debug_log(
    verbose,
    "fetching page contents in batches of " + CONTENT_BATCH_SIZE.to_string(),
  )
  match fetch_page_contents(endpoint, titles) {
    Ok(contents) => print_page_contents(titles, template_name, contents)
    Err(message) => println("error: \{message}")
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
    _ => resolve_language_project_alias(endpoint)
  }
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
    "unknown endpoint alias '\{shorthand}'. Use a full https://.../w/api.php endpoint or a known alias like enwp, commons, meta, mediawiki, or wikidata",
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
fn fetch_all_template_usages(
  endpoint : String,
  template_name : String,
  category_name : String?,
  sort_by : SortBy,
  limit : Int?,
  verbose : Bool,
) -> Result[Array[String], String] {
  let normalized_template = normalize_template_name(template_name)
  let category_suffix = match category_name {
    Some(category) => " in " + category
    None => " without category filter"
  }
  debug_log(
    verbose,
    "fetching usages for " + normalized_template + category_suffix,
  )
  let titles = match
    fetch_all_template_usage_titles(
      endpoint,
      normalized_template,
      category_name,
      None,
      [],
      verbose,
    ) {
    Ok(titles) => titles
    Err(message) => return Err(message)
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
  Ok(limited)
}

///|
fn fetch_all_template_usage_titles(
  endpoint : String,
  template_title : String,
  category_name : String?,
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
    fetch_template_usage_page(
      endpoint, template_title, category_name, continue_token, verbose,
    ) {
    Ok(payload) => payload
    Err(message) => return Err(message)
  }
  let (titles, next_token) = match
    parse_template_usage_payload(payload, category_name, verbose) {
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
        template_title,
        category_name,
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
  if status != 0 {
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
  template_name : String,
  contents : Map[String, String],
) -> Unit {
  let mut first = true
  for title in titles {
    let snippets = extract_template_usages(
      contents.get_or_default(title, ""),
      template_name,
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
  template_name : String,
) -> Array[String] {
  let snippets = []
  let normalized_template = normalize_template_target(template_name)
  let len = content.length()
  let mut i = 0
  while i + 1 < len {
    if is_double_open_brace(content, i) {
      let end = find_transclusion_end(content, i)
      if end > i {
        let snippet = content[i:end].to_string()
        if normalize_template_target(extract_transclusion_target(snippet)) ==
          normalized_template {
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
  if snippet.length() < 4 {
    return ""
  }
  let body = snippet[2:snippet.length() - 2].to_string().trim().to_string()
  let head = body.split("|").to_array()[0].trim().to_string()
  strip_transclusion_prefixes(head)
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
fn normalize_template_target(template_name : String) -> String {
  let normalized = strip_transclusion_prefixes(
    template_name.replace(old="_", new=" ").trim().to_string(),
  )
  let lowered = normalized.to_lower()
  if lowered.has_prefix("template:") {
    lowered[9:].trim().to_string()
  } else {
    lowered
  }
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
fn is_double_close_brace(content : String, index : Int) -> Bool {
  content.code_unit_at(index).to_int() == 125 &&
  content.code_unit_at(index + 1).to_int() == 125
}

///|
fn fetch_template_usage_page(
  endpoint : String,
  template_title : String,
  category_name : String?,
  continue_token : String?,
  verbose : Bool,
) -> Result[String, String] {
  let temp_path = temporary_output_path()
  let command = build_template_usage_command(
    endpoint, template_title, category_name, continue_token, temp_path,
  )
  debug_log(
    verbose,
    "running request: " +
    describe_template_usage_request(
      endpoint, template_title, category_name, continue_token,
    ),
  )
  let status = run_shell_command(command)
  if status != 0 {
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
  template_title : String,
  category_name : String?,
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
  match category_name {
    Some(category_title) => {
      command += " --data-urlencode " + shell_quote("generator=embeddedin")
      command += " --data-urlencode " + shell_quote("geilimit=max")
      command += " --data-urlencode " +
        shell_quote("geititle=" + template_title)
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
      command += " --data-urlencode " + shell_quote("eititle=" + template_title)
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
  category_name : String?,
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
      match category_name {
        Some(category_title) =>
          extract_filtered_embeddedin_response(json, category_title, verbose)
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
  category_title : String,
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
            if page_matches_category(page_obj, category_title) {
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
  category_title : String,
) -> Bool {
  match page_obj.get("categories") {
    Some(Json::Array(categories)) => {
      for category in categories {
        guard category is Json::Object(category_obj) else { continue }
        guard category_obj.get("title") is Some(Json::String(title)) else {
          continue
        }
        if title == category_title {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn normalize_template_name(template_name : String) -> String {
  let trimmed = template_name.trim().to_string()
  if trimmed.has_prefix("Template:") {
    trimmed
  } else {
    "Template:" + trimmed
  }
}

///|
fn normalize_category_name(category_name : String) -> String {
  let trimmed = category_name.trim().to_string()
  if trimmed.has_prefix("Category:") {
    trimmed
  } else {
    "Category:" + trimmed
  }
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
