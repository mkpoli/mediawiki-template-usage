# mediawiki-template-usage

CLI tool to list all pages that use a template on a MediaWiki site.

Use it to understand how a template is used across a wiki by querying the wiki's `embeddedin` API.

By default, the tool returns up to 10 matching pages.

## Release

GitHub Actions now builds and tests the project on pushes and pull requests.

Pushing a version tag such as `v0.1.0` triggers the release workflow, which:

```sh
git tag v0.1.0
git push origin v0.1.0
```

- compiles the native CLI in release mode
- packages the binary together with `README.md` and `LICENSE`
- uploads the `.tar.gz` archive and its `.sha256` file to the GitHub Release

## Usage

```sh
moon run cmd/main -- <endpoint> <template>
moon run cmd/main -- enwp "Citation needed"
moon run cmd/main -- enwp "Citation needed" --limit 20 --show-content
```

Use `moon run cmd/main -- --help` to see available options such as `--limit`, `--sort-by`, and `--show-content`.
