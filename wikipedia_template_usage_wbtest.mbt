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
