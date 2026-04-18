# mediawiki-template-usage

CLI tool to list all pages that use a template on a MediaWiki site.

Use it to understand how a template is used across a wiki by querying the wiki's `embeddedin` API.

By default, the tool returns up to 10 matching pages.

## Usage

```sh
moon run cmd/main -- <endpoint> <template>
moon run cmd/main -- enwp "Citation needed"
moon run cmd/main -- enwp "Citation needed" --limit 20 --show-content
```

Use `moon run cmd/main -- --help` to see available options such as `--limit`, `--sort-by`, and `--show-content`.
