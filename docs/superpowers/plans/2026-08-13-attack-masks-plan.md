# Attack Masks + Retention Benchmark — Plan

TDD, inline execution. Commit per task. Honest benchmark reporting.

## Task 1 — `PGN::Board` attack-mask tables (TDD)

Add `KNIGHT_ATTACKS` / `KING_ATTACKS` frozen 128-entry Arrays to `Board`,
entry `idx` = frozen `Array` of on-board 0x88 targets from `idx`. Build
from `Notation::KNIGHT_OFFS`/`KING_OFFS`, filtering `(t & 0x88).zero?`.

Spec (`spec/board_spec.rb`): mask entries equal the on-board squares the
offsets reach; corner squares have 2 knight / 3 king targets; centre e4
(0x54) has 8 knight / 8 king. E.g. `KNIGHT_ATTACKS[0] == [33, 18]`,
`KING_ATTACKS[0] == [1, 16, 17]`, `KNIGHT_ATTACKS[0x54].length == 8`.

## Task 2 — `Notation` uses the masks

`reaches?` N/K → `Board::KNIGHT_ATTACKS[from].include?(to)` /
`KING_ATTACKS`. `knight_attacked?`/`king_attacked?` → iterate the mask.
`leaper_moves?` N/K → iterate the mask (pass mask instead of `OFFS`).

Spec: existing `notation_spec` + round-trip stay green (byte-identical
SAN). Add a focused test: a knight on e4 reaches d6/f6/etc.; a king on e1
reaches d1/d2/e2/f2/f1.

## Task 3 — `MoveCalculator` K/N origins via the mask

Add `leaper_origins(mask)` iterating pre-filtered on-board targets;
`compute_origin` K/N branch calls
`leaper_origins(Board::KNIGHT_ATTACKS[dest_idx] ...)`; pawn path keeps
`move_origins(offsets)`.

Spec: existing `move_calculator_spec` + full round-trip stay green.

## Task 4 — SAN-generation benchmark section

Add `bench/profile_moves.rb` section 8: reconstruct `Notation.san` for
every move of the immortal game from coordinate from/to (precomputed
once), allocation + throughput. Regenerate baseline; report whether the
mask change moved the SAN and replay (section 1/4) needles.

## Task 5 — Retained-memory benchmark section

Add section 9: `MemoryProfiler` **retained** objects/memsize for
last-position-only, lazy (`each_position`) vs eager (`positions`). Fresh
`PGN::Game` per path. Regenerate baseline.

## Task 6 — Final verification + CHANGELOG/README

Full suite, RuboCop (no new offenses on touched files), `rake bench`,
CHANGELOG + README update.
