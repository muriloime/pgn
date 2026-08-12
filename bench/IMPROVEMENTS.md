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
