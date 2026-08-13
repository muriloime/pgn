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
| Replay allocations (objects) | 5124 | 1571 | -3553 (-69.3%) |
| Replay allocations (bytes) | 262608 | 92440 | -170168 (-64.8%) |
| `Board#dup` x45 (objects) | 451 | 136 | -315 (-69.8%) |
| `Board#dup` x45 (bytes) | 43096 | 10336 | -32760 (-76.0%) |
| `Board#at(str)` x1000 (objects) | 6000 | 0 | -6000 (-100%) |
| `Board#at(str)` x1000 (bytes) | 240000 | 0 | -240000 (-100%) |
| Replay throughput | 841 µs/i | 741 µs/i | ~1.14x faster |

Parser — 500 immortal games (`bench/profile_parse.rb`):

| Metric | original `pgn` | pgn2 | Δ |
|---|---:|---:|---:|
| Parse-only allocations (objects) | 1248065 | 347037 | -901028 (-72.2%) |
| Parse-only allocations (bytes) | 120370470 | 17977414 | -102393056 (-85.1%) |
| Parse + replay allocations (objects) | 3778073 | 1101586 | -2676487 (-70.9%) |
| Parse + replay allocations (bytes) | 249570048 | 62164136 | -187405912 (-75.1%) |
| Parse-only throughput | 1461 ms/i | 305 ms/i | ~4.8x faster |
| Parse + replay throughput | 1938 ms/i | 816 ms/i | ~2.4x faster |

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

Public output (FEN, PGN) is byte-identical to the original gem; the full
suite (182 examples) stays green. See `bench/IMPROVEMENTS.md` for the per-step
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
