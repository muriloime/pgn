# Small + Medium TODO Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clear the small and medium TODO items left in `TODO.md`, leaning on the chessie-backed `PGN::Bitboard::Engine` where it removes pure-Ruby rewrite work.

**Architecture:** The gem stays pure-Ruby for parsing/serialization/position replay; legal-move generation and perft delegate to the native `PGN::Bitboard::Engine` (adapter over `chessie`). New public APIs live on `PGN::Position` / `PGN::Game` and delegate to the engine or to existing private `PGN::Notation` logic. No new Rust is required for these tasks except where noted.

**Tech Stack:** Ruby 3.0+, RSpec, RuboCop, Racc parser, `chessie` 2.0 via `pgn2-bitboard`/`pgn2_native`.

**Spec:** `TODO.md` (cleaned 2026-08-15) plus the in-chat sizing review. There is no separate design spec; this plan is the spec for these tasks.

## Global Constraints

- Ruby `>= 3.0` (`pgn2.gemspec`).
- Serialized PGN/FEN output must stay byte-identical unless a task explicitly changes a documented quirk.
- `PGN::Bitboard::Engine` is a required compiled artifact; APIs that need it raise `NameError` naturally if the extension is absent (match the existing `Position#legal_moves` behavior).
- Each task: write failing spec, implement, run `bundle exec rspec`, run `bundle exec rubocop`, commit.
- Native-dependent specs are skipped automatically when `PGN::Bitboard::Engine` is not defined (see `spec/bitboard_spec.rb`).

---

## Sizing summary

- Small: S1 `Position#legal?` + SAN legal moves, S2 EPD read/write, S3 UCI-style castling normalization, S4 left-recursive parser rules.
- Medium: M1 check/pin/attackers helpers, M2 game outcome detection, M3 idempotent `MoveText#clean_text`, M4 nested-comment normalization + brace escaping, M5 mutable push/pop history, M6 verify `release-gems.yml` cross-compile.

Suggested order: S1 → M1 → M2 (M2 uses S1), then S2, S3, S4, then M3 → M4 (related), then M5, then M6 (CI/packaging, can run in parallel with any).

---

## Task S1: Public `Position#legal?` and SAN legal moves

**Files:**
- Modify: `lib/pgn/position.rb`
- Create: `spec/position_legal_spec.rb`
- Reference: `lib/pgn/notation.rb` (`Notation.san(position, from, to, promotion)`), `ext/pgn2_native/pgn2_native/src/lib.rs` (`Engine#legal?(uci)`, `#legal_moves`)

**Interfaces:**
- Consumes: `PGN::Bitboard::Engine.new(fen).legal_moves` -> `Array<String>` sorted UCI; `PGN::Notation.san(position, from, to, promotion)` -> SAN string.
- Produces:
  - `PGN::Position#legal?(move)` -> `Boolean`; accepts SAN (`"Nf3"`, `"e4"`, `"O-O"`) or UCI (`"g1f3"`).
  - `PGN::Position#legal_moves_san` -> `Array<String>` sorted SAN.
  - `PGN::Position#to_uci(san)` -> `String` (private helper) returning the UCI whose SAN matches, or `nil`.

- [ ] **Step 1: Write failing spec**

```ruby
require 'spec_helper'

RSpec.describe PGN::Position, '#legal?' do
  let(:start) { PGN::Position.start }

  it 'accepts SAN' do
    expect(start.legal?('e4')).to be(true)
    expect(start.legal?('e5')).to be(false)
    expect(start.legal?('Nf3')).to be(true)
  end

  it 'accepts UCI' do
    expect(start.legal?('e2e4')).to be(true)
    expect(start.legal?('e2e5')).to be(false)
  end

  it 'handles castling and promotion SAN' do
    pos = PGN::FEN.new('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1').to_position
    expect(pos.legal?('O-O')).to be(true)
    expect(pos.legal?('O-O-O')).to be(true)
    promo = PGN::FEN.new('8/P7/8/8/8/8/8/4k2K w - - 0 1').to_position
    expect(promo.legal?('a8=Q')).to be(true)
    expect(promo.legal?('a8=N')).to be(true)
  end
end

RSpec.describe PGN::Position, '#legal_moves_san' do
  it 'returns sorted SAN for the start position' do
    sans = PGN::Position.start.legal_moves_san
    expect(sans.length).to eq(20)
    expect(sans).to include('e4', 'Nf3', 'd4')
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/position_legal_spec.rb`
Expected: FAIL with `undefined method 'legal?'` / `'legal_moves_san'`.

- [ ] **Step 3: Implement**

Add to `lib/pgn/position.rb`:

```ruby
# All legal moves from this position as sorted SAN strings, via the
# native engine's UCI move list and Notation.san. Requires the native
# extension; raises NameError if it is absent.
#
# @return [Array<String>] sorted lexicographically
def legal_moves_san
  engine = PGN::Bitboard::Engine.new(to_fen.to_s)
  engine.legal_moves.map { |uci| uci_to_san(uci) }.sort
end

# Whether +move+ is legal. Accepts SAN ("Nf3", "e4", "O-O", "a8=Q") or
# UCI ("g1f3", "e2e4", "e1g1", "a7a8q"). Requires the native extension.
#
# @param move [String] SAN or UCI
# @return [Boolean]
def legal?(move)
  return PGN::Bitboard::Engine.new(to_fen.to_s).legal?(move) if uci?(move)

  legal_moves_san.any? { |san| san == move || san.tr('+#!', '') == move }
end

private

def uci?(move)
  move.match?(/\A[a-h][1-8][a-h][1-8][qrbn]?\z/)
end

def uci_to_san(uci)
  from = uci[0, 2]
  to = uci[2, 2]
  promo = uci[5]
  PGN::Notation.san(self, from, to, promo)
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/position_legal_spec.rb`
Expected: PASS.

- [ ] **Step 5: Run full suite and RuboCop**

Run: `bundle exec rspec` and `bundle exec rubocop`
Expected: all green, no new offenses.

- [ ] **Step 6: Commit**

```bash
git add lib/pgn/position.rb spec/position_legal_spec.rb
git commit -m "feat(position): add #legal? and #legal_moves_san via chessie engine"
```

---

## Task S2: EPD read/write

**Files:**
- Create: `lib/pgn/epd.rb`
- Create: `spec/epd_spec.rb`
- Modify: `lib/pgn.rb` (require `pgn/epd`)
- Reference: `lib/pgn/fen.rb` for the shared board/side/castling/ep parsing.

**Interfaces:**
- Consumes: `PGN::FEN.from_attributes`, `PGN::Board.new`, `PGN::Position`.
- Produces:
  - `PGN::EPD.new(epd_string)` parses `placement side castling ep ops...`.
  - `PGN::EPD#to_position` -> `PGN::Position` (halfmove/fullmove default to `0`/`1`).
  - `PGN::EPD#to_s` -> EPD string.
  - `PGN::FEN#to_epd` -> EPD string (drop halfmove/fullmove).

- [ ] **Step 1: Write failing spec**

```ruby
require 'spec_helper'

RSpec.describe PGN::EPD do
  it 'parses the placement/side/castling/ep fields' do
    epd = PGN::EPD.new('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -')
    expect(epd.to_position.player).to eq(:white)
    expect(epd.to_position.castling).to eq(%w[K Q k q])
  end

  it 'round-trips a simple position' do
    s = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -'
    expect(PGN::EPD.new(s).to_s).to eq(s)
  end

  it 'FEN#to_epd drops the move counters' do
    expect(PGN::FEN.start.to_epd).to eq('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -')
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/epd_spec.rb`
Expected: FAIL with `uninitialized constant PGN::EPD`.

- [ ] **Step 3: Implement**

Create `lib/pgn/epd.rb` mirroring `PGN::FEN` but storing only `board`, `active`, `castling`, `en_passant`, and an `ops` string (remainder after the first four fields). Implement `#to_position` (halfmove `0`, fullmove `1`), `#to_s` (join the four fields plus `ops`), and `PGN::FEN#to_epd` returning `EPD.new(...).to_s` from the FEN's first four fields. Require it from `lib/pgn.rb`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/epd_spec.rb`
Expected: PASS.

- [ ] **Step 5: Run full suite and RuboCop; commit**

```bash
bundle exec rspec && bundle exec rubocop
git add lib/pgn/epd.rb spec/epd_spec.rb lib/pgn.rb
git commit -m "feat: add PGN::EPD read/write and FEN#to_epd"
```

---

## Task S3: UCI-style castling normalization

**Files:**
- Modify: `lib/pgn/move.rb` (`Move#castle=`) or add `Move#to_uci`-aware normalization
- Modify: `lib/pgn/game.rb` (`standardize_castling`) to also accept UCI-style `e1g1`? (scope: normalize `0-0` -> `O-O` is done; this task adds UCI-style castling recognition in SAN parsing where needed)
- Create: `spec/castling_normalization_spec.rb`

**Scope note:** This task is deliberately narrow: ensure `PGN::Move` and the serializer handle UCI-style castling tokens if they appear in movetext, and document that the canonical form remains `O-O`/`O-O-O`. If investigation shows the parser already rejects `e1g1` as a non-SAN move, the task reduces to a spec pinning the current behavior plus a `Move#castle` helper used by S1.

- [ ] **Step 1: Write failing spec** pinning expected behavior for `O-O`, `0-0`, and the UCI -> SAN mapping used by S1.
- [ ] **Step 2: Run test to verify it fails.**
- [ ] **Step 3: Implement** the smallest normalization needed (likely a `Move#to_san` or a constant map in `Notation` for castling UCI -> SAN).
- [ ] **Step 4: Run tests and RuboCop.**
- [ ] **Step 5: Commit** with `feat: normalize UCI-style castling to SAN`.

---

## Task S4: Left-recursive `tag_section` / `variation_list` rules

**Files:**
- Modify: `lib/pgn/pgn_parser.y` (`tag_section`, `variation_list`)
- Regenerate: `lib/pgn/pgn_parser.rb` via Racc (part of the build)
- Modify: `spec/parser_spec.rb` as needed to pin order
- Reference: `lib/pgn/pgn_parser.y` current right-recursive rules and their `reverse`/`merge` semantics.

**Interfaces:**
- Consumes: Racc grammar; existing `pgn_game` consumes `tag_section` and `element_sequence`.
- Produces: same parsed-game hashes with byte-identical `tags` order and `variations` order, but the reversal is a single explicit `.reverse` at consumption instead of implicit in recursion direction.

- [ ] **Step 1: Write/extend spec** that pins tag order and variation order for a multi-tag, multi-variation game (use the existing fixtures plus a crafted case).
- [ ] **Step 2: Run spec to confirm current behavior passes (baseline).**
- [ ] **Step 3: Rewrite rules** to ordinary left-recursion, building an in-order array, and add one explicit `.reverse` (and `merge` for first-occurrence-wins on tags) where `pgn_game` / `element` consumes the list.
- [ ] **Step 4: Regenerate parser** with Racc and run the full suite; confirm byte-identical output for all fixtures.
- [ ] **Step 5: Commit** with `refactor(parser): left-recursive tag/variation rules with explicit reverse`.

---

## Task M1: Check / pin / attackers helpers on `Position`

**Files:**
- Modify: `lib/pgn/position.rb`
- Reference: `lib/pgn/notation.rb` (`attacked?`, `king_idx`, `any_legal_move?` are private; `PGN::Bitboard::Engine#legal_moves` can also answer "in check")
- Create: `spec/position_attack_spec.rb`

**Interfaces:**
- Produces:
  - `PGN::Position#in_check?` -> `Boolean`
  - `PGN::Position#attackers(square)` -> `Array<String>` (algebraic squares attacking `square` for the side to move's opponent)
  - `PGN::Position#pinned?` (optional; can defer if chessie does not expose it easily)

- [ ] **Step 1: Write failing spec** for `in_check?` on a known checked position and `attackers` listing the checking pieces.
- [ ] **Step 2: Run to verify fail.**
- [ ] **Step 3: Implement** by extracting `Notation`'s private `attacked?`/`king_idx` into reusable module methods (or a thin `PGN::Attack` module) and exposing them on `Position`; prefer pure-Ruby extraction over a FFI round-trip for attackers listing.
- [ ] **Step 4: Run full suite and RuboCop.**
- [ ] **Step 5: Commit** with `feat(position): expose in_check? and attackers`.

---

## Task M2: Game outcome detection

**Files:**
- Modify: `lib/pgn/position.rb` / `lib/pgn/game.rb`
- Create: `spec/outcome_spec.rb`
- Reference: S1 (`#legal_moves`, `#legal_moves_san`), `PGN::Zobrist`/`Position#hash` for threefold.

**Interfaces:**
- Produces:
  - `PGN::Position#outcome` -> `:checkmate` | `:stalemate` | `:draw` | `nil`
  - `PGN::Game#outcome` -> same, computed from the final position plus history.
  - `PGN::Position#insufficient_material?` -> `Boolean`
  - `PGN::Position#fifty_move?` -> `Boolean` (uses `halfmove`)
  - `PGN::Game#threefold?` -> `Boolean` (uses `positions` hashes)

- [ ] **Step 1: Write failing spec** covering checkmate, stalemate, insufficient material (K vs K, K+B vs K), 50-move, and threefold via a short repeating game.
- [ ] **Step 2: Run to verify fail.**
- [ ] **Step 3: Implement** checkmate/stalemate with `legal_moves.empty?` + `in_check?` (S1/M1); insufficient material with a small piece-set rule; fifty-move with `halfmove >= 100`; threefold by counting `positions.map(&:hash)` (or streaming `each_position` to avoid materializing).
- [ ] **Step 4: Run full suite and RuboCop.**
- [ ] **Step 5: Commit** with `feat: add game/position outcome detection`.

---

## Task M3: Idempotent `MoveText#clean_text`

**Files:**
- Modify: `lib/pgn/game.rb` (`MoveText#clean_text`, `MoveText#initialize`, `Game#standardize_castling`)
- Modify: `spec/serializer_spec.rb` / `spec/parser_spec.rb`
- Reference: `lib/pgn/lexer.rb` `COMMENT` regex (already supports nested braces and escaped braces).

**Interfaces:**
- Produces: `MoveText#clean_text` returns the same result whether called zero, one, or many times; `Game#moves=` no longer sniffs for `{`/`}` to decide reuse.

- [ ] **Step 1: Write failing spec** that builds a `MoveText` with a nested/escaped comment, calls `clean_text` twice, and asserts equality; plus a spec that `moves=` reuses a braced-comment `MoveText` without re-cleaning.
- [ ] **Step 2: Run to verify fail.**
- [ ] **Step 3: Implement** a single-pass normalizer that strips only the outermost braces and preserves inner braces/escapes in a canonical form; cache the cleaned value on `@comment` so subsequent calls are no-ops; simplify `standardize_castling` to reuse unconditionally.
- [ ] **Step 4: Run full suite (watch for byte-output regressions) and RuboCop.**
- [ ] **Step 5: Commit** with `refactor(movetext): make clean_text idempotent and drop brace sniff`.

---

## Task M4: Nested-comment normalization + brace escaping for round trips

**Files:**
- Modify: `lib/pgn/lexer.rb` (comment token value), `lib/pgn/game.rb` (`MoveText`), `lib/pgn/serializer.rb` (`escape_comment`)
- Modify: `spec/parser_spec.rb`, `spec/serializer_spec.rb`
- Reference: `spec/pgn_files` for `nested_comments.pgn` fixture.

**Interfaces:**
- Produces: parse -> serialize -> parse is byte-identical for comments containing literal braces/escapes.

- [ ] **Step 1: Write failing spec** using the nested-comments fixture asserting `PGN.parse(game.to_pgn).first` equals the original parsed game for comment fields.
- [ ] **Step 2: Run to verify fail.**
- [ ] **Step 3: Implement** symmetric unescape in `MoveText#clean_text` (or a dedicated `Comment` value object) matching `Serializer#escape_comment`; decide one canonical internal representation and document it.
- [ ] **Step 4: Run full suite and RuboCop.**
- [ ] **Step 5: Commit** with `feat: round-trip nested comments and escaped braces`.

---

## Task M5: Mutable push/pop history

**Files:**
- Modify: `lib/pgn/game.rb`
- Create: `spec/game_history_spec.rb`

**Interfaces:**
- Produces:
  - `PGN::Game#push(san)` -> `self`; appends a move, invalidates `@positions`.
  - `PGN::Game#pop` -> `PGN::MoveText` or `nil`; removes the last move, invalidates `@positions`.
  - `PGN::Game#positions` stays consistent after mutations (memoization invalidated).

- [ ] **Step 1: Write failing spec** for push/pop and for `positions` reflecting the new move list after mutation.
- [ ] **Step 2: Run to verify fail.**
- [ ] **Step 3: Implement** `push` (validate via `Position#legal?` from S1 when available, else accept and document) and `pop`; clear `@positions`/`@starting_position` caches on mutation.
- [ ] **Step 4: Run full suite and RuboCop.**
- [ ] **Step 5: Commit** with `feat(game): add mutable push/pop history`.

---

## Task M6: Verify `release-gems.yml` cross-compile

**Files:**
- Modify: `.github/workflows/release-gems.yml` if needed
- Reference: `Rakefile` `native:gem` task, `ext/pgn2_native/extconf.rb`.

**Interfaces:** No code API; produces a verified CI artifact path.

- [ ] **Step 1: Run the cross-compile locally** with `bundle exec rake native:gem` (requires Docker) for x86_64/aarch64 linux+darwin.
- [ ] **Step 2: Inspect** the resulting platform gems and confirm `pgn2_native.so` is included for each platform.
- [ ] **Step 3: If the workflow is missing/broken**, update `.github/workflows/release-gems.yml` to run the same cross-compile on tag push.
- [ ] **Step 4: Trigger or simulate the workflow** and confirm it produces gems.
- [ ] **Step 5: Commit** any workflow fix with `ci: verify/fix prebuilt platform gem cross-compile`.

---

## Notes for executors

- S1 is the keystone for M1/M2; do it first.
- M3 and M4 are related; doing M3 first makes M4's scope clearer.
- Any task that changes parser output must be checked against `spec/pgn_files` fixtures for byte-identical round trips.
- If a task discovers the native extension cannot answer something needed (e.g., `pinned?`), prefer extracting existing pure-Ruby `Notation` logic over adding new Rust surface.
