# Multi-source parser fixtures (Phase B2)

These five files are the frozen cross-language contract for the M3U parser and
source registry. `flutter_app/test/playlist_parser_test.dart` (B2-D),
`Tests/live-foundation/main.swift` (B2-S) and `Tests/webos/playlist_parser.test.js`
(B2-J) all read the *same* bytes from this directory, so a value asserted in one
port is a value asserted in all three. Editing a fixture here therefore changes
three hosted suites at once; add a file instead of rewriting one.

Placeholder hosts only (`*.example`). No real stream address, credential, or
authorized-source list belongs in this directory.
