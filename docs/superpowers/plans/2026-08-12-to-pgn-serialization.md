# `PGN::Game#to_pgn` serializer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a canonical PGN string from a `PGN::Game` via `PGN::Game#to_pgn`, backed by a new `PGN::Serializer` class, so that parse → `to_pgn` → parse round-trips.

**Architecture:** A new `PGN::Serializer` class converts a `PGN::Game` into a String (tags section + blank line + movetext section, trailing newline). `PGN::Game#to_pgn` delegates to it. Serialization is purely structural (no board replay, no legality checks), seeding movetext numbering state from `game.starting_position.fullmove`/`player`.

**Tech Stack:** Ruby, RSpec, the existing `pgn2` gem (whittle parser).

## Global Constraints

- No changes to the parser in this sub-project.
- No move legality validation; serialize moves as given.
- No line wrapping; v1 emits a single movetext line.
- Returns a String ending with a trailing newline.
- No app-specific behavior; nothing here knows about `chessellence`.
- `nil`/empty annotation, comment, or variations are omitted (no empty `{}`).
- Tag values escape `\` and `"`; comments escape `\`, `{`, `}`.

---

## File Structure

- Create: `lib/pgn/serializer.rb` — `PGN::Serializer`, all serialization logic.
- Modify: `lib/pgn.rb` — `require 'pgn/serializer'`.
- Modify: `lib/pgn/game.rb` — add `PGN::Game#to_pgn` delegating to `PGN::Serializer`.
- Create: `spec/serializer_spec.rb` — RSpec cases for the serializer.
- Modify: `spec/game_spec.rb` — add a few `#to_pgn` cases.

---

## Task 1: `PGN::Serializer` core — tags + simple movetext

**Files:**
- Create: `lib/pgn/serializer.rb`
- Modify: `lib/pgn.rb`
- Test: `spec/serializer_spec.rb`

**Interfaces:**
- Produces: `PGN::Serializer.new(game)` and `PGN::Serializer#to_s` returning the canonical PGN string (with trailing newline).

- [ ] **Step 1: Write failing tests** for the simple cases in `spec/serializer_spec.rb`:
  - Tags + result: `PGN::Game.new(%w[e4 e5], { 'White' => 'A', 'Black' => 'B' }, '1-0')` → `[White "A"]\n[Black "B"]\n\n1. e4 e5 1-0\n`.
  - No tags → `[Result "*"]\n\n1. e4 e5 *\n`.
  - Empty game: `PGN::Game.new([], nil, '*')` → `[Result "*"]\n\n*\n`.
  - No result → ends with `*\n`.

- [ ] **Step 2: Run tests, verify they fail** with `NameError` (no `PGN::Serializer`).

Run: `bundle exec rspec spec/serializer_spec.rb`
Expected: FAIL, uninitialized constant `PGN::Serializer`.

- [ ] **Step 3: Implement `PGN::Serializer`** (`lib/pgn/serializer.rb`) with tag escaping, the synthesized `Result` tag, movetext numbering (white `n.`, black `n...` only when needed), and result. Add `require 'pgn/serializer'` to `lib/pgn.rb`.

- [ ] **Step 4: Run tests, verify pass.**

Run: `bundle exec rspec spec/serializer_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit.**
  `git add lib/pgn/serializer.rb lib/pgn.rb spec/serializer_spec.rb && git commit -m "feat: add PGN::Serializer with tags and basic movetext"`

---

## Task 2: Annotations, comments, and variations

**Files:**
- Modify: `lib/pgn/serializer.rb`
- Test: `spec/serializer_spec.rb`

**Interfaces:**
- Consumes: `MoveText#notation`, `#annotation` (Array), `#comment` (String), `#variations` (Array of Arrays of `MoveText`).
- Produces: move tokens `notation + annotation + {comment} + (variation)`; recursive variation serialization starting from the position before the move.

- [ ] **Step 1: Write failing tests:**
  - Castling serializes as `O-O` / `O-O-O` (`PGN::Game.new(%w[O-O O-O-O])`).
  - Annotations: a move with annotation `['$4']` → `e4 $4`; `['??']` → `e4 ??`.
  - Two annotations: `['$2', '$11']` → `d5 $2 $11`.
  - Comment: move with comment `c` → `e4 {c}`.
  - Variations reproduces `spec/pgn_files/variations.pgn` movetext shape, including `2...` after variations: expected movetext `1. e4 e5 2. Nf3 {comment} (2. Nc3 {other} d5 (2... f5) 3. exd5) (2. f4 exf4 {final variation}) 2... Nf6 *` (plus tag section `[White "Somebody"]\n[Black "Petrov"]`).

- [ ] **Step 2: Run tests, verify they fail.**

Run: `bundle exec rspec spec/serializer_spec.rb -e "annotation\|comment\|variation\|Castling"`
Expected: FAIL.

- [ ] **Step 3: Implement** move-token assembly (notation + annotation + comment + recursive variations) and `prev_had_extras`/`prev_player` numbering rules from the spec. Variations start from the same `fullmove`/`player` as the move they attach to and do not affect enclosing state.

- [ ] **Step 4: Run tests, verify pass.**

Run: `bundle exec rspec spec/serializer_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit.**
  `git add lib/pgn/serializer.rb spec/serializer_spec.rb && git commit -m "feat: serialize annotations, comments, and variations"`

---

## Task 3: Game comment, FEN start, and `--` moves

**Files:**
- Modify: `lib/pgn/serializer.rb`
- Test: `spec/serializer_spec.rb`

- [ ] **Step 1: Write failing tests:**
  - Game comment only: `PGN::Game.new([], nil, '*', nil, 'game comment')` → `[Result "*"]\n\n{ game comment } *\n`.
  - FEN start with black to move: a game built from `spec/pgn_files/fen.pgn`-style FEN where `active` is `b`, first move numbered `1...`. Construct via `PGN.parse` of a PGN with a `FEN` tag whose active color is `b`.
  - `--` move serializes verbatim and alternates color/fullmove: `PGN::Game.new(%w[-- e4])` → `1. -- e4`.

- [ ] **Step 2: Run tests, verify they fail.**

Run: `bundle exec rspec spec/serializer_spec.rb -e "game comment\|FEN\|don"`
Expected: FAIL.

- [ ] **Step 3: Implement** game-comment emission (first movetext token, wrapped in `{ }`), and confirm FEN seeding already works via `starting_position.fullmove`/`player` (no board replay). Add comment escaping.

- [ ] **Step 4: Run tests, verify pass.**

Run: `bundle exec rspec spec/serializer_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit.**
  `git add lib/pgn/serializer.rb spec/serializer_spec.rb && git commit -m "feat: serialize game comments, FEN-start numbering, and -- moves"`

---

## Task 4: `PGN::Game#to_pgn` + round-trip fixture tests

**Files:**
- Modify: `lib/pgn/game.rb`
- Modify: `spec/game_spec.rb`

**Interfaces:**
- Produces: `PGN::Game#to_pgn` returning `PGN::Serializer.new(self).to_s`.

- [ ] **Step 1: Write failing tests** in `spec/game_spec.rb`:
  - `#to_pgn` returns a string ending in newline for `PGN::Game.new(%w[e4 e5], { 'White' => 'A' }, '1-0')`.
  - Round-trip: for each fixture in `spec/pgn_files`, parse → `to_pgn` → parse, compare `result`, `moves` (notation), per-move `annotation`/`comment`/`variations`, and that reparsed `tags` are a superset of original (a no-tag game gains a `Result` tag).

- [ ] **Step 2: Run tests, verify they fail** (no `#to_pgn`).

Run: `bundle exec rspec spec/game_spec.rb`
Expected: FAIL, undefined method `to_pgn`.

- [ ] **Step 3: Implement `PGN::Game#to_pgn`** delegating to `PGN::Serializer`.

- [ ] **Step 4: Run full suite, verify pass.**

Run: `bundle exec rspec`
Expected: PASS (all examples).

- [ ] **Step 5: Commit.**
  `git add lib/pgn/game.rb spec/game_spec.rb && git commit -m "feat: add PGN::Game#to_pgn with round-trip fixture tests"`

---

## Self-Review

- **Spec coverage:** tag section + synthesized Result tag (T1), movetext numbering incl. `n...` rules (T1/T2), move token with annotation/comment/variations (T2), recursive variations from prior position (T2), game comment (T3), FEN/black-to-move seeding (T3), `--` (T3), `to_pgn` API + trailing newline (T1/T4), escaping (T1/T3), edge cases (T1/T3), round-trip fixture tests (T4). ✓
- **Placeholder scan:** no TBD/TODO. ✓
- **Type consistency:** `PGN::Serializer.new(game)`, `#to_s`, `PGN::Game#to_pgn` consistent across tasks. `MoveText` accessors match existing `game.rb` (`notation`, `annotation`, `comment`, `variations`). ✓
