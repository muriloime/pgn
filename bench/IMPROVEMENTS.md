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
