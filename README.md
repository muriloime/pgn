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
