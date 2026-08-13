# Efficiency improvements — before/after

Captured by `rake bench` on the same machine. "BEFORE" = `bench/*.pre-optimization.txt`
(pre-optimization snapshot). "AFTER" = `bench/baseline_*.txt`.

## bench/profile_moves.rb (immortal game, 45 plies)

| Metric | BEFORE | AFTER | Δ |
|---|---|---|---|
| Replay allocations (objects) | 5124 | 2565 | -2559 |
| Replay allocations (bytes) | 262608 | 155296 | -107312 |
| Board#dup x45 (objects) | 451 | 91 | -360 |
| Board#dup x45 (bytes) | 43096 | 6736 | -36360 |
| Board#at(str) x1000 (objects) | 6000 | 0 | -6000 |
| Board#at(str) x1000 (bytes) | 240000 | 0 | -240000 |

## bench/profile_parse.rb (500 immortal games)

| Metric | BEFORE | AFTER | Δ |
|---|---|---|---|
| Parse-only allocations (objects) | 1248065 | 1248065 | 0 |
| Parse-only allocations (bytes) | 120370470 | 120370470 | 0 |
| Parse + replay allocations (objects) | 3778073 | 2498573 | -1279500 |
| Parse + replay allocations (bytes) | 249570048 | 195914048 | -53656000 |

## Changes applied

1. `Board#at(str)` / `coordinates_for` — getbyte arithmetic (zero-alloc string lookup).
2. `MoveCalculator#king_position` — early exit.
3. `Move#initialize` — explicit setters (no per-move `names` array).
4. `FEN#board_string` — single-pass serialization.
5. `Board` — column-level copy-on-write (`dup` shares columns, `update` clones one).

All existing characterization specs remain green; public output (FEN, PGN) is byte-identical.

## Parser migration: whittle -> Racc + StringScanner (2026-08-13)

The abandoned `whittle` gem (v0.0.8, 2011) was replaced by a stdlib `Racc` +
`StringScanner` parser (`lib/pgn/pgn_parser.y`, generated to
`lib/pgn/pgn_parser.rb`; lexer in `lib/pgn/lexer.rb`). whittle was responsible
for ~80% of parse allocations.

Corpus: 500 immortal games (`BENCH_N=500`). Baseline = `bench/baseline_parse.txt`
(whittle). New = `bench/baseline_parse.racc.txt`. Allocation counts are
deterministic; throughput is noisy over a 5 s window (use ms/i).

| Metric | whittle | racc | Δ |
|---|---|---|---|
| Parse-only allocations (objects) | 1248065 | 557035 | -691030 (-55.4%) |
| Parse-only allocations (bytes) | 120370470 | 36636902 | -83733568 (-69.6%) |
| Parse + replay allocations (objects) | 2498573 | 1614087 | -884486 (-35.4%) |
| Parse + replay allocations (bytes) | 195914048 | 105404152 | -90509896 (-46.2%) |
| Parse-only throughput (ms/i) | 741 | 212 | -529 (~3.5x faster) |
| Parse + replay throughput (ms/i) | 1114 | 371 | -743 (~3.0x faster) |

### What changed
- `lib/pgn/pgn_parser.y` / `pgn_parser.rb`: Racc grammar mirroring the whittle
  rules, held as instance state (fixes the `@@pgn`/`@@game_comment` reentrancy
  bug). `PGN::Game#pgn` is sliced from per-game byte offsets (no O(n^2)
  `@@pgn +=` accumulation).
- `lib/pgn/lexer.rb`: StringScanner (C ext) lexer reusing whittle's exact
  terminal regexes; records per-game content-start byte offsets.
- `lib/pgn/parser.rb`: thin facade delegating to `PGN::PgnParser`.
- whittle dependency dropped; `lib/pgn/whittle_parser.rb` deleted.

### Behavior preservation
The grammar deliberately replicates whittle's quirks so parsed-game
serialization stays byte-compatible: right-recursive `variation_list` (variation
order reverses) and right-recursive `tag_section` (reverse insertion order,
first-wins). `game.pgn` is verbatim raw text. A golden-equivalence spec (now
removed with whittle) confirmed identical output on all 14 fixtures + 11 inline
inputs during the migration; 32 explicit parser specs now pin the behavior
permanently (`spec/parser_explicit_spec.rb`).

Full suite: 187 examples, 0 failures.

## Quick wins (Approach A) — 2026-08-13

Safe, behavior-compatible micro-optimizations on top of the Racc parser.
Spec: `docs/superpowers/specs/2026-08-13-pgn-performance-quick-wins-design.md`.
"BEFORE" = `bench/baseline_*.pre-quickwins.txt` (working tree immediately before
this change). "AFTER" = `bench/baseline_*.txt`.

### bench/profile_moves.rb (immortal game, 45 plies)

| Metric | BEFORE | AFTER | Δ |
|---|---|---|---|
| Replay allocations (objects) | 2177 | 1710 | -467 (-21.4%) |
| Replay allocations (bytes) | 141616 | 103760 | -37856 (-26.7%) |
| Replay throughput (µs/i) | 931.70 | 848.64 | -83.06 (-8.9%) |

### bench/profile_parse.rb (500 immortal games)

| Metric | BEFORE | AFTER | Δ |
|---|---|---|---|
| Parse-only allocations (objects) | 626037 | 603537 | -22500 (-3.6%) |
| Parse-only allocations (bytes) | 39417414 | 28257414 | -11160000 (-28.3%) |
| Parse-only throughput (ms/i) | 318.39 | 274.08 | -44.31 (-13.9%) |
| Parse + replay allocations (objects) | 1683087 | 1427586 | -255501 (-15.2%) |
| Parse + replay allocations (bytes) | 108184152 | 78104136 | -30080016 (-27.8%) |
| Parse + replay throughput (ms/i) | 795.32 | 715.05 | -80.27 (-10.1%) |

### Changes applied

1. `PGN::Lexer` — added `next_token_pair` (returns `[type, value]`, no `Token`
   Struct) built on a shared private `scan_next` routine that preserves the
   `note_token`/`advance_line`/`game_starts` side effects. `next_token`/`tokens`
   unchanged. `PgnParser#next_token` (in `.y` and generated `.rb`) now uses
   `next_token_pair`. Eliminates the per-token `Token` Struct + its
   `keyword_init` Hash (the larger win in bytes).
2. `PGN::Game#moves=` — reuses an existing `MoveText` directly when its comment
   is already fully cleaned (nil or brace-free); still re-wraps (preserving the
   legacy double-`clean_text` for multi-line/nested comments) when the comment
   carries braces. Halves `MoveText` allocations on the parse path for
   comment-free corpora.
3. `PGN::Move#piece=` — replaced the per-`Move.new` `san.match('O-O')` guard
   (allocated a `MatchData` on every move, castling or not) with a
   non-allocating `san.start_with?('O')`. The full hand-rolled SAN parser was
   **deferred** per the spec's "measure first; defer if marginal" guidance:
   it would save only ~1 `MatchData`/ply (~2% of replay, ~1.3% of parse+replay)
   at high risk to SAN edge cases.
4. `PGN::Position#next_player` — `(PLAYERS - [player]).first` →
   `player == :white ? :black : :white` (removes 2 array allocations/ply).
   `Position#move` — skips `castling - restrictions` when `restrictions` is
   empty (returns the shared `castling` array; safe because castling arrays
   are replaced, never mutated).
   `PGN::MoveCalculator` — memoizes `destination_coords` (was recomputed 2–3
   times/move, each allocating a 2-element array); frozen `ROOK_RESTRICTIONS`
   constant replaces per-call hash literals in `castling_restrictions`; empty
   short-circuit avoids `compact.uniq` on the common empty path.
   `PGN::Move#pawn?` — `%w[P p].include?` → `piece == 'P' || piece == 'p'`.
   `valid_square?` was left unchanged: its `(0..7)` are frozen range literals
   cached by the VM, so inlining would only save method dispatch, not
   allocations (the original rationale was unfounded).

### Behavior preservation

All 182 specs pass unmodified (`bundle exec rspec`). The lexer refactor keeps
`next_token`/`tokens` and the `game_starts`-driven verbatim `Game#pgn` slicing
byte-identical (covered by `spec/lexer_spec.rb`, `spec/parser_explicit_spec.rb`,
and the fixture round-trip in `spec/game_spec.rb`). Racc parser is in sync with
`pgn_parser.y` (CI racc-sync check passes). No public API or serialized-output
changes.
