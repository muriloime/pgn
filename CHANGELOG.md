# Changelog

## Unreleased

### Summary

Native Rust bitboard perft backend: a `pgn2-bitboard` engine (magic/BMI2-
`pext` slider tables, make/unmake, full legal move generation) exposed to
Ruby as `PGN::Bitboard::Engine` via a `magnus`/`rb_sys` `cdylib`
(`pgn2_native`), shipped as precompiled platform gems. The engine lives in
`ext/pgn2_native/` and is fully decoupled from the pure-Ruby 0x88
`Board`/`Notation`/`MoveCalculator`, which stay byte-identical; all specs
green. Fast perft (≈11–16 Mnps through the Ruby binding) is the primary
deliverable; a thin `#legal_moves` / `#legal?` UCI API is the byproduct.

### Added
- **`PGN::Bitboard::Engine`** (native): `Engine.new(fen)`, `#perft(depth)`,
  `#legal_moves` (sorted UCI), `#legal?(uci)`. Validates against the
  published perft suite (startpos depth 6 = 119,060,324; Kiwipete depth 5
  = 193,690,690; positions 3–6).
- **`ext/pgn2_native/`** Cargo workspace: `pgn2-bitboard` (pure-Rust engine,
  `cargo test`) + `pgn2_native` (`cdylib`, `magnus` bindings). Built via
  `rb_sys`/`extconf.rb`; `bundle exec rake compile`.
- **`lib/pgn/bitboard.rb`** load gate: requires the native lib, rescuing
  `LoadError` so the rest of the gem works without it.
- **`bench/perft.rb`** + `rake bench:perft`: perft nps benchmark.
- **CI**: `.github/workflows/native.yml` (`cargo test` + `rake compile` +
  `rspec`) and `.github/workflows/release-gems.yml` (cross-compile
  prebuilt platform gems via `rake-compiler-dock`).

### Distribution note

This adds a **required compiled extension**. Release artifacts are
**precompiled platform gems** (x86_64/aarch64, linux/darwin) built in CI;
end users and the chessellence Docker build need no Rust toolchain. Interim
source builds install Rust in the Docker build stage (see README). The
pure-Ruby gem contract is otherwise unchanged; `PGN::Bitboard` is simply
undefined when the extension is absent.

---

## Unreleased (attack-masks)

### Summary

Attack-mask pass: precomputed knight/king on-board target tables on
`PGN::Board`, used by `Notation` (reaches/attacked/leaper moves) and
`MoveCalculator` (knight/king origin lookup), plus a retained-memory
benchmark section. No behavior change; serialized PGN/FEN stays
byte-identical; all 226 specs green.

### Changed
- **`PGN::Board::KNIGHT_ATTACKS` / `KING_ATTACKS`**: new frozen 128-entry
  tables mapping each 0x88 index to the frozen Array of on-board target
  indices reachable by that piece (built once at load from the existing
  offsets). Replaces the per-call `OFFS.any? { |o| from + o == to }` +
  `(t & 0x88).zero?` off-board test with a direct array iteration.
- **`PGN::Notation`**: `#reaches?` (N/K), `#knight_attacked?`,
  `#king_attacked?`, and `#leaper_moves?` now iterate the precomputed masks
  instead of offsets. `leaper_moves?` takes targets directly (no per-call
  off-board test).
- **`PGN::MoveCalculator`**: K/N origin lookup routes through a new
  `leaper_origins` using `Board::KNIGHT_ATTACKS`/`KING_ATTACKS`; the pawn
  path keeps the offset-based `move_origins`.
- **Bench** (`bench/profile_moves.rb`): new section 8 (SAN generation
  allocation + throughput) and section 9 (retained memory: lazy
  `each_position` vs eager `positions`). Baselines refreshed.

### Performance
- **SAN generation** (`Notation.san` over the immortal game): throughput
  **+8%** (334 → 361 ips, 2.99 → 2.77 ms/i) from a same-harness A/B
  (pre-mask lib vs masks). Allocations unchanged (1387 objects) — the masks
  only replace arithmetic + an off-board test, no new objects per move.
- **Replay**: neutral. Same-harness A/B: 930 → 931 objects / +6720 bytes
  with masks; throughput within noise. (The committed replay baseline
  refreshed 976 → 931 objects, which is measurement-environment variance
  between runs of identical pre-mask code, not an effect of the masks.)
- **Retention** (new section 9): a caller that streams `each_position` and
  keeps the `Game` retains 95 objects / 6280 bytes; a caller that calls
  `positions` (memoizing the full array on the Game) retains 287 objects /
  17232 bytes — ~3x less retained for the streaming pattern.

## 1.5.0 (2026-08-13)

Performance/internals pass: a direct 0x88 FEN builder, a lazy
`Game#each_position` enumerator, and a lazily-computed Zobrist position
hash with `Position#hash`/`#eql?`/`#==`. No public behavior change;
serialized PGN/FEN output stays byte-identical; all 222 specs green.

### Changed
- **`PGN::Board#fen_board_string`**: new method that serializes the FEN
  board-string portion by walking the 0x88 `@cells` array directly (ranks
  8→1, files a→h, empty-run collapsing), instead of rebuilding the 8x8
  `squares` array and transposing. `FEN#board_string` now delegates to it,
  so every `position.to_fen` / `game.fen_list` call skips the 8x8 rebuild.
  FEN output is byte-identical (the `board_string round-trip` spec pins
  it). Measured (immortal game, 46 positions): 1913 objects / 100464
  bytes for FEN generation; ~1.27k ips.
- **`PGN::Game#each_position`**: new lazy enumerator (yields each
  `PGN::Position` in order, or returns an `Enumerator` without a block);
  `#positions` is now `each_position.to_a` with the same memoization.
  Callers that only need the last position can stream without
  materializing the full array. `positions` still returns the same
  `Array`. Cost: one `Enumerator` per `#positions` call (parse+replay
  for 500 games: +500 objects, throughput flat).
- **`PGN::Zobrist`**: new module with a deterministic 64-bit Zobrist key
  table (`table`/`side`/`castling`/`ep_file`) and a `seed(board, player,
  castling, en_passant)` helper, generated once from a frozen seed so
  hashes are stable across processes. Pure Ruby, no native deps.
- **`PGN::Position`**: new `#zobrist` (the hash, computed lazily on first
  access and cached), `#hash`, `#eql?`, and `#==`. Equality compares
  board cells, side to move, castling rights, and en-passant square —
  halfmove/fullmove counters are ignored, matching threefold-repetition
  semantics. The hash is lazy: the replay hot path (which never asks for
  it) pays nothing (replay stays at 976 objects / 62064 bytes,
  byte-identical to 1.5.0); consumers pay one full seed on demand. An
  incremental per-move update was prototyped and rejected: 64-bit
  Integer XOR allocates a new `Bignum` per operation (~9 per move),
  which regressed replay by +40% allocations / −32% throughput for a
  feature nothing currently consumes — laziness keeps the public API
  with zero hot-path cost.

## 1.5.0 (2026-08-13)

### Summary

Clarity refactor on the 0x88 hot path, plus a small parser perf win: no
public API changes, no behavior change; serialized PGN/FEN output stays
byte-identical; all 201 specs green.

### Changed
- **`PGN::Board`**: promoted the on-board bitmask test and square-name
  lookup to public `on_board?(idx)` / `square_name(idx)` methods,
  replacing private duplicates of the same logic in `MoveCalculator`.
  Added a named `Board.from_cells(cells)` factory for building a board
  directly from a 128-cell 0x88 array; `#dup` (called every move) now
  routes through it instead of reaching around the constructor via
  `Board.allocate` + `instance_variable_set` directly. Performance is
  identical — same allocate + one ivar set — just a documented factory
  instead of a reflective one-off.
- **`PGN::MoveCalculator`**: calls `board.on_board?`/`board.square_name`
  instead of its own private copies; named the castling-table square
  literals (`C1`..`G8`) instead of raw 0x88 integers in `CASTLING`, for
  readability. `#board`/`#move` are now `attr_reader` instead of
  `attr_accessor` — there was no external writer, and the `@dest_idx`
  memo already silently relied on both never changing after
  `#initialize`; dropping the setters enforces that invariant in the
  type instead of by convention.
- **`PGN::Lexer`**: dropped the per-token `@line` counter (one
  `str.count("\n")` via `advance_line` on every `next_token`/
  `next_token_pair` call) in favor of a lazy `line_at(off)`, computed
  only when a line number is actually needed (error messages, the spec
  `tokens` helper) — the parser itself never reads it. Removes a
  `str.count("\n")` call from the parse hot path (~6% of parse CPU for
  a value that was never read).

## 1.4.0 (2026-08-13)

### Summary

New `PGN::Notation` module that *generates* Standard Algebraic Notation
(SAN) for a single coordinate move (origin square, destination square,
optional promotion) given the position before the move. The rest of the
gem only *parses* SAN; this is the reverse direction, needed to render
moves stored as coordinates (e.g. `e2`-`e4`) in standard chess notation.

### Added
- `PGN::Notation.san(position, from, to, promotion = nil)` and the
  convenience `PGN::Notation.san_from_fen(fen, from, to, promotion = nil)`.
  Builds full SAN: piece letter, capture (`x`), castling (`O-O`/`O-O-O`),
  pawn capture file (`exd5`), promotion (`=Q`), legal-move disambiguation
  (file / rank / full square, respecting pins), and check (`+`) / checkmate
  (`#`) suffixes. Checkmate detection drives full legal-move generation for
  the side to move (the gem's first move generator). Raise `ArgumentError`
  if the origin square is empty.
- New `spec/notation_spec.rb`; all 201 specs green. A round-trip harness over
  every parseable fixture reproduces the original SAN of all 277 moves
  exactly (including disambiguation and `+`/`#` suffixes).

### Changed (parser performance)
- `PGN::Lexer#scan_one` now dispatches on the leading byte of the next
  token via a frozen `BYTE_DISPATCH` table (with an `ALL_RULES` fallback),
  trying only the 1-2 rules that can match that byte instead of walking all
  nine rules in order. Profiling had `StringScanner#scan` at ~23% of parse
  CPU and the rule loop ~38% inclusive; the dispatch nearly halves scan time.
- `PGN::PgnParser#next_token` mutates the lexer's `[type, value]` pair in
  place rather than allocating a second translated pair — one array per token
  is the Racc floor.
- Net (500 immortal games): parse-only throughput +25% (305 → 203 ms/i),
  parse allocations −17% (347037 → 288537 objects / 17977414 → 15640374
  bytes), parse+replay allocations −7% (831530 → 773030 objects). Serialized
  PGN/FEN output stays byte-identical; all 201 specs green.

## 1.3.0 (2026-08-13)

### Summary

Replay (move-application) board-representation rewrite: `PGN::Board`
internals move to the classic 0x88 scheme (a 128-cell array indexed by
`rank*16+file`) and `PGN::MoveCalculator` works entirely in single-integer
square indices, so the replay hot path no longer allocates `[file,rank]`
coordinate arrays or square-name strings. No public API changes; serialized
PGN/FEN output stays byte-identical.

### Changed
- **`PGN::Board`**: internals rewritten to a 0x88 array (`@cells`, 128
  entries). The public file-major `squares` 8x8 API, `at` (string/coord
  overloads), `update`, `change!`, `position_for`, `coordinates_for`, and
  `dup` are preserved (computed/translated at the API boundary, off the
  hot path). New internal 0x88 accessors `index_of`, `index_for`, `at_index`,
  `update_index`, and `apply!` (integer-keyed batch update) serve the hot
  path. `dup` copies the 128-cell array (cheaper than the prior column COW:
  136 → 91 objects / 10336 → 3856 bytes per 45 dupes).
- **`PGN::MoveCalculator`**: rewritten to address squares as 0x88 integer
  indices throughout. `#compute_origin` returns an index; `#changes` is an
  integer-keyed hash applied via `Board#apply!`; ray stepping (`first_piece`)
  and off-board checks use a single integer add and the `(idx & 0x88).zero?`
  bitmask (≈1.6x faster than a 0..7 four-integer bounds check, measured);
  `castling_restrictions`/`en_passant_*` use integer corner indices. The
  public `#origin` reader still returns an algebraic square string. Scan and
  disambiguation algorithms are unchanged, so output is byte-identical.
- **Plan B (piece-location index) — attempted, rejected**: a `piece → 0x88
  indices` index maintained in `update`/`apply!`, used for O(1)
  slider/leaper/king origin lookups, was implemented on top of the 0x88
  board and passed all 182 specs, but regressed: replay 526 → 727 µs/i
  (+38% slower), allocations 976 → 1591 objects (+63%). `Board#dup` (called
  every move) must clone the index (≈12 piece arrays: Board#dup 91 → 676
  objects), and every move pays per-update index maintenance that pawns —
  the most common move type, whose origins are geometry-fixed and can't use
  the index — pay for no benefit. The index helps move-*generation*
  libraries (chess.js, python-chess) that enumerate all legal moves, but
  not replay, which validates one given move where ray-scanning from the
  destination is already cheap. Reverted; the 0x88 board alone is the
  winner. Rationale recorded in `TODO.md`.
- Performance vs 1.2.1 (immortal game, 45 plies; A/B batched median, 200
  replies × 7, fresh process each): replay throughput 798 → 535 µs/i
  (+49%); replay allocations 1571 → 976 objects (−38%) and 92440 → 62064
  bytes (−33%). Full pipeline (`bench/profile_parse.rb`, 500 games):
  parse+replay throughput 659 → 534 ms/i (+23%), allocations 1101586 →
  831530 objects (−24.5%) and 62164136 → 47966112 bytes (−22.8%);
  parse-only unchanged. 182 specs pass; byte-identical FEN/PGN output;
  zero new rubocop offenses vs 1.2.1 (the rewrite is shorter on
  ClassLength/AbcSize and leaves the same pre-existing metric offenses on
  the same methods).

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
