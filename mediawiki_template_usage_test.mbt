///|
test "parse config accepts explicit limit" {
  let config = @mediawiki_template_usage.parse_config([
    "/tmp/mediawiki-template-usage", "https://en.wikipedia.org/w/api.php", "Citation needed",
    "--limit", "3", "--sort-by", "title-asc",
  ]) catch {
    err => fail("parse_config failed: \{err}")
  }
  assert_eq(config, {
    endpoint: "https://en.wikipedia.org/w/api.php",
    template_name: "Citation needed",
    limit: Some(3),
    sort_by: @mediawiki_template_usage.TitleAsc,
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
  assert_eq(config.limit, None)
  assert_eq(config.sort_by, @mediawiki_template_usage.Api)
}

///|
test "parse config resolves shared project aliases" {
  let config = @mediawiki_template_usage.parse_config([
    "/tmp/mediawiki-template-usage", "commons", "Featured picture",
  ]) catch {
    err => fail("parse_config failed: \{err}")
  }
  assert_eq(config.endpoint, "https://commons.wikimedia.org/w/api.php")
  assert_eq(config.sort_by, @mediawiki_template_usage.Api)
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
  })
}

///|
test "render help mentions limit and template" {
  let help = @mediawiki_template_usage.command().render_help()
  assert_true(help.contains("--limit"))
  assert_true(help.contains("--sort-by"))
  assert_true(help.contains("template"))
  assert_true(help.contains("embeddedin API"))
}
