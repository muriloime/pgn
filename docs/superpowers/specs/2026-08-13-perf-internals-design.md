# Performance / Internals (Group 4) — Design

**Goal:** Make the existing pure-Ruby PGN/FEN hot paths faster and lay a
hashing foundation later groups can build on, without changing the public
API or byte output, and without adding native dependencies.

**Scope (this pass):** three concrete, benchmark-validated changes.
Everything else in Group 4 (precomputed attack masks, bitboard/C backend)
is deferred to a later pass.

1. Direct 0x88 FEN board-string builder.
2. Lazy position iteration for `PGN::Game`.
3. Incremental Zobrist hash on `PGN::Position`.

## 1. Direct 0x88 FEN board-string builder

**Problem.** `PGN::FEN#board_string` calls `self.board.squares`, which
rebuilds the full 8x8 array from the 0x88 `@cells` array on every call (8
file-maps × 8 rank-maps = 9 array allocations, 64 reads). `FEN#to_s` — and
therefore every `position.to_fen` / `game.fen_list` call — pays this cost.

**Change.** Add `PGN::Board#fen_board_string` that walks `@cells` directly
in FEN order (rank 8 → rank 1, file a → file h), collapsing runs of `nil`
into digit counters, and join the rows with `/`. `FEN#board_string` is
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
called, and memoizes it. For a game that only wants the last position, or
a caller that streams positions, this is unnecessary allocation and
holds the whole game's positions alive.

**Change.** Keep `#positions` returning an `Array` (back-compat) but build
it lazily: add `#each_position` (returns an `Enumerator` when no block is
given, yields each successive position without materializing the array),
and have `#positions` be `each_position.to_a` with the existing memoization.
The replay loop is shared, so the eager and lazy paths produce identical
positions.

**Output/behavior:** `game.positions` still returns the same `Array`
(same objects, same order); `game.each_position.to_a == game.positions`.
New code can use `game.each_position { |p| ... }` to avoid the array.

**Benchmark signal:** a new section measuring peak allocations for
"last position only" via `each_position` vs. the eager `positions`; the
lazy path must allocate O(1) positions instead of O(plies).

## 3. Incremental Zobrist hash on `PGN::Position`

**Problem / opportunity.** `Position` has no hash/equality; later groups
(threefold repetition, transposition) need one. Computing a hash from
scratch each time is wasteful; doing it incrementally on `Position#move`
keeps the cost off any future hot path and gives us `Position#hash` /
`#eql?` for free.

**Change.** Add a frozen `Zobrist` table (piece × square random 64-bit
Integers, plus player-to-move, castling, en-passant file) as a private
constant. `Position` stores `@zobrist` (an Integer). `Position.start`
seeds it from the starting board; `Position#move` updates it by XOR-ing
out the moved/captured/castled pieces and in the new ones, flipping the
side-to-move bit, and adjusting castling/ep fields. `Position#hash`
returns `@zobrist`; `Position#eql?`/`==` compare the FEN-relevant fields
(board cells, player, castling, en_passant — *not* halfmove/fullmove, to
match repetition semantics).

This is additive: no existing method is removed; `==`/`hash` are new and
only consumed by new specs in this pass (a position-equality spec and a
"hash is stable across equivalent positions" spec). No existing behavior
changes.

**Output/behavior:** no change to existing output; new `Position#hash`/
`#eql?`/`==` are covered by dedicated specs.

**Benchmark signal:** `Position#hash` is O(1) (a single integer read);
no benchmark regression to `replay` beyond the documented maintenance
cost, validated against the committed baseline.

## Global constraints

- Pure Ruby only; no new runtime dependencies; no C extension.
- Ruby 3.x stdlib (`Racc` + `StringScanner` already in use).
- Public output (FEN, PGN) stays byte-identical; the full spec suite
  (currently 201 examples) stays green; no new RuboCop offenses vs. `main`.
- Every change is validated against `bench/baseline_*.txt` (allocations
  drop or stay flat; throughput rises or stays flat).
- TDD: failing test first, then implementation, then green, then commit.
