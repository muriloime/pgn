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
