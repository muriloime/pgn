# Third-Party Notices

This gem bundles a compiled Rust extension (`pgn2_native`) that links
the `chessie` crate.

## chessie

- Source: https://crates.io/crates/chessie
- Repository: https://github.com/duck2/chessie
- Version: 2.0.x (see `ext/pgn2_native/Cargo.lock` for the exact pinned
  version)
- License: Mozilla Public License 2.0 (MPL-2.0)

`chessie` and its dependency `chessie_types` are MPL-2.0. They are used
unmodified. The MPL-2.0 license is file-level copyleft: it applies to
`chessie`'s own source files only and does not change the license of
this gem's code (MIT). Per MPL-2.0 §3.3, the source of the MPL-licensed
files is available at the repository URL above (and is reproducibly
pinned in `ext/pgn2_native/Cargo.lock`).

pgn2's own code remains MIT-licensed; see `LICENSE.txt`.
