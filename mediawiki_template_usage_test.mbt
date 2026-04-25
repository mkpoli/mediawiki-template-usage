///|
test "parse config accepts explicit limit" {
  let config = @mediawiki_template_usage.parse_config([
    "/tmp/mediawiki-template-usage", "https://en.wikipedia.org/w/api.php", "Citation needed",
    "--limit", "3", "--sort-by", "title-asc", "--show-content", "--category", "Living people",
    "-v",
  ]) catch {
    err => fail("parse_config failed: \{err}")
  }
  assert_eq(config, {
    endpoint: "https://en.wikipedia.org/w/api.php",
    template_name: "Citation needed",
    category_name: Some("Category:Living people"),
    limit: Some(3),
    sort_by: @mediawiki_template_usage.TitleAsc,
    show_content: true,
    verbose: true,
  })
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
  assert_eq(config.category_name, None)
  assert_eq(config.limit, Some(10))
  assert_eq(config.sort_by, @mediawiki_template_usage.Api)
  assert_eq(config.show_content, false)
  assert_eq(config.verbose, false)
}

///|
test "parse config resolves shared project aliases" {
  let config = @mediawiki_template_usage.parse_config([
    "/tmp/mediawiki-template-usage", "commons", "Featured picture",
  ]) catch {
    err => fail("parse_config failed: \{err}")
  }
  assert_eq(config.endpoint, "https://commons.wikimedia.org/w/api.php")
  assert_eq(config.category_name, None)
  assert_eq(config.limit, Some(10))
  assert_eq(config.sort_by, @mediawiki_template_usage.Api)
  assert_eq(config.show_content, false)
  assert_eq(config.verbose, false)
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
    category_name: None,
    limit: Some(2),
    sort_by: @mediawiki_template_usage.Api,
    show_content: false,
    verbose: false,
  })
}

///|
test "parse config accepts category with prefix" {
  let config = @mediawiki_template_usage.parse_config([
    "/tmp/mediawiki-template-usage", "enwp", "Citation needed", "--category", "Category:All articles with unsourced statements",
  ]) catch {
    err => fail("parse_config failed: \{err}")
  }
  assert_eq(
    config.category_name,
    Some("Category:All articles with unsourced statements"),
  )
  assert_eq(config.verbose, false)
}

///|
test "parse config accepts verbose long flag" {
  let config = @mediawiki_template_usage.parse_config([
    "/tmp/mediawiki-template-usage", "enwp", "Citation needed", "--verbose",
  ]) catch {
    err => fail("parse_config failed: \{err}")
  }
  assert_eq(config.verbose, true)
}

///|
test "render help mentions limit and template" {
  let help = @mediawiki_template_usage.command().render_help()
  assert_true(help.contains("--limit"))
  assert_true(help.contains("[default: 10]"))
  assert_true(help.contains("--sort-by"))
  assert_true(help.contains("--category"))
  assert_true(help.contains("--verbose"))
  assert_true(help.contains("--show-content"))
  assert_true(help.contains("template"))
  assert_true(help.contains("embeddedin API"))
  assert_true(help.contains("Examples:"))
  assert_true(
    help.contains("./mediawiki-template-usage enwp \"Citation needed\""),
  )
  assert_true(help.contains("--category \"Living people\""))
  assert_true(help.contains("moon run cmd/main -- enwp \"Citation needed\""))
}
