# Changelog

## 1.2.1 (2026-08-13)

### Summary

Replay (move-application) throughput quick win on the `MoveCalculator`
hot path. No public API changes; serialized PGN/FEN output stays
byte-identical. See `bench/IMPROVEMENTS.md` for the per-step deltas.

### Changed
- **`MoveCalculator#valid_square?`**: integer compares (`file >= 0 &&
  file < 8`) instead of `(0..7).include?(file)`, which both allocates a
  `Range` per call and is ~3.4x slower. This predicate sits inside the
  `first_piece` / `move_origins` / `king_position` inner board-scanning
  loops — the dominant replay compute site (~46% of replay CPU via
  per-method timing, not the SAN regex parse as had been assumed).
- **`MoveCalculator#compute_origin`**: string `case` (`when 'B','R','Q',...`)
  instead of `/[brq]/i` regex `===` matches, removing 4 `MatchData`
  allocations per move.
- **`MoveCalculator#first_piece`**: returns only the `[file, rank]` square
  (`nil` when the scan runs off the edge) instead of a `[piece, square]`
  wrapper tuple; callers read the piece via a new `piece_at` helper. Removes
  one array allocation per direction scan.
- Performance vs 1.2.0 (immortal game, 45 plies, fresh process each):
  replay throughput 814.65 us/i -> 752.54 us/i (+8.2%); replay allocations
  1709 -> 1571 objects (-138, -8.1%) and 103720 -> 92440 bytes (-10.9%).
  182 specs pass; byte-identical FEN/PGN output; zero new rubocop offenses
  vs 1.2.0. The piece-location-index rewrite (the real ~46% ceiling,
  deferred "Approach B") is unchanged.

## 1.2.0 (2026-08-13)

### Summary

Parse allocation quick win: collapse `PGN::Lexer#scan_one`'s per-token
3-element tuple. No public API changes; serialized PGN/FEN output stays
byte-identical. See `bench/IMPROVEMENTS.md` for the per-step deltas.

### Changed
- **Lexer hot path**: `PGN::Lexer#scan_one` now returns the matched string
  directly (stashing its type/discarded flag in ivars) instead of a
  3-element `[type, m, discarded]` tuple, so the parser path (`next_token_pair`)
  allocates only the single `[type, value]` array Racc requires per token.
  Selected by per-line allocation profiling (`scan_one`'s tuple was the #1
  parse allocation site).
- **Deferred**: the coordinate-only-board + piece-location-index work was
  profiled and deferred to a single coherent board-representation rewrite
  (see TODO) — coordinate-board alone measured only ~1.25× replay at medium
  risk and would likely be superseded by the piece-index rewrite.
- Performance vs 1.1.0: parse-only allocations −42% objects (603537 → 347037 /
  500 games); parse+replay −18% objects (1427586 → 1170586). Replay path
  unchanged. All 182 specs pass; racc-sync OK.

## 1.1.0 (2026-08-13)

### Summary

Performance quick wins ("Approach A"): safe, behavior-compatible
micro-optimizations on top of the 1.0 parser. No public API changes; serialized
PGN/FEN output stays byte-identical. See
`docs/superpowers/specs/2026-08-13-pgn-performance-quick-wins-design.md` and
`bench/IMPROVEMENTS.md` for the design and per-step deltas.

### Changed
- **Lexer hot path**: `PGN::Lexer#next_token_pair` returns `[type, value]`
  without allocating a `Token` Struct (or its `keyword_init` Hash), via a shared
  scanning routine that preserves `game_starts` for verbatim `pgn` slicing.
  `PgnParser#next_token` uses it.
- **`PGN::Game#moves=`**: reuses an existing `MoveText` when its comment is
  already clean (halving `MoveText` allocations on the parse path); still
  re-wraps to preserve the legacy double-`clean_text` for multi-line/nested
  comments.
- **`PGN::Move#piece=`**: non-allocating castling guard (`start_with?('O')`
  instead of `match('O-O')`), removing a `MatchData` from every `Move.new`.
- **`PGN::Position`**: `next_player` uses a ternary instead of
  `(PLAYERS - [player])`; `Position#move` skips `castling - restrictions` when
  there are no restrictions.
- **`PGN::MoveCalculator`**: memoized `destination_coords`, frozen
  `ROOK_RESTRICTIONS` constant, empty short-circuit in `castling_restrictions`.
- **`PGN::Move#pawn?`**: non-allocating (`==` instead of `%w[P p].include?`).
- Performance vs 1.0: replay allocations −21% objects / −27% bytes; parse-only
  allocations −3.6% objects / −28% bytes; parse + replay −15% objects / −28%
  bytes. The full hand-rolled SAN parser was deferred (marginal payoff, high
  risk) per the design's "measure first" guidance.

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
