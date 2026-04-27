///|
test "normalize template name" {
  let namespace_info = {
    primary_name: "Template",
    canonical_name: Some("Template"),
    aliases: ["テンプレート"],
  }
  assert_eq(
    normalize_template_name("Infobox person", namespace_info),
    "Template:Infobox person",
  )
  assert_eq(
    normalize_template_name("Template:Citation needed", namespace_info),
    "Template:Citation needed",
  )
  assert_eq(
    normalize_template_name(
      "テンプレート:Citation needed", namespace_info,
    ),
    "Template:Citation needed",
  )
}

///|
test "extract embeddedin response and continue token" {
  let payload =
    #|{
    #|  "continue": { "eicontinue": "10|Template:Infobox_person", "continue": "-||" },
    #|  "query": {
    #|    "embeddedin": [
    #|      { "pageid": 1, "title": "Page One" },
    #|      { "pageid": 2, "title": "Page Two" }
    #|    ]
    #|  }
    #|}
  match parse_template_usage_payload(payload, None, false) {
    Ok((titles, Some(token))) => {
      assert_eq(titles, ["Page One", "Page Two"])
      assert_eq(token, "10|Template:Infobox_person")
    }
    _ => panic()
  }
}

///|
test "extract filtered embeddedin response and continue token" {
  let payload =
    #|{
    #|  "continue": { "geicontinue": "10|Template:Infobox_person", "continue": "||" },
    #|  "query": {
    #|    "pages": [
    #|      {
    #|        "title": "Page One",
    #|        "categories": [
    #|          { "title": "Category:Living people" }
    #|        ]
    #|      },
    #|      {
    #|        "title": "Page Two",
    #|        "categories": [
    #|          { "title": "Category:Other" }
    #|        ]
    #|      }
    #|    ]
    #|  }
    #|}
  match parse_template_usage_payload(payload, Some("living people"), false) {
    Ok((titles, Some(token))) => {
      assert_eq(titles, ["Page One"])
      assert_eq(token, "10|Template:Infobox_person")
    }
    _ => panic()
  }
}

///|
test "limit titles caps output size" {
  let titles = ["A", "B", "C"]
  assert_eq(limit_titles(titles, Some(2)), ["A", "B"])
  assert_eq(limit_titles(titles, None), ["A", "B", "C"])
  assert_eq(limit_titles(titles, Some(0)).length(), 0)
}

///|
test "resolve language project aliases" {
  assert_eq(resolve_endpoint("enwp"), "https://en.wikipedia.org/w/api.php")
  assert_eq(resolve_endpoint("dewikt"), "https://de.wiktionary.org/w/api.php")
  assert_eq(resolve_endpoint("frvoy"), "https://fr.wikivoyage.org/w/api.php")
}

///|
test "prepend dump file keeps source first" {
  assert_eq(
    prepend_dump_file("/tmp/jawiktionary-2026-04-01-p7p579548.xml", [
      "/tmp/jawiktionary-2026-04-01-p7p579549.xml",
    ]),
    [
      "/tmp/jawiktionary-2026-04-01-p7p579548.xml", "/tmp/jawiktionary-2026-04-01-p7p579549.xml",
    ],
  )
}

///|
test "split dump pages extracts page fragments" {
  let payload =
    #|<mediawiki><page><title>A</title></page><page><title>B</title></page></mediawiki>
  assert_eq(split_dump_pages(payload), [
    "<page><title>A</title></page>", "<page><title>B</title></page>",
  ])
}

///|
test "parse dump xml extracts titles and content" {
  let query = build_query_context("Citation needed", None, {
    template: {
      primary_name: "Template",
      canonical_name: Some("Template"),
      aliases: [],
    },
    category: {
      primary_name: "Category",
      canonical_name: Some("Category"),
      aliases: [],
    },
  })
  let payload =
    #|<mediawiki>
    #|  <page>
    #|    <title>Page One</title>
    #|    <revision><text>{{Citation needed|date=2024}}</text></revision>
    #|  </page>
    #|  <page>
    #|    <title>Page &amp; Two</title>
    #|    <revision><text>Before &lt;tag&gt;{{Citation needed}}&lt;/tag&gt;</text></revision>
    #|  </page>
    #|</mediawiki>
  let (titles, contents) = match parse_dump_xml(payload, query) {
    Ok(result) => result
    Err(err) => fail(err)
  }
  assert_eq(titles, ["Page One", "Page & Two"])
  assert_eq(contents.get("Page One"), Some("{{Citation needed|date=2024}}"))
  assert_eq(
    contents.get("Page & Two"),
    Some("Before <tag>{{Citation needed}}</tag>"),
  )
}

///|
test "parse dump xml applies category filter" {
  let query = build_query_context(
    "Citation needed",
    Some("カテゴリ:Living people"),
    {
      template: {
        primary_name: "Template",
        canonical_name: Some("Template"),
        aliases: [],
      },
      category: {
        primary_name: "Category",
        canonical_name: Some("Category"),
        aliases: ["カテゴリ"],
      },
    },
  )
  let payload =
    #|<mediawiki>
    #|  <page>
    #|    <title>Page One</title>
    #|    <revision><text>{{Citation needed}} [[カテゴリ:Living people]]</text></revision>
    #|  </page>
    #|  <page>
    #|    <title>Page Two</title>
    #|    <revision><text>{{Citation needed}} [[Category:Physics]]</text></revision>
    #|  </page>
    #|</mediawiki>
  let (titles, contents) = match parse_dump_xml(payload, query) {
    Ok(result) => result
    Err(err) => fail(err)
  }
  assert_eq(titles, ["Page One"])
  assert_eq(
    contents.get("Page One"),
    Some("{{Citation needed}} [[カテゴリ:Living people]]"),
  )
  assert_eq(contents.get("Page Two"), None)
}

///|
test "parse dump page extracts title and revision text" {
  let page = parse_dump_page(
    "<page><title>Sample</title><revision><text>Body</text></revision></page>",
  )
  match page {
    Some(page) => {
      assert_eq(page.title, "Sample")
      assert_eq(page.content, "Body")
    }
    None => fail("expected parsed page")
  }
}

///|
test "sort titles by title desc" {
  assert_eq(sort_titles(["Short", "Long", "Medium"], TitleDesc), [
    "Short", "Medium", "Long",
  ])
}

///|
test "sort titles preserves api order" {
  let titles = ["B", "A", "C"]
  assert_eq(sort_titles(titles, Api), ["B", "A", "C"])
}

///|
test "extract page content response" {
  let payload =
    #|{
    #|  "query": {
    #|    "pages": [
    #|      {
    #|        "title": "Albert Einstein",
    #|        "revisions": [
    #|          { "slots": { "main": { "content": "{{Infobox scientist}}\nBody" } } }
    #|        ]
    #|      },
    #|      {
    #|        "title": "Physics",
    #|        "revisions": [
    #|          { "slots": { "main": { "content": "Plain text" } } }
    #|        ]
    #|      }
    #|    ]
    #|  }
    #|}
  match parse_page_content_payload(payload) {
    Ok(contents) => {
      assert_eq(
        contents.get("Albert Einstein"),
        Some("{{Infobox scientist}}\nBody"),
      )
      assert_eq(contents.get("Physics"), Some("Plain text"))
    }
    Err(message) => fail(message)
  }
}

///|
test "extract template usages finds matching snippets" {
  let content = "Before\n{{Infobox scientist|name=Albert Einstein}}\nMiddle\n{{Citation needed|date=April 2024}}\nAfter"
  assert_eq(extract_template_usages(content, "citation needed"), [
    "{{Citation needed|date=April 2024}}",
  ])
}

///|
test "extract template usages handles nested templates" {
  let content = "{{Citation needed|reason={{lang|fr|source needed}}|date=April 2024}}"
  assert_eq(extract_template_usages(content, "citation needed"), [
    "{{Citation needed|reason={{lang|fr|source needed}}|date=April 2024}}",
  ])
}

///|
test "render page content prefixes title" {
  assert_eq(
    render_page_content("Albert Einstein", ["{{Infobox scientist}}"]),
    "= Albert Einstein =\n{{Infobox scientist}}",
  )
}

///|
test "normalize category name" {
  let namespace_info = {
    primary_name: "Category",
    canonical_name: Some("Category"),
    aliases: ["カテゴリ"],
  }
  assert_eq(
    normalize_category_name("Living people", namespace_info),
    "Category:Living people",
  )
  assert_eq(
    normalize_category_name(
      "Category:All articles with unsourced statements", namespace_info,
    ),
    "Category:All articles with unsourced statements",
  )
  assert_eq(
    normalize_category_name("カテゴリ:アイヌ語", namespace_info),
    "Category:アイヌ語",
  )
}

///|
test "build query context uses localized aliases" {
  let query = build_query_context(
    "テンプレート:Citation needed",
    Some("カテゴリ:アイヌ語"),
    {
      template: {
        primary_name: "Template",
        canonical_name: Some("Template"),
        aliases: ["テンプレート"],
      },
      category: {
        primary_name: "Category",
        canonical_name: Some("Category"),
        aliases: ["カテゴリ"],
      },
    },
  )
  assert_eq(query.template_title, "Template:Citation needed")
  assert_eq(query.template_target, "citation needed")
  assert_eq(query.category_title, Some("Category:アイヌ語"))
  assert_eq(query.category_target, Some("アイヌ語"))
}

///|
test "parse api namespaces payload includes aliases" {
  let payload =
    #|{
    #|  "query": {
    #|    "namespaces": {
    #|      "10": { "id": 10, "name": "Template", "canonical": "Template" },
    #|      "14": { "id": 14, "name": "Category", "canonical": "Category" }
    #|    },
    #|    "namespacealiases": [
    #|      { "id": 10, "alias": "テンプレート" },
    #|      { "id": 14, "alias": "カテゴリ" }
    #|    ]
    #|  }
    #|}
  let namespaces = match parse_api_namespaces_payload(payload) {
    Ok(namespaces) => namespaces
    Err(err) => fail(err)
  }
  assert_eq(namespaces.template.aliases, ["テンプレート"])
  assert_eq(namespaces.category.aliases, ["カテゴリ"])
}

///|
test "parse dump namespaces uses siteinfo metadata" {
  let payload =
    #|<mediawiki>
    #|  <siteinfo>
    #|    <namespaces>
    #|      <namespace key="10" case="first-letter" canonical="Template">テンプレート</namespace>
    #|      <namespace key="14" case="first-letter" canonical="Category">カテゴリ</namespace>
    #|    </namespaces>
    #|  </siteinfo>
    #|</mediawiki>
  let namespaces = match parse_dump_namespaces(payload) {
    Ok(namespaces) => namespaces
    Err(err) => fail(err)
  }
  assert_eq(namespaces.template.primary_name, "テンプレート")
  assert_eq(namespaces.template.canonical_name, Some("Template"))
  assert_eq(namespaces.template.aliases, ["Template"])
  assert_eq(namespaces.category.primary_name, "カテゴリ")
  assert_eq(namespaces.category.canonical_name, Some("Category"))
  assert_eq(namespaces.category.aliases, ["Category"])
}

///|
test "normalize cli args expands verbose alias" {
  assert_eq(normalize_cli_args(["enwp", "Citation needed", "-v"]), [
    "enwp", "Citation needed", "--verbose",
  ])
}

///|
test "dump progress logging threshold" {
  assert_false(should_log_dump_progress(999, 1000))
  assert_true(should_log_dump_progress(1000, 1000))
  assert_true(should_log_dump_progress(1250, 1000))
}
