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
- Speed up replay via a board-representation rewrite (deferred "Approach B"):
  per-line profiling shows the remaining replay allocations are architectural
  — `MoveCalculator#first_piece` scan-return arrays (~5/ply, the #1 site) and
  `Board#position_for` string joins (~3/ply). Do these as ONE coherent
  rewrite (not separately, to avoid throwing away work):
  (a) a piece-location index (piece → squares) so king/disambiguation/origin
    lookups are O(1) instead of scanning 64 squares — kills `first_piece` scan
    arrays AND the dominant replay compute (`valid_square?`/`at` ≈ 15/ply calls);
  (b) a coordinate-only internal board (int square keys, no `"e4"` strings on
    the hot path) — kills `position_for` strings + `changes` string keys.
  Caveat: `change!`/`update`/`position_for`/`coordinates_for`/`squares` are
  spec-tested public API, so the new representation must be additive (string
  API kept). Realistic ceiling ~2× replay allocation + ~1.5–2× throughput;
  medium-high risk (Board/MoveCalculator/Position/FEN). Only worth it given a
  real hot-loop need (replay is already ~0.8 ms/ply).
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
