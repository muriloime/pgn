# PGN2

[![CI](https://github.com/muriloime/pgn/actions/workflows/ci.yml/badge.svg)](https://github.com/muriloime/pgn/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/pgn2.svg)](https://rubygems.org/gems/pgn2)

A PGN parser and FEN generator for Ruby, with a serializer and an interactive
play mode. The parser is built on the Ruby standard library (`Racc` +
`StringScanner`) and has no native or third-party runtime dependencies.

This is a fork of the [pgn](https://github.com/capicue/pgn) gem.

## Usage

### Creating games from pgn files

On the command line, it is easy to read in and play through chess games
in [portable game notation](http://en.wikipedia.org/wiki/Portable_Game_Notation) format.

```
> games = PGN.parse(File.read("./examples/immortal_game.pgn"))
> game  = games.first
> game.play
```

Play through the game using `a` or left arrow to move backward, and `d`
or right arrow to move forward. `q` or `^C` quits play mode.

    ♜ ♞ ♝ ♛ ♚ ♝ ♞ ♜
    ♟ ♟ ♟ ♟ ♟ ♟ ♟ ♟
    _ _ _ _ _ _ _ _
    _ _ _ _ _ _ _ _
    _ _ _ _ _ _ _ _
    _ _ _ _ _ _ _ _
    ♙ ♙ ♙ ♙ ♙ ♙ ♙ ♙
    ♖ ♘ ♗ ♕ ♔ ♗ ♘ ♖

    ♜ ♞ ♝ ♛ ♚ ♝ ♞ ♜
    ♟ ♟ ♟ ♟ ♟ ♟ ♟ ♟
    _ _ _ _ _ _ _ _
    _ _ _ _ _ _ _ _
    _ _ _ _ _ _ _ _
    _ _ _ _ ♙ _ _ _
    _ _ _ _ _ _ _ _
    ♙ ♙ ♙ ♙ _ ♙ ♙ ♙
    ♖ ♘ ♗ ♕ ♔ ♗ ♘ ♖

    ...

You can also access all of the information about a game.

```
> game.positions.last
=>
♜ _ ♝ ♚ _ _ _ ♜
♟ _ _ ♟ ♗ ♟ ♘ ♟
♞ _ _ _ _ ♞ _ _
_ ♟ _ ♘ ♙ _ _ ♙
_ _ _ _ _ _ ♙ _
_ _ _ ♙ _ _ _ _
♙ _ ♙ _ ♔ _ _ _
♛ _ _ _ _ _ ♝ _

> game.positions.last.to_fen
=> r1bk3r/p2pBpNp/n4n2/1p1NP2P/6P1/3P4/P1P1K3/q5b1 b - - 1 22

> game.result
=> "1-0"

> game.tags["White"]
=> "Adolf Anderssen"
```

It is possible to create a game without parsing a pgn file.

```
moves = %w{e4 c5 c3 d5 exd5 Qxd5 d4 Nf6}
game = PGN::Game.new(moves)
```

Note that if you simply want an abstract syntax tree from the pgn file,
you can use `PGN::Parser.parse`.

### Serializing games

A game round-trips to PGN text with `PGN::Game#to_pgn` (or `PGN::Serializer`):

```
> game.to_pgn
=> "[Event \"?\"]\n[Site \"?\"]\n[White \"Adolf Anderssen\"]\n...\n1. e4 e5 2. Nf3 ... 1-0\n"

> PGN.parse(game.to_pgn).first.result == game.result
=> true
```

Comments, variations, annotations, the `FEN` starting position, and game
comments are all serialized. See `spec/game_spec.rb` for the round-trip
gate that exercises every fixture.

### Dealing with FEN strings

[Forsyth Edwards Notation](http://en.wikipedia.org/wiki/Forsyth%E2%80%93Edwards_Notation)
is a compact way to represent all of the information about a given chess
position. It is easy to convert between FEN strings and chess positions.

```
> fen = PGN::FEN.start
=> rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1

> fen = PGN::FEN.new("r1bk3r/p2pBpNp/n4n2/1p1NP2P/6P1/3P4/P1P1K3/q5b1 b - - 1 22")
> position = fen.to_position
=>
♜ _ ♝ ♚ _ _ _ ♜
♟ _ _ ♟ ♗ ♟ ♘ ♟
♞ _ _ _ _ ♞ _ _
_ ♟ _ ♘ ♙ _ _ ♙
_ _ _ _ _ _ ♙ _
_ _ _ ♙ _ _ _ _
♙ _ ♙ _ ♔ _ _ _
♛ _ _ _ _ _ ♝ _

> position.to_fen
=> r1bk3r/p2pBpNp/n4n2/1p1NP2P/6P1/3P4/P1P1K3/q5b1 b - - 1 22
```

### Generating SAN from coordinates

{PGN::Notation} is the reverse of {PGN::Move}: it *builds* Standard
Algebraic Notation for a coordinate move (origin square, destination square,
optional promotion) given the position before the move. Use it to render
moves stored as coordinates in standard chess notation.

```
> PGN::Notation.san(PGN::Position.start, "g1", "f3")
=> "Nf3"

> PGN::Notation.san_from_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "e2", "e4")
=> "e4"

> fen = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"
> PGN::Notation.san_from_fen(fen, "e1", "g1")
=> "O-O"
```

It handles captures, en passant, promotions, legal-move disambiguation
(file / rank / full square, respecting pins), and check (`+`) / checkmate
(`#`) suffixes.

## Benchmarks

A reproducible profiling harness lives in `bench/`. It measures the
allocation and throughput cost of the hot paths (move application, board
copying, parsing), so efficiency changes can be proven with a before/after
diff of committed baselines.

Run the full suite (writes/updates the committed baseline files):

```
bundle exec rake bench
```

Individual profiles:

```
bundle exec rake bench:moves  # move/board profiling only
bundle exec rake bench:parse  # parse profiling only
```

`bench/baseline_moves.txt` and `bench/baseline_parse.txt` are committed
snapshots of the current implementation. After an optimization, re-run
`rake bench` and `git diff` the baseline files: allocation counts/bytes
should drop, ips numbers should rise.

### Compared to the original `pgn` gem

pgn2 is a fork of the upstream [`pgn`](https://github.com/capicue/pgn) gem.
The "original" figures below come from `bench/*.pre-optimization.txt`,
snapshots captured before any hot-path work — at that point pgn2's parser
(`whittle`), `Board#dup` (flat copy), and `Board#at(str)` (string-alloc)
were byte-for-byte the original gem's code. The "pgn2" figures are the
current committed baselines (stdlib `Racc` + `StringScanner` parser,
column-level copy-on-write `Board`, getbyte-arithmetic `at`). All numbers
are from the same machine (Ruby 4.0.5, x86_64-linux). **Allocation counts
are deterministic** and the headline signal. **Throughput is reported as the
median of N back-to-back wall-clock runs** (whittle-era commit `1360bfc` vs
current `main`): the `benchmark-ips` harness has ±30–60% per-run variance, so
its single-run `ms/i` is not reliable across versions — e.g. the Racc baseline
once recorded 371 ms/i (±37%) for parse+replay but the same commit measures
~1017 ms reproduced today. `bench/baseline_*.txt` remains the harness of
record for allocations.

Move pipeline — immortal game, 45 plies (`bench/profile_moves.rb`):

| Metric | original `pgn` | pgn2 | Δ |
|---|---:|---:|---:|
| Replay allocations (objects) | 5124 | 976 | -4148 (-80.9%) |
| Replay allocations (bytes) | 262608 | 62064 | -200544 (-76.4%) |
| `Board#dup` x45 (objects) | 451 | 91 | -360 (-79.8%) |
| `Board#dup` x45 (bytes) | 43096 | 3856 | -39240 (-91.1%) |
| `Board#at(str)` x1000 (objects) | 6000 | 0 | -6000 (-100%) |
| `Board#at(str)` x1000 (bytes) | 240000 | 0 | -240000 (-100%) |
| Replay throughput | 841 µs/i | 517 µs/i | ~1.63x faster |

Parser — 500 immortal games (`bench/profile_parse.rb`):

| Metric | original `pgn` | pgn2 | Δ |
|---|---:|---:|---:|
| Parse-only allocations (objects) | 1248065 | 288537 | -959528 (-76.9%) |
| Parse-only allocations (bytes) | 120370470 | 15640374 | -104730096 (-87.0%) |
| Parse + replay allocations (objects) | 3778073 | 773530 | -3004543 (-79.5%) |
| Parse + replay allocations (bytes) | 249570048 | 45706128 | -203863920 (-81.7%) |
| Parse-only throughput | 1461 ms/i | 203 ms/i | ~7.2x faster |
| Parse + replay throughput | 1938 ms/i | 484 ms/i | ~4.0x faster |

What changed to get there:

1. `Board#at(str)` / `coordinates_for` — getbyte arithmetic (zero-alloc string lookup).
2. `MoveCalculator#king_position` — early exit.
3. `Move#initialize` — explicit setters (no per-move `names` array).
4. `FEN#board_string` — single-pass serialization.
5. `Board` — column-level copy-on-write (`dup` shares columns, `update` clones one).
6. Parser — `whittle` (≈80% of parse allocations) replaced by stdlib `Racc` +
   `StringScanner`; `PGN::Game#pgn` sliced from per-game byte offsets (no O(n²)
   `@@pgn +=` accumulation).
7. `PGN::Lexer#next_token_pair` — parser hot path returns `[type, value]`
   without allocating a `Token` Struct (or its `keyword_init` Hash), via a
   shared scanning routine that preserves `game_starts` for verbatim `pgn` slicing.
8. `PGN::Game#moves=` — reuse existing `MoveText` when its comment is already
   clean; halve `MoveText` allocations on the parse path (still re-wraps to
   preserve the legacy double-`clean_text` for multi-line/nested comments).
9. `PGN::Move#piece=` — non-allocating castling guard (`start_with?('O')`
   instead of `match('O-O')`), removing a `MatchData` from every `Move.new`.
10. `PGN::Position#next_player` — ternary instead of `(PLAYERS - [player])`;
    `Position#move` skips `castling - restrictions` when there are none.
11. `PGN::MoveCalculator` — memoized `destination_coords`, frozen
    `ROOK_RESTRICTIONS`, empty short-circuit in `castling_restrictions`;
    `Move#pawn?` non-allocating.
12. `PGN::Lexer#scan_one` — returns the matched string directly (stashing
    type/discarded in ivars) instead of a 3-element `[type, m, discarded]`
    tuple, so the parser hot path now allocates only the single `[type, value]`
    array Racc requires per token. Cuts parse allocations ~42% (603537 → 347037
    objects for 500 games).
13. `PGN::MoveCalculator#valid_square?` — integer bounds (`file >= 0 && file < 8`)
    instead of `(0..7).include?` (≈3.4x faster per call, zero-alloc, in the
    board-scan inner loops); `#compute_origin` — string `case` dispatch instead
    of regex `/[brq]/i` matches; `#first_piece` — returns only the `[file, rank]`
    square via a `piece_at` helper instead of a `[piece, square]` tuple. Replay
    throughput +8.2% (766 → 741 µs/i), replay allocations −8% (1710 → 1571
    objects). Board-scanning origin lookup is ~46% of replay CPU; the
    piece-location-index rewrite that would cut it remains deferred.
14. `PGN::Board` / `PGN::MoveCalculator` — 0x88 board representation. `Board`
    internals are now a 128-cell array indexed by `rank*16+file` (the classic
    0x88 scheme), and `MoveCalculator` works entirely in single-integer square
    indices via `Board#at_index`/`#apply!`, so the replay hot path no longer
    allocates `[file,rank]` coordinate arrays or square-name strings.
    Off-board is a single bitmask (`(idx & 0x88).zero?`, ~1.6x faster than a
    0..7 bounds check) and ray stepping is a single integer add. Algorithm
    unchanged → byte-identical output. Replay throughput +49% (798 → 517 µs/i),
    replay allocations −38% (1571 → 976 objects) / −33% (92440 → 62064 bytes),
    parse+replay +21% throughput. A companion piece-location index (piece →
    0x88 indices for O(1) origin/king lookups) was implemented on top, passed
    all specs, but *regressed* (replay 526→727 µs/i, allocations +63%): `dup`
    must clone the index every move and every move pays maintenance that pawns
    (the common case, geometry-fixed origins) can't use — so it was rejected
    and reverted. The 0x88 board alone is the winner.
15. `PGN::Lexer#scan_one` — byte-dispatch: the leading byte of the next
    token selects the 1-2 `RULES` that can possibly match it (a frozen
    `BYTE_DISPATCH` table; `ALL_RULES` fallback) instead of walking all nine
    rules in order. `StringScanner#scan` was ~23% of parse CPU and the rule
    loop ~38% inclusive; the dispatch nearly halves scan time. `PgnParser#
    next_token` now mutates the lexer's `[type, value]` pair in place instead
    of allocating a second translated pair (one array per token is the Racc
    floor). Parse-only throughput +25% (305 → 203 ms/i), parse allocations
    −17% (347037 → 288537 objects / 17977414 → 15640374 bytes for 500 games).
    Output byte-identical.
16. `PGN::Board#fen_board_string` — serializes the FEN board string by
    walking the 0x88 `@cells` array directly (ranks 8→1, files a→h, empty-run
    collapsing) instead of rebuilding the 8x8 `squares` array and
    transposing on every `position.to_fen` / `game.fen_list`. `FEN#board_string`
    delegates to it. FEN output byte-identical. Measured on the immortal game
    (46 positions): FEN generation allocations −40% (3201 → 1913 objects /
    231104 → 100464 bytes), ~1.44× throughput (1140 → 792 µs/i). Adds a new
    `bench/baseline_moves.txt` section 5/6 for FEN allocation/throughput.
17. `PGN::Game#each_position` / `PGN::Zobrist` — additive features, not hot-
    path wins. `each_position` is a lazy enumerator sharing the replay loop
    with `#positions` (one `Enumerator` per `#positions` call, hence the
    parse+replay +500 objects / +80000 bytes in the table above vs. the prior
    baseline). `PGN::Zobrist` provides a deterministic 64-bit hash table and
    `Position#zobrist`/`#hash`/`#eql?`/`#==`; the hash is computed lazily and
    cached, so the replay hot path (which never asks for it) pays nothing —
    an incremental per-move update was prototyped and rejected because 64-bit
    Integer XOR allocates a `Bignum` per operation (~9/move), regressing
    replay +40% allocations / −32% throughput for a feature nothing
    currently consumes. Replay stays at 976 objects / 62064 bytes.

Public output (FEN, PGN) is byte-identical to the original gem; the full
suite (222 examples) stays green. See `bench/IMPROVEMENTS.md` for the per-step
before/after deltas that produced these tables.

## Installation

Add this line to your application's Gemfile:

    gem 'pgn2'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install pgn2

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature` from `main`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Open a Pull Request against `main`

See `CHANGELOG.md` for release history.
