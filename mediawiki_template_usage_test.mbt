///|
test "parse config accepts explicit limit" {
  let config = @mediawiki_template_usage.parse_config([
    "/tmp/mediawiki-template-usage", "https://en.wikipedia.org/w/api.php", "Citation needed",
    "--limit", "3", "--sort-by", "title-asc", "--show-content",
  ]) catch {
    err => fail("parse_config failed: \{err}")
  }
  assert_eq(config, {
    endpoint: "https://en.wikipedia.org/w/api.php",
    template_name: "Citation needed",
    limit: Some(3),
    sort_by: @mediawiki_template_usage.TitleAsc,
    show_content: true,
  })
}

///|
test "parse config accepts dump directory source" {
  let config = @mediawiki_template_usage.parse_config([
    "/tmp/mediawiki-template-usage", "/tmp", "Citation needed",
  ]) catch {
    err => fail("parse_config failed: \{err}")
  }
  assert_eq(config.endpoint, "/tmp")
  assert_eq(config.template_name, "Citation needed")
  assert_eq(config.limit, Some(10))
  assert_eq(config.sort_by, @mediawiki_template_usage.Api)
  assert_eq(config.show_content, false)
}

///|
test "parse config resolves endpoint aliases" {
  let config = @mediawiki_template_usage.parse_config([
    "/tmp/mediawiki-template-usage", "enwp", "Citation needed",
  ]) catch {
    err => fail("parse_config failed: \{err}")
  }
  assert_eq(config.endpoint, "https://en.wikipedia.org/w/api.php")
  assert_eq(config.template_name, "Citation needed")
  assert_eq(config.limit, Some(10))
  assert_eq(config.sort_by, @mediawiki_template_usage.Api)
  assert_eq(config.show_content, false)
}

///|
test "parse config resolves shared project aliases" {
  let config = @mediawiki_template_usage.parse_config([
    "/tmp/mediawiki-template-usage", "commons", "Featured picture",
  ]) catch {
    err => fail("parse_config failed: \{err}")
  }
  assert_eq(config.endpoint, "https://commons.wikimedia.org/w/api.php")
  assert_eq(config.limit, Some(10))
  assert_eq(config.sort_by, @mediawiki_template_usage.Api)
  assert_eq(config.show_content, false)
}

///|
test "parse config prefers args after separator" {
  let config = @mediawiki_template_usage.parse_config([
    "moon", "run", "cmd/main", "--", "https://www.mediawiki.org/w/api.php", "Main page",
    "-l", "2",
  ]) catch {
    err => fail("parse_config failed: \{err}")
  }
  assert_eq(config, {
    endpoint: "https://www.mediawiki.org/w/api.php",
    template_name: "Main page",
    limit: Some(2),
    sort_by: @mediawiki_template_usage.Api,
    show_content: false,
  })
}

///|
test "render help mentions limit and template" {
  let help = @mediawiki_template_usage.command().render_help()
  assert_true(help.contains("--limit"))
  assert_true(help.contains("[default: 10]"))
  assert_true(help.contains("--sort-by"))
  assert_true(help.contains("--show-content"))
  assert_true(help.contains("template"))
  assert_true(help.contains("API or a local Wikimedia dumps folder"))
  assert_true(help.contains("Examples:"))
  assert_true(
    help.contains("./mediawiki-template-usage enwp \"Citation needed\""),
  )
  assert_true(
    help.contains(
      "./mediawiki-template-usage ./dumps/enwiki \"Citation needed\"",
    ),
  )
  assert_true(help.contains("moon run cmd/main -- enwp \"Citation needed\""))
}
