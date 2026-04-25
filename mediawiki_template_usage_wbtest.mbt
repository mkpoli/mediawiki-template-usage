///|
test "normalize template name" {
  assert_eq(
    normalize_template_name("Infobox person"),
    "Template:Infobox person",
  )
  assert_eq(
    normalize_template_name("Template:Citation needed"),
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
  match parse_embeddedin_payload(payload) {
    Ok((titles, Some(token))) => {
      assert_eq(titles, ["Page One", "Page Two"])
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
test "parse dump page matches extracts titles and content" {
  let payload =
    #|<page><title>Page One</title><revision><text xml:space="preserve">{{Citation needed|date=2024}}</text></revision></page>
    #|<page><title>Page &amp; Two</title><revision><text xml:space="preserve">Before &lt;tag&gt;{{Citation needed}}&lt;/tag&gt;</text></revision></page>
  let (titles, contents) = parse_dump_page_matches(payload)
  assert_eq(titles, ["Page One", "Page & Two"])
  assert_eq(contents.get("Page One"), Some("{{Citation needed|date=2024}}"))
  assert_eq(
    contents.get("Page & Two"),
    Some("Before <tag>{{Citation needed}}</tag>"),
  )
}

///|
test "build dump page regex escapes template variants" {
  assert_eq(
    build_dump_page_regex("Template:Citation needed"),
    "(?is)<page>.*?\\{\\{\\s*(?:subst:|safesubst:)?(?:template:)?\\s*citation[ _]+needed(?=[\\s|}]).*?</page>",
  )
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
  assert_eq(extract_template_usages(content, "Citation needed"), [
    "{{Citation needed|date=April 2024}}",
  ])
}

///|
test "extract template usages handles nested templates" {
  let content = "{{Citation needed|reason={{lang|fr|source needed}}|date=April 2024}}"
  assert_eq(extract_template_usages(content, "Template:Citation needed"), [
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
