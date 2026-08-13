# Attack Masks + Retention Benchmark — Design

**Goal:** (1) Replace per-call knight/king offset loops with precomputed
on-board attack masks; (3) add a retained-memory benchmark section
showing the lazy `each_position` retention win. Pure Ruby, no behavior
change, byte-identical output.

## 1. Precomputed knight/king attack masks

**Where the offsets are used today:**
- `PGN::Notation#reaches?` (N/K): `KNIGHT_OFFS.any? { |o| from + o == to }`.
- `PGN::Notation#knight_attacked?` / `#king_attacked?`: `OFFS.any? { off; i = target+off; (i & 0x88).zero? && at_index(i) == piece }`.
- `PGN::Notation#leaper_moves?` (N/K in `any_legal_move?`): same offset + on-board pattern.
- `PGN::MoveCalculator#move_origins` (K/N origin lookup on the replay path): `offsets.each { off; target = dest+off; next unless on_board?(target); ... }`.

**Change.** Add two frozen 128-element tables to `PGN::Board`:
`KNIGHT_ATTACKS` and `KING_ATTACKS`, where entry `idx` is a frozen `Array`
of the on-board 0x88 target indices reachable from `idx` by that piece
(built from the existing `Notation::KNIGHT_OFFS`/`KING_OFFS` offsets,
filtering `(t & 0x88).zero?`). Then:

- `Notation#reaches?` N/K → `Board::KNIGHT_ATTACKS[from].include?(to)`.
- `Notation#knight_attacked?` / `#king_attacked?` → iterate the mask
  (no per-call off-board test).
- `Notation#leaper_moves?` N/K → iterate the mask.
- `MoveCalculator#move_origins` for K/N → a new `leaper_origins(mask, piece)`
  that iterates pre-filtered on-board targets; pawns keep the offset path.

**Correctness:** the masks are exactly the precomputed set of on-board
targets the current code computes per call, so output is byte-identical.
The existing `move_calculator_spec`, `notation_spec`, and the full
round-trip suite pin this.

**Benchmark:** add a `Notation.san` reconstruction section to
`bench/profile_moves.rb` (rebuild SAN for every move of the immortal game
from its coordinate from/to); re-check section 1 (replay) and section 4
(replay throughput) for the `MoveCalculator` change. Report honestly: if
the masks don't move the needle (the offset loops are tiny vs. the O(128)
scans that dominate `Notation`), say so.

## 3. Retained-memory benchmark for `each_position`

**Change.** Add a section to `bench/profile_moves.rb` measuring
`MemoryProfiler` **retained** objects/memsize for "last position only",
lazy (`each_position`) vs eager (`positions`). Lazy retains only the last
`Position` (+ enumerator); eager memoizes the full array on the `Game` and
retains all `PLY+1` positions.

Uses `report.total_retained` / `report.total_retained_memsize` (objects
allocated during the report still alive at its end). Fresh `PGN::Game`
per path so construction cost cancels.

## Global constraints
- Pure Ruby; no new deps; no native.
- Byte-identical FEN/PGN; full suite green; no new RuboCop offenses on
  touched files (existing offenses may remain).
- TDD; commit per task.
