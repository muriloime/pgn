# `PGN::Game#to_pgn` serialization — design

- Date: 2026-08-12
- Status: Draft, awaiting review
- Repo: `git@github.com:muriloime/pgn.git` (gem `pgn2`)
- Sub-project: 1 of 4 (“add generic, reusable features to pgn2”)

## Context

`chessellence` uses `pgn2` only to parse/validate lesson PGNs at seed time. We
want to enhance pgn2 with generic, reusable features. This is the first of four
independent sub-projects, each with its own design → plan → implementation cycle:

1. **`PGN::Game#to_pgn` serializer** ← this document
2. FEN helpers / position utilities (parse, validate, compare, normalize)
3. Parser improvements (NAGs, recursive variations)
4. Server-side move/FEN validation API (legal moves, check/checkmate/draw)

`to_pgn` is first because it is self-contained, closes a long-standing TODO in
the gem, is immediately useful for exporting/sharing games from `chessellence`,
and does not depend on a rules engine.

## Goal

Produce a canonical PGN string from a `PGN::Game`’s structured data (tags,
moves, comments, annotations, variations, result), so that:

- `PGN.parse(game.to_pgn)` is equivalent to `game` (round-trippable).
- The output is valid PGN per the PGN spec for the features the parser already
  supports (movetext, comments, NAGs/symbolic annotations, variations, FEN
  start tag, game result).
- The gem remains free of app-specific behavior; nothing here knows about
  `chessellence`.

## Non-goals

- No move legality validation, no check/checkmate detection. A `PGN::Game`
  built from arbitrary SAN serializes as given. (Validation is sub-project 4.)
- No line wrapping / 80-column formatting in v1. Output is a single movetext
  line. Wrapping can be added later as an option without changing the core.
- No preservation of the original raw `pgn` formatting. `to_pgn` serializes
  from structured data, not from the `Game#pgn` attribute.
- No changes to the parser in this sub-project.

## API

```ruby
class PGN::Game
  # @return [String] a canonical PGN string for this game
  def to_pgn
    PGN::Serializer.new(self).to_s
  end
end
```

- Returns a String ending with a trailing newline.
- No options in v1 (YAGNI). A future `width:` option for line wrapping can be
  added without breaking callers.

Implementation lives in a new `PGN::Serializer` class so `PGN::Game` stays thin
and the serialization logic is independently testable.

## Output structure

A game serializes as up to two sections separated by a blank line:

1. **Tag section** — one tag pair per line, in the order of `game.tags`:
   `[Key "Value"]`. If `tags` is `nil` or empty, emit a synthesized
   `[Result "<result or *>"]` tag instead. The current parser grammar
   requires at least one tag pair, so this keeps no-tag games parseable; it
   means a no-tag game round-trips with a single `Result` tag added.
2. **Movetext section** — optional game comment, then moves, then result.

```
[Event "Zurich Chess Challenge"]
[White "Carlsen, Magnus"]

1. c4 g6 2. d4 Nf6 ... 1-0
```

If there are no moves, the movetext section is just the game comment (if any)
followed by the result. (The tag section is never entirely omitted — see
above.)

## Movetext rules

State tracked while emitting a line (mainline or variation):

- `fullmove` — starts from `game.starting_position.fullmove` (1 by default).
- `player` — starts from `game.starting_position.player` (`:white` by default).
- `prev_player` — the color of the previously emitted move in the current
  line (`nil` at the start of a line/variation).
- `prev_had_extras` — whether the previous move emitted any annotation,
  comment, or variation.

For each `MoveText` in the line:

- If `player == :white`:
  - Emit `"<fullmove>."` then the move token.
- If `player == :black`:
  - Emit `"<fullmove>..."` before the move token when a number is needed:
    - at the start of a line/variation (`prev_player.nil?`),
    - after a comment/annotation/variation on the previous move
      (`prev_had_extras`),
    - when the previous move was not white (`prev_player != :white`).
  - Otherwise emit the move token with no number (conventional
    `1. e4 e5 2. Nf3 ...` style).
- After emitting, update state:
  - `prev_player = player`
  - `prev_had_extras = move had annotation, comment, or variation`
  - If `player == :black`, `fullmove += 1`.
  - `player = opposite`.

This reproduces the conventional style and keeps black move numbers
unambiguous after comments/variations, e.g. the `variations.pgn` fixture:

```
1. e4 e5 2. Nf3 {comment} (2. Nc3 {other} d5 (2... f5) 3. exd5) (2. f4 exf4 {final variation}) 2... Nf6 *
```

### Move token

A move token is the notation plus trailing extras, joined by spaces:

1. `move.notation` (e.g. `e4`, `O-O`, `Nef6+`, `--`).
2. Each element of `move.annotation` (e.g. `$2`, `??`), in order.
3. `move.comment` as `{ ... }`, if present.
4. Each variation as `( ... )`, if present.

Variations are serialized recursively with the same movetext rules, starting
from the position **before** the move they are attached to (same `fullmove`
and `player` as that move). Variations do not affect the enclosing line’s
`fullmove`/`player` state.

### Game comment

If `game.comment` is present, it is emitted as the first token of the movetext
section, wrapped as `{ ... }`, before any move numbers.

### Result

The result token is appended last:

- `game.result` if present and non-empty.
- `"*"` otherwise.

### Castling and `--`

- The parser already normalizes `0` to `O` in `Game#moves=`, so castling
  serializes as `O-O` / `O-O-O`.
- `--` (“don’t care”) moves serialize verbatim and are treated as a normal ply
  for color/fullmove alternation, matching `Position#move`’s behavior.

## Starting position

`PGN::Game#starting_position` already returns a `PGN::Position` from the `FEN`
tag (or the standard start). The serializer uses only its `fullmove` and
`player` to seed movetext state. It does **not** replay moves on a board, so
invalid games still serialize. This means a game starting with black to move
from a FEN tag emits its first move as `1... ...`.

## Escaping

- **Tag values:** escape `\` and `"`:
  `value.to_s.gsub('\\', '\\\\\\\\').gsub('"', '\\"')`.
- **Comments:** wrap in `{ ... }` and escape `\`, `{`, and `}` for correctness.
  Note: the current parser’s `MoveText#clean_text` does not unescape inner
  braces, so a comment containing escaped braces will not round-trip
  byte-for-byte until parser improvements (sub-project 3) add unescaping. For
  v1, tests avoid literal braces inside comment text; the serializer is still
  correct for the spec.
- **Annotations:** emitted verbatim (`$n` or symbolic `?!` forms).
- **Notation:** emitted verbatim.

## Edge cases

- No tags → emit a synthesized `[Result "<result or *>"]` tag (keeps output
  parseable by the current grammar; a no-tag game round-trips with that tag
  added).
- No moves → emit game comment (if any) and result only.
- No result → emit `*`.
- `nil`/empty annotation or comment → omit (do not emit empty `{}`).
- `nil`/empty variations → omit.
- Game starting with black to move (FEN tag) → first move numbered `1...`.
- Manually constructed game (`PGN::Game.new(%w[e4 e5])`) → tag section
  `[Result "*"]` then `1. e4 e5 *`.

## Testing

New `spec/serializer_spec.rb` (RSpec, matching existing style) plus a few
`#to_pgn` cases in `spec/game_spec.rb`. Cases:

1. Simple game with tags and result:
   `PGN::Game.new(%w[e4 e5], { 'White' => 'A', 'Black' => 'B' }, '1-0')`
   → `[White "A"]\n[Black "B"]\n\n1. e4 e5 1-0`.
2. Manually constructed game with no tags → `[Result "*"]\n\n1. e4 e5 *`.
3. Castling serializes as `O-O` / `O-O-O`.
4. Annotations: `$4`, `??` emitted after notation.
5. Comments and variations: reproduces `variations.pgn` movetext shape,
   including `2...` after variations.
6. FEN start with black to move → first move `1...`.
7. Empty game: `PGN::Game.new([], nil, '*')` → `*`.
8. Game comment only: `PGN::Game.new([], nil, '*', nil, 'game comment')`
   → `{ game comment } *`.
9. **Round-trip:** for each fixture in `spec/pgn_files`, parse → `to_pgn` →
   parse again, then compare `result`, `moves` (notation), per-move
   `annotation`, `comment`, and `variations`, and that the reparsed `tags` are a
   superset of the original (a no-tag game gains a `Result` tag). This does not
   require byte-for-byte equality with the original file.

## Future considerations (not in this sub-project)

- Optional line wrapping (`width:` argument) to respect the PGN 80-column
  recommendation.
- Canonical Seven-Tag-Roster ordering/normalization option.
- Exact raw-PGN preservation is out of scope; callers that want the original
  source should use `Game#pgn`.
