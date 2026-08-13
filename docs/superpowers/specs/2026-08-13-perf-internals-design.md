# Performance / Internals (Group 4) — Design

**Goal:** Make the existing pure-Ruby PGN/FEN hot paths faster and lay a
hashing foundation later groups can build on, without changing the public
behavior or byte output, and without adding native dependencies.

**Scope (this pass):** three concrete, benchmark-validated changes.
Everything else in Group 4 (precomputed attack masks, bitboard/C backend)
is deferred to a later pass.

1. Direct 0x88 FEN board-string builder.
2. Lazy position iteration for `PGN::Game`.
3. Incremental Zobrist hash on `PGN::Position`.

## 1. Direct 0x88 FEN board-string builder

**Problem.** `PGN::FEN#board_string` calls `board.squares`, which
rebuilds the full 8x8 array from the 0x88 `@cells` array on every call (8
file-maps × 8 rank-maps = 64 reads plus array allocations). `FEN#to_s` —
and therefore every `position.to_fen` / `game.fen_list` call — pays this
cost.

**Change.** Add `PGN::Board#fen_board_string` that walks `@cells` directly
in FEN order (rank 8 → rank 1, file a → file h), collapsing runs of `nil`
into digit counters, and joining the rows with `/`. `FEN#board_string` is
rewritten to delegate to it. The public `Board#squares` 8x8 API stays
unchanged (it is still used by `Board#inspect` and equality specs); only
the FEN path stops going through it.

**Output:** byte-identical to today (the `board_string round-trip` spec
already pins this).

**Benchmark signal:** a new `bench/profile_moves.rb` section measuring
FEN generation allocations/throughput for the immortal game's positions;
allocation count for `to_fen` must drop vs. the committed baseline.

## 2. Lazy position iteration for `PGN::Game`

**Problem.** `PGN::Game#positions` eagerly builds the full `Array` of
positions (one `Position` + one `Board#dup` per ply) the first time it is
called, and memoizes it. For a caller that only needs the last position,
or that wants to stream positions, this allocates and retains the whole
sequence.

**Change.** Keep `#positions` returning an `Array` (back-compat) but build
it lazily: add `#each_position` (returns an `Enumerator` when no block is
given, yields each successive position without materializing the array),
and have `#positions` be `each_position.to_a` with the existing memoization.
The replay loop is shared, so the eager and lazy paths produce identical
positions.

**Output/behavior:** `game.positions` still returns the same `Array`
(same objects, same order); `game.each_position.to_a == game.positions`.
New code can use `game.each_position { |p| ... }` to avoid the array.

**Benchmark signal:** a new section measuring allocations for "last
position only" via `each_position` vs. the eager `positions`; the lazy
path must allocate far fewer objects because it does not create the
`Array` and does not retain intermediate positions.

## 3. Incremental Zobrist hash on `PGN::Position`

**Problem / opportunity.** `Position` has no hash/equality; later groups
(threefold repetition, transposition tables) need one. Computing a hash
from scratch each move is wasteful; doing it incrementally on
`Position#move` keeps the cost off any future hot path and gives us
`Position#hash` / `#eql?` for free.

**Change.** Add a frozen `PGN::Zobrist` module containing:
- piece × square random 64-bit Integer table (`TABLE`),
- side-to-move (`SIDE`), castling (`CASTLING`), and en-passant-file
  (`EP_FILE`) keys,
- `Zobrist.seed(board, player, castling, en_passant)` for fresh hashes,
- `Zobrist.update(position, move, calculator, new_board, new_castling,
  new_ep)` for incremental hashes.

`Position` stores `@zobrist` (an Integer). `Position.start` seeds it
from the starting board; `Position#move` uses `Zobrist.update` to derive
the new hash by XOR-ing out/in only the changed squares, flipping the
side-to-move key, and updating castling/ep contributions. To avoid
seeding a new position twice, `Position#initialize` accepts an optional
`zobrist:` keyword; `#move` passes the precomputed incremental hash into
the constructor.

`Position#hash` returns `@zobrist`; `Position#eql?`/`#==` compare the
FEN-relevant fields (board cells, player, castling, en_passant — *not*
halfmove/fullmove, to match repetition semantics).

This is additive: no existing method is removed; `==`/`hash` are new and
only consumed by new specs in this pass. No existing behavior changes.

**Output/behavior:** no change to existing output; new `Position#hash`/
`#eql?`/`#==` are covered by dedicated specs.

**Benchmark signal:** `Position#hash` is O(1) (a single integer read).
The replay benchmark (section 1) will show a small allocation increase
because every position now carries `@zobrist`; that increase is an
acceptable, documented trade-off for the new capability. No other
benchmark section should regress.

## Global constraints

- Pure Ruby only; no new runtime dependencies; no C extension.
- Ruby 3.x stdlib (`Racc` + `StringScanner` already in use).
- Public output (FEN, PGN) stays byte-identical; the full spec suite
  stays green; no *new* RuboCop offenses in changed files (some files on
  `main` already have offenses; do not increase their offense count).
- Every change is validated against `bench/baseline_*.txt` (allocations
  drop or stay flat; throughput rises or stays flat), with the noted
  exception of the Zobrist maintenance cost in replay benchmarks.
- TDD: failing test first, then implementation, then green, then commit.
