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
    destination is already cheap); it pays in move-*generation* libraries
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
- `MoveCalculator#destination_coords` memoizes into `@dest_coords` based on
  `board`/`move`/`origin` never changing after `#initialize` — true today,
  but only by convention, since `board`, `move`, `origin` are all public
  `attr_accessor`s with no cache invalidation tied to their setters. If a
  future caller ever mutates and reuses a `MoveCalculator` instance, this
  memo goes stale silently. Either drop the public setters or invalidate
  `@dest_coords` when they're used.
