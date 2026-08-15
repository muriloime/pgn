# TODOs

## Parsing

- Accept a more flexible input format
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

## Roadmap ideas (from pioz/chess + python-chess review)

Out of scope for now: SVG rendering, Chess960, Shredder-FEN, FRC castling.

### Group 1 — PGN & Format Robustness

- [ ] Streaming/lazy PGN reader: yield games from an `IO` without slurping
      the whole file.
- [ ] EPD read/write (`EPD#to_position`, `FEN#to_epd`).
- [ ] Richer game-tree API: node-style mainline/variations, add/promote/
      demote variations.
- [ ] Nested-comment normalization + brace escaping for byte-perfect round
      trips.
- [ ] Tolerant parse mode: collect warnings/errors instead of failing on the
      first bad move.

### Group 2 — Position Intelligence / Game Rules

`PGN::Bitboard::Engine` is now a thin adapter over the `chessie` crate, so
several of these can be implemented by delegating from `PGN::Position` to
the native engine (or by using chessie’s FEN-based answers) instead of
rewriting the logic in pure Ruby.

- [ ] Full legal-move API: `Position#legal?(san_or_uci)` and SAN-based
      `Position#legal_moves`, delegating to `PGN::Bitboard::Engine` where
      possible. `Position#legal_moves` already returns sorted UCI from the
      engine; a clean SAN entry point and a `Position#legal?` predicate are
      still missing publicly.
- [ ] Check / pin / attackers helper methods exposed on `Position` (logic
      already exists privately in `Notation`; chessie can also answer this
      from a FEN).
- [ ] Game outcome detection: checkmate, stalemate, insufficient material,
      50-move rule, threefold repetition.
- [ ] Mutable push/pop history (`game.push(san)`, `game.pop`).

### Group 3 — Engine & Analysis Integration

- [ ] Lightweight UCI/XBoard engine wrapper (`PGN::Engine`-style).
- [ ] PGN annotation helpers: auto-generate NAGs/comments from engine info.
- [ ] Optional Polyglot opening-book reader and/or Syzygy tablebase prober.
- [ ] UCI-style castling normalization (see pioz/chess).

### Group 4 — Performance / Internals

- [ ] Incremental Zobrist hashing in `Board`/`Position` for fast repetition /
      transposition checks. Note: the previous attempt regressed replay
      because `Bignum` XOR allocations on every move dwarfed the gains;
      incremental update is only worth revisiting if something starts
      consuming hashes on the hot path.
- [ ] Verify the `release-gems.yml` cross-compile (rake-compiler-dock) for
      x86_64/aarch64 linux+darwin before relying on prebuilt gems.
