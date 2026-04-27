///|
test "parse config accepts explicit limit" {
  let config = @mediawiki_template_usage.parse_config([
    "/tmp/mediawiki-template-usage", "https://en.wikipedia.org/w/api.php", "Citation needed",
    "--limit", "3", "--sort-by", "title-asc", "--show-content", "--category", "Living people",
    "-v",
  ]) catch {
    err => fail("parse_config failed: \{err}")
  }
  assert_eq(config.endpoint, "https://en.wikipedia.org/w/api.php")
  assert_eq(config.dump_files, [])
  assert_eq(config.template_name, "Citation needed")
  assert_eq(config.category_name, Some("Category:Living people"))
  assert_eq(config.limit, Some(3))
  assert_eq(config.sort_by, @mediawiki_template_usage.TitleAsc)
  assert_eq(config.show_content, true)
  assert_eq(config.verbose, true)
}

///|
test "parse config accepts dump file source" {
  let dump_file = "/tmp/mediawiki-template-usage-test.xml"
  @mediawiki_template_usage.write_string_to_file_for_test(dump_file, "<page/>")
  let config = @mediawiki_template_usage.parse_config([
    "/tmp/mediawiki-template-usage", dump_file, "Citation needed",
  ]) catch {
    err => {
      @mediawiki_template_usage.remove_file_for_test(dump_file)
      fail("parse_config failed: \{err}")
    }
  }
  @mediawiki_template_usage.remove_file_for_test(dump_file)
  assert_eq(config.endpoint, dump_file)
  assert_eq(config.dump_files, [dump_file])
  assert_eq(config.template_name, "Citation needed")
  assert_eq(config.limit, Some(10))
  assert_eq(config.sort_by, @mediawiki_template_usage.Api)
  assert_eq(config.show_content, false)
}

///|
test "parse config accepts additional dump files" {
  let primary = "/tmp/mediawiki-template-usage-test-1.xml"
  let secondary = "/tmp/mediawiki-template-usage-test-2.xml"
  let tertiary = "/tmp/mediawiki-template-usage-test-3.xml"
  @mediawiki_template_usage.write_string_to_file_for_test(primary, "<page/>")
  @mediawiki_template_usage.write_string_to_file_for_test(secondary, "<page/>")
  @mediawiki_template_usage.write_string_to_file_for_test(tertiary, "<page/>")
  let config = @mediawiki_template_usage.parse_config([
    "/tmp/mediawiki-template-usage", primary, "Citation needed", "--dump-file", secondary,
    "--dump-file", tertiary,
  ]) catch {
    err => {
      @mediawiki_template_usage.remove_file_for_test(primary)
      @mediawiki_template_usage.remove_file_for_test(secondary)
      @mediawiki_template_usage.remove_file_for_test(tertiary)
      fail("parse_config failed: \{err}")
    }
  }
  @mediawiki_template_usage.remove_file_for_test(primary)
  @mediawiki_template_usage.remove_file_for_test(secondary)
  @mediawiki_template_usage.remove_file_for_test(tertiary)
  assert_eq(config.endpoint, primary)
  assert_eq(config.dump_files, [primary, secondary, tertiary])
}

///|
test "parse config resolves endpoint aliases" {
  let config = @mediawiki_template_usage.parse_config([
    "/tmp/mediawiki-template-usage", "enwp", "Citation needed",
  ]) catch {
    err => fail("parse_config failed: \{err}")
  }
  assert_eq(config.endpoint, "https://en.wikipedia.org/w/api.php")
  assert_eq(config.dump_files, [])
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
  assert_eq(config.dump_files, [])
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
  assert_eq(config.endpoint, "https://www.mediawiki.org/w/api.php")
  assert_eq(config.dump_files, [])
  assert_eq(config.template_name, "Main page")
  assert_eq(config.category_name, None)
  assert_eq(config.limit, Some(2))
  assert_eq(config.sort_by, @mediawiki_template_usage.Api)
  assert_eq(config.show_content, false)
  assert_eq(config.verbose, false)
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
  assert_true(help.contains("-h, --help"))
  assert_true(help.contains("--limit"))
  assert_true(help.contains("-l, --limit"))
  assert_true(help.contains("[default: 10]"))
  assert_true(help.contains("--sort-by"))
  assert_true(help.contains("--category"))
  assert_true(help.contains("-v, --verbose"))
  assert_true(help.contains("--verbose"))
  assert_true(help.contains("--show-content"))
  assert_true(help.contains("--dump-file"))
  assert_true(help.contains("template"))
  assert_true(help.contains("API or local Wikimedia XML dump files"))
  assert_true(help.contains("Examples:"))
  assert_true(
    help.contains("./mediawiki-template-usage enwp \"Citation needed\""),
  )
  assert_true(help.contains("jawiktionary-2026-04-01-p7p579548.xml"))
  assert_true(help.contains("--category \"Living people\""))
  assert_true(help.contains("moon run cmd/main -- enwp \"Citation needed\""))
}
