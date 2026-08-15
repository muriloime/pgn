# TODOs

## Parsing

- Accept a more flexible input format
- Tolerant parse mode: collect warnings/errors instead of failing on the
  first bad move.

## Roadmap ideas (from pioz/chess + python-chess review)

Out of scope for now: SVG rendering, Chess960, Shredder-FEN, FRC castling.

### Group 1 — PGN & Format Robustness

- [ ] Streaming/lazy PGN reader: yield games from an `IO` without slurping
      the whole file.

### Group 2 — Position Intelligence / Game Rules

`PGN::Bitboard::Engine` is a thin adapter over the `chessie` crate, so
several of these are implemented by delegating from `PGN::Position` to the
native engine rather than rewriting the logic in pure Ruby.

- [ ] Pin-aware helpers beyond `Position#attackers` (e.g. pinned-piece
      detection, discovered-check detection), delegating to chessie where
      useful.

### Group 3 — Engine & Analysis Integration

- [ ] Lightweight UCI/XBoard engine wrapper (`PGN::Engine`-style).
- [ ] PGN annotation helpers: auto-generate NAGs/comments from engine info.
- [ ] Optional Polyglot opening-book reader and/or Syzygy tablebase prober.

### Group 4 — Performance / Internals

- [ ] Incremental Zobrist hashing in `Board`/`Position` for fast repetition /
      transposition checks. Note: the previous attempt regressed replay
      because `Bignum` XOR allocations on every move dwarfed the gains;
      incremental update is only worth revisiting if something starts
      consuming hashes on the hot path (e.g. `Game#threefold?` now streams
      Zobrist hashes, so revisit if it shows up in profiles).
- [ ] Final Docker verification of the `release-gems.yml` cross-compile
      (rake-compiler-dock) for x86_64/aarch64 linux+darwin; the Rakefile
      cross-compile config and `native:clean` task are wired, but the full
      Docker build still wants confirming on a machine with Docker.
- [ ] `Engine#legal_p`/`legal?` compares candidate moves via
      `chessie::Move`'s `PartialEq<str>`, which allocates a `String` via
      `to_uci()` per candidate scanned. Currently negligible (offset by
      `legal_moves()` now being stack-allocated `ArrayVec` instead of a
      heap `Vec`, and dwarfed by movegen/FFI cost) — only worth a cheap
      numeric comparison if `legal?` ever ends up in a genuine hot loop.
