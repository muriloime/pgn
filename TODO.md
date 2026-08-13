# TODOs

## Parsing

- Accept a more flexible input format
- Support recursive variations
- Support numeric annotation glyphs

## Misc

- Support converting a game to pgn format
- Speed up parsing
  - ✓ (done in 1.2.0) Removed `PGN::Lexer`'s per-token `Token` Struct
    allocation on the parser hot path (`next_token_pair`), and collapsed
    `scan_one`'s `[type, m, discarded]` tuple to a single returned string
    (type/discarded stashed in ivars). The full `Token` is kept only for the
    `#tokens` spec helper. Parse allocations −42% (603537 → 347037 / 500 games).
- Speed up replay via a board-representation rewrite ("Approach B"): done.
  (b) ✓ (done in 1.3.0) Rewrote `Board` internals to the classic 0x88
  representation (128-cell array indexed by `rank*16+file`) and rewrote
  `MoveCalculator` to work entirely in single-integer square indices via
  `Board#at_index`/`#apply!`, so the replay hot path no longer allocates
  `[file,rank]` coordinate arrays or square-name strings. Off-board is a
  single bitmask (`(idx & 0x88).zero?`, ~1.6x faster than a 0..7 bounds
  check) and ray stepping is a single integer add. Algorithm unchanged, so
  output is byte-identical. Measured (immortal game): replay 798→535 µs/i
  (+49% throughput), allocations 1571→976 objects (−38%) / 92440→62064 bytes
  (−33%); parse+replay +21% throughput. 182 specs green, 0 new rubocop
  offenses vs main. The public string/coord API is preserved (additive).
  (c) Two related ideas were left alone during cleanup rather than "fixed",
  since fixing them would cost more than they're worth right now. First,
  `Board#squares` rebuilds the full 8x8 array from `@cells` on every call
  (9 allocations, 64 reads); it's off the replay hot path by design, but
  `FEN#to_s` round-trips through it on every position-to-FEN call, so FEN
  generation pays that cost repeatedly. Memoizing would mean invalidating
  the cache from `update`/`apply!`, i.e. adding a write to the actual hot
  path to speed up a path that isn't hot -- the wrong trade; if FEN
  generation becomes hot, have it read `@cells` directly instead. Second,
  `Board#dup` uses `Board.allocate` plus `instance_variable_set` to copy
  `@cells` directly and skip that same conversion -- a deliberate
  hot-path shortcut (`dup` runs every move), but it bypasses the public
  constructor via reflection, so there's no real "build a Board from raw
  cells" factory, just this one-off reach-around; a `Board.from_cells`
  factory would be cleaner without changing the perf story. Also
  considered and not attempted: column-granularity copy-on-write in
  `dup` (the pre-0x88 Board only duplicated touched file-columns on
  write); the flat 0x88 array trades that away for simplicity and the
  +49% throughput measured above, and reintroducing it would need its
  own A/B before it's worth the complexity.
  (a) ✗ (attempted, rejected) A piece-location index (piece → 0x88 indices)
  maintained in `update`/`apply!` and used for O(1) slider/leaper/king
  origin lookups. Implemented on top of (b), all 182 specs green, but it
  **regressed**: replay 526→727 µs/i (+38% slower), allocations 976→1591
  objects (+63%). Root cause: `Board#dup` (called every move) must clone
  the index (`transform_values(&:dup)` ≈ 12 piece arrays) — Board#dup went
  91→676 objects — and every move pays per-update index maintenance
  (`<<`/`delete`) that pawns (the most common move type, whose origins are
  geometry-fixed and can't use the index) pay for no benefit. The index
  helps sliders/leapers (minority of moves) but the dup + maintenance cost
  is paid by every move. Conclusion: a global piece index is a loss for
  replay (where only ONE given move is validated, so ray-scanning from the
  destination is already cheap); it pays in move-_generation_ libraries
  (chess.js/python-chess) that enumerate ALL legal moves. Not worth a COW
  variant either (maintenance + pawns). Reverted; (b) alone is the winner.
- Replace the right-recursive `tag_section`/`variation_list` rules in
  `pgn_parser.y` with ordinary left-recursion plus one explicit `.reverse`
  at the point each list is consumed, so the legacy whittle-order
  compatibility quirk is a single greppable line instead of implicit in
  recursion direction.
- Make `MoveText#clean_text` idempotent (or run it exactly once, at
  construction) so `Game#moves=`/`#standardize_castling` doesn't need to
  sniff a comment for leftover `{`/`}` to decide whether a MoveText is safe
  to reuse as-is. The brace check is a bandaid for `clean_text` not fully
  normalizing multi-line/nested comments in one pass; fixing that at the
  source would let `moves=` reuse unconditionally.
- `MoveCalculator#dest_idx` (formerly `#destination_coords`, renamed in the
  1.3.0 0x88 rewrite) memoizes into `@dest_idx` based on `board`/`move`
  never changing after `#initialize` — true today, but only by convention,
  since `board` and `move` are public `attr_accessor`s with no cache
  invalidation tied to their setters. If a future caller ever mutates and
  reuses a `MoveCalculator` instance, this memo goes stale silently. Either
  drop the public setters or invalidate `@dest_idx` when they're used.
  Relatedly, the `||=` doesn't actually memoize for castling moves (where
  `move.destination` is `nil`, so the right-hand side re-evaluates every
  call); harmless since the result is nil either way and castling is rare,
  but worth a `defined?(@dest_idx)` guard if this method gets hotter.
