# mediawiki-template-usage

CLI tool to list all pages that use a template on a MediaWiki site.

Use it to understand how a template is used across a wiki by querying the wiki's `embeddedin` API or by scanning local Wikimedia XML dump files.

By default, the tool returns up to 10 matching pages.

## Release

GitHub Actions now builds and tests the project on Linux, macOS, and Windows.

Pushing a version tag such as `v0.1.0` triggers the release workflow, which:

```sh
git tag v0.1.0
git push origin v0.1.0
```

- compiles the native CLI in release mode
- packages the binary together with `README.md` and `LICENSE`
- uploads platform-specific archives and `.sha256` files to the GitHub Release

The release archives let users run the CLI without installing MoonBit first.

Current limitation: API mode still shells out to `curl`, and dump mode currently supports plain `.xml` files only.

## Usage

### Production

After downloading a release archive, run the packaged binary directly:

```sh
./mediawiki-template-usage <source> <template>
./mediawiki-template-usage enwp "Citation needed"
./mediawiki-template-usage jawiktionary-2026-04-01-p7p579548.xml "Citation needed"
./mediawiki-template-usage jawiktionary-2026-04-01-p7p579548.xml "Citation needed" --dump-file jawiktionary-2026-04-01-p7p579549.xml
./mediawiki-template-usage enwp "Citation needed" --category "Living people"
./mediawiki-template-usage enwp "Citation needed" --limit 20 --show-content
```

Use `./mediawiki-template-usage --help` to see available options such as `--limit`, `--sort-by`, `--category`, and `--show-content`.

`<source>` can be a full MediaWiki API endpoint, a shorthand alias like `enwp` or `wikidata`, or a single plain Wikimedia XML dump file such as `jawiktionary-2026-04-01-p7p579548.xml`.

Use `--dump-file` to add more plain `.xml` dump files and treat them as one combined source.

### Development

From the project root, run the CLI through MoonBit:

```sh
moon run cmd/main -- <source> <template>
moon run cmd/main -- enwp "Citation needed"
moon run cmd/main -- jawiktionary-2026-04-01-p7p579548.xml "Citation needed"
moon run cmd/main -- jawiktionary-2026-04-01-p7p579548.xml "Citation needed" --dump-file jawiktionary-2026-04-01-p7p579549.xml
moon run cmd/main -- enwp "Citation needed" --category "Living people"
moon run cmd/main -- enwp "Citation needed" --limit 20 --show-content
```

Use `moon run cmd/main -- --help` to see available options such as `--limit`, `--sort-by`, `--category`, and `--show-content`.
