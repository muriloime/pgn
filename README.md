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
are from the same machine (Ruby 4.0.5, x86_64-linux); allocation counts are
deterministic, throughput is over a 5 s window so treat ms/i as the stable
signal (ips is noisy).

Move pipeline — immortal game, 45 plies (`bench/profile_moves.rb`):

| Metric | original `pgn` | pgn2 | Δ |
|---|---:|---:|---:|
| Replay allocations (objects) | 5124 | 2565 | -2559 (-50.0%) |
| Replay allocations (bytes) | 262608 | 155296 | -107312 (-40.9%) |
| `Board#dup` x45 (objects) | 451 | 91 | -360 (-79.8%) |
| `Board#dup` x45 (bytes) | 43096 | 6736 | -36360 (-84.4%) |
| `Board#at(str)` x1000 (objects) | 6000 | 0 | -6000 (-100%) |
| `Board#at(str)` x1000 (bytes) | 240000 | 0 | -240000 (-100%) |
| Replay throughput | 1.132k ips (884 µs/i) | 1.669k ips (599 µs/i) | ~1.5x faster |

Parser — 500 immortal games (`bench/profile_parse.rb`):

| Metric | original `pgn` | pgn2 | Δ |
|---|---:|---:|---:|
| Parse-only allocations (objects) | 1248065 | 557035 | -691030 (-55.4%) |
| Parse-only allocations (bytes) | 120370470 | 36636902 | -83733568 (-69.6%) |
| Parse + replay allocations (objects) | 3778073 | 1614087 | -2163986 (-57.3%) |
| Parse + replay allocations (bytes) | 249570048 | 105404152 | -144165896 (-57.7%) |
| Parse-only throughput | 1.513 ips (661 ms/i) | 4.711 ips (212 ms/i) | ~3.1x faster |
| Parse + replay throughput | 0.933 ips (1070 ms/i) | 2.698 ips (371 ms/i) | ~2.9x faster |

What changed to get there:

1. `Board#at(str)` / `coordinates_for` — getbyte arithmetic (zero-alloc string lookup).
2. `MoveCalculator#king_position` — early exit.
3. `Move#initialize` — explicit setters (no per-move `names` array).
4. `FEN#board_string` — single-pass serialization.
5. `Board` — column-level copy-on-write (`dup` shares columns, `update` clones one).
6. Parser — `whittle` (≈80% of parse allocations) replaced by stdlib `Racc` +
   `StringScanner`; `PGN::Game#pgn` sliced from per-game byte offsets (no O(n²)
   `@@pgn +=` accumulation).

Public output (FEN, PGN) is byte-identical to the original gem; the full
suite (187 examples) stays green. See `bench/IMPROVEMENTS.md` for the per-step
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
