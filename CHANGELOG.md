# Changelog

## 1.0.0 (2026-08-13)

### Summary

First stable release. The parser has been migrated off the abandoned `whittle`
gem (v0.0.8, 2011) to a stdlib `Racc` + `StringScanner` parser. The public API
(`PGN.parse`, `PGN::Game`, `PGN::Serializer`, `PGN::Board`, `PGN::Move`) is
unchanged and serialized PGN output stays byte-compatible with the previous
release.

### Added
- Parser now accepts tag values containing unescaped double-quotes (e.g.
  `[Event "IRT BLITZ "Sub Zonal""]`), a form found in real-world PGN files.
  Previously the parser raised on such input.
- New fixtures `spec/pgn_files/doublequotes.pgn` and
  `spec/pgn_files/specialcharacters.pgn`, plus tests for parsing tag values
  with inner quotes and for the `Encoding` argument of `PGN.parse`.
- `PGN::Serializer` and `PGN::Game#to_pgn` (carried over from the 0.x line).
- Comprehensive test and profiling infrastructure: exhaustive characterization
  specs for `Board`, `Move`, and `MoveCalculator`; a round-trip gate over all
  fixtures; and allocation/throughput harnesses under `bench/`.

### Changed
- **Parser rewritten on `Racc` + `StringScanner`** (stdlib only, no new runtime
  dependency). `lib/pgn/pgn_parser.y` (generated to `lib/pgn/pgn_parser.rb`)
  mirrors the former grammar; `lib/pgn/lexer.rb` is the StringScanner lexer.
  `PGN::Parser` is now a thin facade over `PGN::PgnParser`.
- **Removed the `whittle` runtime dependency.**
- **Fixed a parser reentrancy bug**: the legacy parser accumulated `@@pgn` and
  `@@game_comment` in class variables shared across calls. The new parser holds
  all state per instance, so repeated and concurrent parses no longer leak
  state. `PGN::Game#pgn` is now sliced from per-game byte offsets (eliminating
  the previous O(n^2) `@@pgn +=` accumulation).
- Performance: parse-only allocations −55% objects / −70% bytes; parse-only
  throughput ~3.5× faster; parse + replay ~3.0× faster. Board copy-on-write,
  zero-allocation `Board#at(str)`, single-pass `FEN#board_string`, and
  streamlined `Move`/`MoveCalculator` hot paths. See `bench/IMPROVEMENTS.md`.
- `spec/spec_helper.rb`: removed the deprecated
  `treat_symbols_as_metadata_keys_with_true_values` config (drops an RSpec
  deprecation warning).

### Notes
- The grammar deliberately replicates two legacy parser quirks for
  byte-compatible serialization: variations are emitted in reverse source
  order, and duplicate tags keep the first value with reverse insertion order.
  These can be revisited in a future release.

### Credits
- The double-quotes parsing fix and the new fixtures were contributed by
  Alexis Vargas (https://github.com/lexisvar), ported from the `pgn3` fork.
