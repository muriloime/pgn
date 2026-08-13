# TODOs

## Parsing

- Accept a more flexible input format
- Support recursive variations
- Support numeric annotation glyphs

## Misc

- Support converting a game to pgn format
- Speed up parsing
  - Collapse PGN::Lexer's per-token allocation chain (Array in `scan_one` ->
    `Token` struct -> Array in racc's `next_token`) to fewer allocations on
    the hot path; keep the full `Token` (with offset/line) only for the
    `#tokens` spec helper, which is its only consumer.
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
