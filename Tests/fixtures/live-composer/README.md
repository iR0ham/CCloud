# Live composer fixtures (Task B4-3 S1)

`composer_cases.json` is the frozen cross-language contract for the behaviour-neutral display composer.
`flutter_app/test/live_source_composer_test.dart`, `Tests/live-foundation/main.swift` and
`Tests/webos/live_source_composer.test.js` all read the *same* bytes, so a row list, a stream order, or an
issue count asserted on one port is asserted on all three. Editing a case here changes three hosted suites at
once; add a file instead of rewriting one.

Placeholder hosts only (`*.example`). No real stream address, credential, or authorized-source list belongs in
this directory.

## Why a new directory

The slice brief names `tests/fixtures/live_catalog/composer_cases.json`. That path is not usable here:

* `git ls-files` shows no lowercase `tests/` path in this repository — every tracked harness directory lives
  under `Tests/` (`Tests/fixtures`, `Tests/webos`, `Tests/live-foundation`, `Tests/api`, `Tests/player`).
* The owner's volume and the `macos-15` runners are case-insensitive, so `tests/` would be the *same*
  directory as `Tests/`, and a case-pressed path would resolve differently on a Linux runner than on macOS.
* The existing fixture groups already have owners: `Tests/fixtures/multi-source/README.md` freezes five files
  as the M3U parse contract, and `Tests/fixtures/migration/` holds the frozen documents the migration suites
  read. `composer_cases.json` is a third contract with its own consumers, so it gets its own directory rather
  than becoming a sixth file inside a group that documents itself as five.

## How to read a case

Each case supplies the built-in row groups it wants (`rows`), the document the seam would have handed the
composer — no usable document (`"document": null`), a raw undecodable one (`rawDocument`), or a complete
schema-v1 one (`document`) — and an `expect` block stating the returned row count, the returned names in
order, and per row its streams, country, languages and geo-block flag plus the number of issues per code.
`mintedNanoid` and `unifiedMemberCount` are extra assertions for the cases that need them; see the per-case
comments for what each one is proving.

A `document` is fed through each port's real codec, never through a test-local mapping, so the file stays a
wire-format contract. Its member ids are literal (`member:built-irib1`), which works because the composer
matches a built-in row to its member by provider identity rather than by `memberId` — no `stableKeyHash`
output is duplicated in this directory, so no hash can drift here.

`mintedNanoid` sits inside `expect` because it constrains a returned row, exactly like `rowStreams`.
`unifiedMemberCount` sits beside `expect` because it constrains the *unified layer's* grouping of the same
document, which the composer's rows-only signature cannot show: the merge collapses two members into one row,
so "the catalog holds two members" has to be asserted against `buildUnifiedChannels` directly. All three
suites read both keys from these positions; moving one without moving the other two is a red suite.
