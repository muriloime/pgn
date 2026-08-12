# Efficiency Tests + Profiling Harness — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an exhaustive regression-test net for the hot-path classes (`PGN::Board`, `PGN::Move`, `PGN::MoveCalculator`, expanded `PGN::Position`) and a reproducible profiling harness that captures a committed **baseline** of allocations and timing, so that a later optimization plan can prove (via before/after diff) that efficiency actually improved.

**Architecture:** Two layers. (1) RSpec specs that characterize the *current observable behavior* of the move-application pipeline through public APIs only (board squares, castling array, halfmove/fullmove counters, en-passant square, FEN round-trip) — never poking private methods, so the tests survive the refactors they exist to protect. (2) A `bench/` directory of standalone Ruby scripts using stdlib `Benchmark` plus dev-dep gems `benchmark-ips` (timing) and `memory_profiler` (allocation accounting), driven by a `rake bench` task, writing human-readable baseline reports into `bench/baseline_*.txt` that are committed at the current HEAD.

**Tech Stack:** Ruby 4.0.5, RSpec 3.13 (`expect`/`to` syntax for new specs; existing `should`-style specs are left untouched), `benchmark-ips`, `memory_profiler`, the existing `pgn2` gem + `whittle` parser. Workload fixtures come from `examples/immortal_game.pgn` (a real 23-move, 45-ply game) and the synthetic multi-game corpus derived from it.

## Global Constraints

- **No changes to `lib/` in this plan.** This plan only adds tests and benchmark tooling. The algorithms stay exactly as they are so the baseline reflects current performance.
- New specs use modern RSpec `expect(...).to ...` syntax. Do not rewrite the existing `should`-style specs (`parser_spec.rb`, `position_spec.rb`, `fen_spec.rb`) — leave them as-is.
- All new specs must **pass against the current implementation** (this plan is a characterization/regression net, not a bug-fix). If a written expectation does not match real behavior, the test is wrong, not the code — adjust the test.
- `PGN::Board.start` returns a board backed by the shared, frozen `PGN::Board::START` constant. **Do not mutate `PGN::Board.start` directly in specs**; use `.dup` whenever a test needs to update a board. This prevents random-order failures caused by shared mutable inner arrays.
- Profiling harness must be **deterministic and reproducible**: fixed fixtures, fixed iteration counts, no wall-clock dependence in the committed baseline numbers (ips is informational; the committed baseline focuses on *allocation counts/bytes*, which are stable).
- Baseline report files (`bench/baseline_moves.txt`, `bench/baseline_parse.txt`) are committed to the repo so optimization work can `git diff` them.
- Do not add `bench/baseline_*.txt` to `.gitignore`; do add `/bench/tmp` if any scratch files are needed (none are required here).
- No new runtime dependencies. `benchmark-ips` and `memory_profiler` are **development** dependencies only.
- `PGN.parse` uses class variables (`@@pgn`, `@@game_comment`); do not try to fix that here. Profiling must call `PGN.parse` in the main thread sequentially (it already does).

---

## Why these tests and these metrics (rationale, for the implementer)

The three proposed optimizations (in a *future* plan) target:

| Proposed optimization | Current cost | What this plan measures |
|---|---|---|
| Flat / copy-on-write `Board` | `Board#dup` copies all 8 column arrays per move (O(64) per move) | `Board#dup` allocation share; total allocations per replayed ply |
| Cache / early-exit `king_position` | O(64) full-board scan, every disambiguation | Replay throughput (ips) on games with disambiguation; allocations per replay |
| `Board#at(str)` coord arithmetic | `position.chars.to_a` + 2 hash lookups per string lookup | String-path allocation counts |

A regression net is mandatory because **none of `Board`, `Move`, or `MoveCalculator` have any specs today** — only `Position` (thin), `FEN`, `Game`, `Parser`, `Serializer` are tested. Refactoring the hot path without these tests is unsafe. The profiling harness quantifies the wins.

---

## File Structure

- **Modify:** `pgn2.gemspec` — add `benchmark-ips` and `memory_profiler` as dev dependencies.
- **Modify:** `Rakefile` — add `bench` namespace tasks.
- **Modify:** `README.md` — add a "Benchmarks" section.
- **Create:** `spec/board_spec.rb` — exhaustive `PGN::Board` characterization.
- **Create:** `spec/move_spec.rb` — exhaustive `PGN::Move` SAN-parsing characterization.
- **Create:** `spec/move_calculator_spec.rb` — exhaustive move-application characterization (origin resolution, disambiguation, castling, en passant, counters).
- **Modify:** `spec/position_spec.rb` — expand to exhaustive `PGN::Position` coverage (add new `describe` blocks; keep existing `should` blocks intact).
- **Create:** `bench/profile_moves.rb` — per-move allocation + replay-throughput profiling.
- **Create:** `bench/profile_parse.rb` — parse + parse-and-replay allocation/throughput profiling on a synthetic corpus.
- **Create:** `bench/baseline_moves.txt` — committed baseline (output of `bench/profile_moves.rb`).
- **Create:** `bench/baseline_parse.txt` — committed baseline (output of `bench/profile_parse.rb`).

---

## Task 1: Add profiling dev dependencies + `bench/` scaffolding

**Files:**
- Modify: `pgn2.gemspec`
- Create: `bench/.keep`

**Interfaces:**
- Produces: `benchmark-ips` and `memory_profiler` available via `require 'benchmark/ips'` and `require 'memory_profiler'` after `bundle install`; an empty `bench/` directory present in git.

- [ ] **Step 1: Add dev dependencies to `pgn2.gemspec`.** In the dev-dependency block, after the `rspec` line, add:

```ruby
  spec.add_development_dependency 'benchmark-ips'
  spec.add_development_dependency 'memory_profiler'
```

- [ ] **Step 2: Create the `bench/` directory so it is tracked even before scripts exist.**

```bash
mkdir -p bench
touch bench/.keep
```

- [ ] **Step 3: Install the new gems and verify they load.**

```bash
bundle install
bundle exec ruby -e "require 'benchmark/ips'; require 'memory_profiler'; puts 'ok'"
```
Expected: prints `ok` with no error.

- [ ] **Step 4: Commit.**

```bash
git add pgn2.gemspec Gemfile.lock bench/.keep
git commit -m "chore: add benchmark-ips and memory_profiler dev deps + bench/ scaffold"
```

---

## Task 2: Exhaustive `PGN::Board` spec

**Files:**
- Create: `spec/board_spec.rb`

**Interfaces:**
- Consumes: `PGN::Board.start`, `PGN::Board#at`, `#update`, `#change!`, `#coordinates_for`, `#position_for`, `#dup`, `#inspect`, constant `PGN::Board::START`.
- Produces: a green characterization suite that pins `Board`'s public behavior for the upcoming flat-board refactor.

Coverage checklist (each bullet = one or more `it` blocks):
- `.start` returns a board whose `squares == PGN::Board::START`.
- `#at(str)` and `#at(file, rank)` agree for a sample of squares; correct pieces at the start position (e.g. `at("a1")=="R"`, `at("e1")=="K"`, `at("e2")=="P"`, `at("e7")=="p"`, `at("e8")=="k"`); empty squares return `nil`.
- `#coordinates_for` / `#position_for` round-trip all 64 squares.
- `#update` places a piece and mutates `self`; returns `self`.
- `#change!` applies a multi-square hash at once and mutates `self`; returns `self`.
- `#dup` returns a `PGN::Board` with equal `squares` but independent arrays (mutating the copy does not affect the original, and vice-versa).
- `#inspect` returns a String containing the unicode pawn glyph and at least one newline.

- [ ] **Step 1: Write the failing test file `spec/board_spec.rb`.**

```ruby
require 'spec_helper'

describe PGN::Board do
  describe '.start' do
    it 'uses the START constant for its squares' do
      expect(PGN::Board.start.squares).to eq(PGN::Board::START)
    end
  end

  describe '#at' do
    # Use .dup because PGN::Board.start returns the same shared board
    # backed by the frozen START constant.
    let(:board) { PGN::Board.start.dup }

    it 'returns the starting pieces on their home squares' do
      expect(board.at('a1')).to eq('R')
      expect(board.at('b1')).to eq('N')
      expect(board.at('c1')).to eq('B')
      expect(board.at('d1')).to eq('Q')
      expect(board.at('e1')).to eq('K')
      expect(board.at('h1')).to eq('R')
      expect(board.at('a2')).to eq('P')
      expect(board.at('e2')).to eq('P')
      expect(board.at('a7')).to eq('p')
      expect(board.at('e8')).to eq('k')
      expect(board.at('d8')).to eq('q')
    end

    it 'returns nil for empty squares' do
      expect(board.at('e3')).to be_nil
      expect(board.at('d4')).to be_nil
      expect(board.at('a3')).to be_nil
    end

    it 'agrees between the string and coordinate overloads' do
      expect(board.at('e4')).to eq(board.at(4, 3))
      expect(board.at('a1')).to eq(board.at(0, 0))
      expect(board.at('h8')).to eq(board.at(7, 7))
    end
  end

  describe '#coordinates_for / #position_for' do
    it 'round-trips every square on the board' do
      ('a'..'h').each_with_index do |file, fi|
        ('1'..'8').each_with_index do |rank, ri|
          square = "#{file}#{rank}"
          expect(PGN::Board.start.coordinates_for(square)).to eq([fi, ri])
          expect(PGN::Board.start.position_for([fi, ri])).to eq(square)
        end
      end
    end
  end

  describe '#update' do
    it 'places a piece and mutates self, returning self' do
      board = PGN::Board.start.dup
      result = board.update('e4', 'P')
      expect(result).to be(board)
      expect(board.at('e4')).to eq('P')
    end

    it 'can clear a square with nil' do
      board = PGN::Board.start.dup
      board.update('e2', nil)
      expect(board.at('e2')).to be_nil
    end
  end

  describe '#change!' do
    it 'applies several squares at once and returns self' do
      board = PGN::Board.start.dup
      result = board.change!('e2' => nil, 'e4' => 'P')
      expect(result).to be(board)
      expect(board.at('e2')).to be_nil
      expect(board.at('e4')).to eq('P')
    end
  end

  describe '#dup' do
    it 'returns a PGN::Board with equal squares' do
      original = PGN::Board.start.dup
      copy = original.dup
      expect(copy).to be_a(PGN::Board)
      expect(copy.squares).to eq(original.squares)
    end

    it 'is independent: mutating the copy leaves the original untouched' do
      original = PGN::Board.start.dup
      copy = original.dup
      copy.update('e4', 'Q')
      expect(original.at('e4')).to be_nil
      expect(copy.at('e4')).to eq('Q')
    end

    it 'is independent: mutating the original leaves the copy untouched' do
      original = PGN::Board.start.dup
      copy = original.dup
      original.update('e4', 'Q')
      expect(copy.at('e4')).to be_nil
    end
  end

  describe '#inspect' do
    it 'returns a string with unicode pieces and newlines' do
      inspected = PGN::Board.start.inspect
      expect(inspected).to be_a(String)
      expect(inspected).to include("\u{2659}") # white pawn
      expect(inspected).to include("\n")
    end
  end
end
```

- [ ] **Step 2: Run the spec, verify it passes against the current implementation.**

Run: `bundle exec rspec spec/board_spec.rb --format documentation`
Expected: PASS (all examples green). If any expectation fails, the *test* is wrong — re-read `lib/pgn/board.rb` and correct the expectation, not the library.

- [ ] **Step 3: Commit.**

```bash
git add spec/board_spec.rb
git commit -m "test: exhaustive PGN::Board characterization spec"
```

---

## Task 3: Exhaustive `PGN::Move` spec

**Files:**
- Create: `spec/move_spec.rb`

**Interfaces:**
- Consumes: `PGN::Move.new(san, player)` and its readers `piece, destination, promotion, check, capture, disambiguation, castle`, plus predicates `pawn?, white?, black?, check?, checkmate?`.
- Produces: a green characterization suite pinning SAN parsing, which the `MoveCalculator` depends on.

Coverage checklist:
- Pawn push white/black (`e4`, `d5`) → `piece` `P`/`p`, `pawn?` true, `capture` false.
- Pawn capture (`exd5`) → `piece` `P`, `capture` true, `disambiguation` `'e'`, `destination` `'d5'`.
- Piece moves (`Nf3`, `Bc4`, `Qd1`, `Ke2`) → correct `piece`, `destination`, `pawn?` false.
- Disambiguation by file (`Nbd2`), by rank (`N4c3`), by capture+file (`Raxc1`).
- Promotion white (`e8=Q`) and black (`b8=Q` → `promotion` `'q'` lowercase), with capture+promotion (`exd8=Q`).
- Check (`g5+`) → `check` `'+'`, `check?` true; mate (`Qe7#`) → `check` `'#'`, `checkmate?` true.
- Castling white `O-O` → `castle` `'K'`, `O-O-O` → `castle` `'Q'`; black `O-O` → `castle` `'k'`, `O-O-O` → `castle` `'q'`. `piece` is `nil` for castling.
- Don't-care move (`--`) → no match, `piece` `nil`, `destination` `nil`, `pawn?` false.
- `white?`/`black?` follow the `player` argument.

- [ ] **Step 1: Write the failing test file `spec/move_spec.rb`.**

```ruby
require 'spec_helper'

describe PGN::Move do
  describe 'pawn pushes' do
    it 'parses a white pawn push' do
      m = PGN::Move.new('e4', :white)
      expect(m.piece).to eq('P')
      expect(m.destination).to eq('e4')
      expect(m.capture).to eq(false)
      expect(m.pawn?).to eq(true)
      expect(m.white?).to eq(true)
    end

    it 'parses a black pawn push' do
      m = PGN::Move.new('d5', :black)
      expect(m.piece).to eq('p')
      expect(m.destination).to eq('d5')
      expect(m.pawn?).to eq(true)
      expect(m.black?).to eq(true)
    end
  end

  describe 'pawn captures' do
    it 'parses a pawn capture, using the file as disambiguation' do
      m = PGN::Move.new('exd5', :white)
      expect(m.piece).to eq('P')
      expect(m.capture).to eq(true)
      expect(m.disambiguation).to eq('e')
      expect(m.destination).to eq('d5')
    end
  end

  describe 'piece moves' do
    it 'parses knight, bishop, queen, king moves' do
      expect(PGN::Move.new('Nf3', :white).piece).to eq('N')
      expect(PGN::Move.new('Bc4', :white).piece).to eq('B')
      expect(PGN::Move.new('Qd1', :white).piece).to eq('Q')
      expect(PGN::Move.new('Ke2', :white).piece).to eq('K')
    end

    it 'parses black piece moves as lowercase' do
      expect(PGN::Move.new('Nf6', :black).piece).to eq('n')
      expect(PGN::Move.new('Qd8', :black).piece).to eq('q')
    end

    it 'is not a pawn for piece moves' do
      expect(PGN::Move.new('Nf3', :white).pawn?).to eq(false)
    end
  end

  describe 'disambiguation' do
    it 'parses file disambiguation' do
      m = PGN::Move.new('Nbd2', :white)
      expect(m.piece).to eq('N')
      expect(m.disambiguation).to eq('b')
      expect(m.destination).to eq('d2')
    end

    it 'parses rank disambiguation' do
      m = PGN::Move.new('N4c3', :white)
      expect(m.disambiguation).to eq('4')
      expect(m.destination).to eq('c3')
    end

    it 'parses a capturing disambiguated rook move' do
      m = PGN::Move.new('Raxc1', :white)
      expect(m.piece).to eq('R')
      expect(m.disambiguation).to eq('a')
      expect(m.capture).to eq(true)
      expect(m.destination).to eq('c1')
    end
  end

  describe 'promotion' do
    it 'parses a white promotion' do
      m = PGN::Move.new('e8=Q', :white)
      expect(m.piece).to eq('P')
      expect(m.destination).to eq('e8')
      expect(m.promotion).to eq('Q')
    end

    it 'lowercases the promotion piece for black' do
      m = PGN::Move.new('b8=Q', :black)
      expect(m.promotion).to eq('q')
    end

    it 'parses a capturing promotion' do
      m = PGN::Move.new('exd8=Q', :white)
      expect(m.capture).to eq(true)
      expect(m.disambiguation).to eq('e')
      expect(m.destination).to eq('d8')
      expect(m.promotion).to eq('Q')
    end
  end

  describe 'check and mate' do
    it 'parses a checking move' do
      m = PGN::Move.new('g5+', :white)
      expect(m.check).to eq('+')
      expect(m.check?).to eq(true)
      expect(m.checkmate?).to eq(false)
    end

    it 'parses a checkmate move' do
      m = PGN::Move.new('Qe7#', :white)
      expect(m.check).to eq('#')
      expect(m.checkmate?).to eq(true)
      expect(m.check?).to eq(false)
    end
  end

  describe 'castling' do
    it 'parses white kingside and queenside' do
      expect(PGN::Move.new('O-O', :white).castle).to eq('K')
      expect(PGN::Move.new('O-O-O', :white).castle).to eq('Q')
    end

    it 'parses black kingside and queenside (lowercase)' do
      expect(PGN::Move.new('O-O', :black).castle).to eq('k')
      expect(PGN::Move.new('O-O-O', :black).castle).to eq('q')
    end

    it 'has nil piece for castling moves' do
      expect(PGN::Move.new('O-O', :white).piece).to be_nil
    end
  end

  describe "the don't-care move" do
    it 'parses -- as a no-op with no piece or destination' do
      m = PGN::Move.new('--', :white)
      expect(m.piece).to be_nil
      expect(m.destination).to be_nil
      expect(m.pawn?).to eq(false)
    end
  end
end
```

- [ ] **Step 2: Run the spec, verify it passes.**

Run: `bundle exec rspec spec/move_spec.rb --format documentation`
Expected: PASS. If a case fails, re-read `lib/pgn/move.rb` (esp. the `SAN_REGEX` and the custom setters) and fix the expectation.

- [ ] **Step 3: Commit.**

```bash
git add spec/move_spec.rb
git commit -m "test: exhaustive PGN::Move SAN-parsing characterization spec"
```

---

## Task 4: Exhaustive `PGN::MoveCalculator` spec

**Files:**
- Create: `spec/move_calculator_spec.rb`

**Interfaces:**
- Consumes: indirectly via `PGN::FEN.new(fen).to_position.move(san)` → `PGN::Position#move`, which constructs `PGN::MoveCalculator`. Public observable surface: `PGN::Position#board`, `#castling`, `#en_passant`, `#halfmove`, `#fullmove`, `#player`. (We never instantiate `MoveCalculator` directly — this keeps tests stable across its planned refactor.)
- Produces: a green suite pinning origin resolution, disambiguation, castling mechanics, en passant, and counter updates.

This is the heart of the regression net. Tests assert *which squares changed* (origin emptied, destination filled), plus castling-array / counter / en-passant effects.

Coverage checklist (each built from a real FEN so the path is unambiguous):

- Pawn single push (white e4 from start, black d5).
- Pawn double push (white e2-e4 from start; black d7-d5 after 1.e4).
- Pawn diagonal capture (`exd5` on a FEN with a black pawn on d5).
- Pawn en-passant capture (white `exd6` on a FEN with black just having played d7-d5, en passant square `d6`): origin `e5` emptied, captured pawn `d5` emptied, `d6` filled.
- Knight move single origin (`Nf3` from start empties `g1`).
- Bishop move (`Bc4` on a FEN with the diagonal clear empties `f1`).
- Rook move along a clear file (`Ra2` from a FEN empties `a1`).
- Queen move along a ray.
- King move single origin (`Ke2`-type).
- Castling kingside white (`O-O` on `r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1`): `e1` emptied, `g1`=`K`, `h1` emptied, `f1`=`R`; castling becomes `['k','q']`.
- Castling queenside white (`O-O-O`): `e1` emptied, `c1`=`K`, `a1` emptied, `d1`=`R`; castling `['k','q']`.
- Castling kingside/queenside black (mirror FEN, black to move): king `g8`/`c8`, rook `f8`/`d8`; castling `['K','Q']`.
- Promotion white `e8=Q` (FEN with white pawn on e7, no piece on e8): origin `e7` emptied, `e8`=`Q`.
- Disambiguation by SAN file: `Ndb5` (mirror of the existing `position_spec` case) empties the `d`-file knight, leaves the other.
- Disambiguation by SAN rank (`R1a2`-style on a FEN with two rooks on the same file, both able to reach the target square).
- Disambiguation by discovered check (`Ne2` on the `position_spec` "discovered check" FEN) empties `g1`, leaves `c3`.
- Pawn same-file double-push disambiguation (`f4` on the `position_spec` two-pawns FEN) empties `f3`, leaves `f2`.
- Castling restrictions: moving a king (from a FEN where the king can legally step) drops `K` and `Q`; moving a rook from `a1` drops `Q`, from `h1` drops `K`; capturing a corner rook drops the matching castling right; castling drops both.
- Counters: a pawn move or capture resets `halfmove` to 0; a quiet non-pawn move increments `halfmove` by 1; black's move increments `fullmove`.
- En-passant square: white double push → `e3`; black double push → `d6`; single push → `nil`; castling → `nil`; a quiet move → `nil`.

- [ ] **Step 1: Write the failing test file `spec/move_calculator_spec.rb`.**

```ruby
require 'spec_helper'

# All tests exercise MoveCalculator *indirectly* through PGN::Position#move
# so they remain valid across an internal refactor of the calculator.
def position(fen)
  PGN::FEN.new(fen).to_position
end

describe PGN::MoveCalculator do
  describe 'pawn pushes' do
    it 'white single push from start empties e2 and fills e4' do
      nxt = PGN::Position.start.move('e4')
      expect(nxt.board.at('e2')).to be_nil
      expect(nxt.board.at('e4')).to eq('P')
    end

    it 'white double push leaves e3 empty (not just e2 cleared)' do
      nxt = PGN::Position.start.move('e4')
      expect(nxt.board.at('e3')).to be_nil
    end

    it 'black single push empties d7 and fills d5' do
      nxt = position('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1').move('d5')
      expect(nxt.board.at('d7')).to be_nil
      expect(nxt.board.at('d5')).to eq('p')
      expect(nxt.board.at('d6')).to be_nil
    end
  end

  describe 'pawn captures' do
    it 'captures diagonally onto the target square' do
      nxt = position('rnbqkbnr/3ppppp/8/8/3PP3/8/PPP2PPP/RNBQKBNR w KQkq - 0 1').move('exd5')
      expect(nxt.board.at('e4')).to be_nil
      expect(nxt.board.at('d5')).to eq('P')
    end
  end

  describe 'en passant' do
    let(:fen) { 'rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3' }

    it 'captures the pawn behind the destination' do
      nxt = position(fen).move('exd6')
      expect(nxt.board.at('e5')).to be_nil   # origin emptied
      expect(nxt.board.at('d5')).to be_nil   # captured pawn removed
      expect(nxt.board.at('d6')).to eq('P')  # landed on the en-passant square
    end
  end

  describe 'piece moves with a single origin' do
    it 'knight from g1 to f3' do
      nxt = PGN::Position.start.move('Nf3')
      expect(nxt.board.at('g1')).to be_nil
      expect(nxt.board.at('f3')).to eq('N')
    end

    it 'bishop along a clear diagonal' do
      nxt = position('rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1').move('Bc4')
      expect(nxt.board.at('f1')).to be_nil
      expect(nxt.board.at('c4')).to eq('B')
    end

    it 'rook along a clear file' do
      nxt = position('4k3/8/8/8/8/8/8/R3K3 w - - 0 1').move('Ra2')
      expect(nxt.board.at('a1')).to be_nil
      expect(nxt.board.at('a2')).to eq('R')
    end

    it 'queen along a ray' do
      nxt = position('4k3/8/8/8/8/8/8/Q3K3 w - - 0 1').move('Qa4')
      expect(nxt.board.at('a1')).to be_nil
      expect(nxt.board.at('a4')).to eq('Q')
    end

    it 'king steps one square' do
      nxt = position('4k3/8/8/8/8/8/8/4K3 w - - 0 1').move('Ke2')
      expect(nxt.board.at('e1')).to be_nil
      expect(nxt.board.at('e2')).to eq('K')
    end
  end

  describe 'castling' do
    let(:fen) { 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1' }

    it 'white kingside places king on g1 and rook on f1' do
      nxt = position(fen).move('O-O')
      expect(nxt.board.at('e1')).to be_nil
      expect(nxt.board.at('g1')).to eq('K')
      expect(nxt.board.at('h1')).to be_nil
      expect(nxt.board.at('f1')).to eq('R')
      expect(nxt.castling.sort).to eq(%w[k q])
    end

    it 'white queenside places king on c1 and rook on d1' do
      nxt = position(fen).move('O-O-O')
      expect(nxt.board.at('e1')).to be_nil
      expect(nxt.board.at('c1')).to eq('K')
      expect(nxt.board.at('a1')).to be_nil
      expect(nxt.board.at('d1')).to eq('R')
      expect(nxt.castling.sort).to eq(%w[k q])
    end

    it 'black kingside places king on g8 and rook on f8' do
      nxt = position('r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1').move('O-O')
      expect(nxt.board.at('e8')).to be_nil
      expect(nxt.board.at('g8')).to eq('k')
      expect(nxt.board.at('f8')).to eq('r')
      expect(nxt.castling.sort).to eq(%w[K Q])
    end

    it 'black queenside places king on c8 and rook on d8' do
      nxt = position('r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1').move('O-O-O')
      expect(nxt.board.at('e8')).to be_nil
      expect(nxt.board.at('c8')).to eq('k')
      expect(nxt.board.at('d8')).to eq('r')
      expect(nxt.castling.sort).to eq(%w[K Q])
    end
  end

  describe 'promotion' do
    let(:fen) { '4k3/4P3/8/8/8/8/8/4K3 w - - 0 1' }

    it 'promotes a white pawn to a queen on e8' do
      nxt = position(fen).move('e8=Q')
      expect(nxt.board.at('e7')).to be_nil
      expect(nxt.board.at('e8')).to eq('Q')
    end
  end

  describe 'disambiguation' do
    it 'resolves by SAN file (Ndb5 empties the d-file knight)' do
      nxt = position('r1bqkb1r/pp1p1ppp/2n1pn2/8/3NP3/2N5/PPP2PPP/R1BQKB1R w KQkq - 3 6').move('Ndb5')
      expect(nxt.board.at('d4')).to be_nil
      expect(nxt.board.at('c3')).to eq('N')
    end

    it 'resolves by SAN rank' do
      # Two white rooks on the a-file (a1 and a3), both can reach a2.
      # R1a2 must move the rook on rank 1.
      nxt = position('4k3/8/8/8/8/R7/8/R3K3 w - - 0 1').move('R1a2')
      expect(nxt.board.at('a1')).to be_nil
      expect(nxt.board.at('a2')).to eq('R')
      expect(nxt.board.at('a3')).to eq('R')
    end

    it 'resolves by discovered check (Ne2 empties g1, not c3)' do
      nxt = position('rnbqk2r/p1pp1ppp/1p2pn2/8/1bPP4/2N1P3/PP3PPP/R1BQKBNR w KQkq - 0 5').move('Ne2')
      expect(nxt.board.at('g1')).to be_nil
      expect(nxt.board.at('c3')).to eq('N')
    end

    it 'resolves two pawns on a file by rejecting the double push when blocked' do
      nxt = position('r2q1rk1/4bppp/p3n3/1p2n3/4N3/1B2BP2/PP3P1P/R2Q1RK1 w - - 4 19').move('f4')
      expect(nxt.board.at('f3')).to be_nil
      expect(nxt.board.at('f2')).to eq('P')
    end
  end

  describe 'castling restrictions (observable via position.castling)' do
    it 'moving the white king drops both white rights' do
      nxt = position('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1').move('Ke2')
      expect(nxt.castling.sort).to eq(%w[k q])
    end

    it 'moving the a1 rook drops queenside white' do
      nxt = position('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1').move('Ra2')
      expect(nxt.castling.sort).to eq(%w[K k q])
    end

    it 'moving the h1 rook drops kingside white' do
      nxt = position('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1').move('Rh2')
      expect(nxt.castling.sort).to eq(%w[Q k q])
    end

    it 'capturing a corner rook drops the matching right' do
      nxt = position('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1').move('Rxa8')
      expect(nxt.castling).not_to include('q')
      expect(nxt.castling).to include('k')
    end
  end

  describe 'halfmove and fullmove counters' do
    it 'a pawn move resets the halfmove clock' do
      nxt = position('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 5 3').move('e4')
      expect(nxt.halfmove).to eq(0)
    end

    it 'a quiet non-pawn move increments the halfmove clock' do
      nxt = position('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1').move('Nf6')
      expect(nxt.halfmove).to eq(1)
    end

    it 'a capture resets the halfmove clock' do
      nxt = position('rnbqkbnr/3ppppp/8/8/3PP3/8/PPP2PPP/RNBQKBNR w KQkq - 7 4').move('exd5')
      expect(nxt.halfmove).to eq(0)
    end

    it "black's move increments the fullmove counter" do
      nxt = position('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1').move('Nf6')
      expect(nxt.fullmove).to eq(2)
    end

    it "white's move does not increment the fullmove counter" do
      nxt = PGN::Position.start.move('e4')
      expect(nxt.fullmove).to eq(1)
    end
  end

  describe 'en passant square' do
    it 'is set after a white double push' do
      expect(PGN::Position.start.move('e4').en_passant).to eq('e3')
    end

    it 'is set after a black double push' do
      nxt = position('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1').move('d5')
      expect(nxt.en_passant).to eq('d6')
    end

    it 'is nil after a single push' do
      expect(PGN::Position.start.move('Nf3').en_passant).to be_nil
    end

    it 'is nil after castling' do
      expect(position('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1').move('O-O').en_passant).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run the spec, verify it passes.**

Run: `bundle exec rspec spec/move_calculator_spec.rb --format documentation`
Expected: PASS. FEN-based tests are the most likely to have a wrong expectation; if one fails, double-check the FEN coordinates (board orientation: file index 0=a, rank index 0=rank 1) and the resulting square, then fix the test.

- [ ] **Step 3: Commit.**

```bash
git add spec/move_calculator_spec.rb
git commit -m "test: exhaustive PGN::MoveCalculator characterization spec"
```

---

## Task 5: Expand `PGN::Position` spec to exhaustive coverage

**Files:**
- Modify: `spec/position_spec.rb` (add new `describe`/`context` blocks; **do not touch** the existing `should`-style examples)

**Interfaces:**
- Consumes: `PGN::Position.start`, `#move`, `#next_player`, `#to_fen`, `#board`, `#castling`, `#en_passant`, `#halfmove`, `#fullmove`, `#player`, `PLAYERS`, `CASTLING`.
- Produces: full state-transition coverage of `Position`, complementing the calculator tests at the position level.

Coverage checklist (new blocks only; existing `should` blocks stay):
- `.start` attributes: `player` `:white`, `castling` `['K','Q','k','q']`, `en_passant` `nil`, `halfmove` `0`, `fullmove` `1`.
- `#next_player` toggles white↔black.
- `#move` toggles `player` and yields a new `PGN::Position` (does not mutate the source).
- `#to_fen` round-trips the start position to `PGN::FEN::INITIAL`, and round-trips an arbitrary mid-game position through `PGN::FEN.new(...).to_position.to_fen.to_s`.
- After `1.e4`: `player` `:black`, `en_passant` `'e3'`, `halfmove` `0`, `fullmove` `1`, board `e4=P`, `e2` empty.
- After `1.e4 e5`: `player` `:white`, `en_passant` `'e6'`, `fullmove` `2`.
- Castling restriction propagation after castling (mirror the calculator castling test at the position level).

- [ ] **Step 1: Append new `expect`-style blocks to `spec/position_spec.rb`.** Keep all existing content; add at the end of the file:

```ruby

# New exhaustive coverage below. Existing `should` examples above are
# intentionally left untouched.

describe PGN::Position do
  describe '.start attributes' do
    it 'has the expected starting state' do
      pos = PGN::Position.start
      expect(pos.player).to eq(:white)
      expect(pos.castling).to eq(%w[K Q k q])
      expect(pos.en_passant).to be_nil
      expect(pos.halfmove).to eq(0)
      expect(pos.fullmove).to eq(1)
    end
  end

  describe '#next_player' do
    it 'toggles white to black and back' do
      expect(PGN::Position.start.next_player).to eq(:black)
      expect(PGN::Position.start.move('e4').next_player).to eq(:white)
    end
  end

  describe '#move' do
    it 'returns a new PGN::Position and does not mutate the source' do
      pos = PGN::Position.start
      nxt = pos.move('e4')
      expect(nxt).to be_a(PGN::Position)
      expect(nxt).not_to be(pos)
      expect(pos.board.at('e4')).to be_nil
      expect(pos.player).to eq(:white)
    end

    it 'toggles the player to move' do
      expect(PGN::Position.start.move('e4').player).to eq(:black)
      expect(PGN::Position.start.move('e4').move('e5').player).to eq(:white)
    end

    it 'updates state after 1.e4' do
      nxt = PGN::Position.start.move('e4')
      expect(nxt.en_passant).to eq('e3')
      expect(nxt.halfmove).to eq(0)
      expect(nxt.fullmove).to eq(1)
      expect(nxt.board.at('e4')).to eq('P')
      expect(nxt.board.at('e2')).to be_nil
    end

    it 'updates state after 1.e4 e5' do
      nxt = PGN::Position.start.move('e4').move('e5')
      expect(nxt.player).to eq(:white)
      expect(nxt.en_passant).to eq('e6')
      expect(nxt.fullmove).to eq(2)
    end

    it 'propagates castling restrictions' do
      fen = 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1'
      nxt = PGN::FEN.new(fen).to_position.move('O-O')
      expect(nxt.castling.sort).to eq(%w[k q])
    end
  end

  describe '#to_fen' do
    it 'round-trips the start position to FEN::INITIAL' do
      expect(PGN::Position.start.to_fen.to_s).to eq(PGN::FEN::INITIAL)
    end

    it 'round-trips an arbitrary position through FEN' do
      fen = 'r1bqkb1r/pp1p1ppp/2n1pn2/8/3NP3/2N5/PPP2PPP/R1BQKB1R w KQkq - 3 6'
      parsed = PGN::FEN.new(fen).to_position
      expect(parsed.to_fen.to_s).to eq(fen)
    end
  end
end
```

- [ ] **Step 2: Run the spec, verify it passes.**

Run: `bundle exec rspec spec/position_spec.rb --format documentation`
Expected: PASS (both old `should` examples and new `expect` examples green).

- [ ] **Step 3: Commit.**

```bash
git add spec/position_spec.rb
git commit -m "test: expand PGN::Position spec to exhaustive coverage"
```

---

## Task 6: Move/board allocation + replay profiling harness

**Files:**
- Create: `bench/profile_moves.rb`

**Interfaces:**
- Consumes: `examples/immortal_game.pgn`, `PGN.parse`, `PGN::Game#positions`, `PGN::Game#starting_position`, `PGN::Board#dup`, `memory_profiler`, `benchmark/ips`.
- Produces: a runnable script whose stdout is a human-readable report (printed by `rake bench:moves` and captured into `bench/baseline_moves.txt` in Task 8).

Metrics it reports:
1. **Total allocated objects/bytes** to replay the immortal game's 45 plies from `starting_position` (this isolates move-application cost from parse cost).
2. **`Board#dup` share**: allocations from calling `board.dup` 45 times on the start board, so we can see what fraction of (1) is the per-move copy (the flat-board optimization target).
3. **String-path `Board#at` share**: allocations from 1000 `board.at('e4')` calls (the `at(str)` optimization target).
4. **Replay throughput** (ips): fresh `PGN::Game` → `.positions` for the immortal game, excluding parse.

- [ ] **Step 1: Write `bench/profile_moves.rb`.**

```ruby
# frozen_string_literal: true
# Measures per-move allocation and replay throughput for the move pipeline.
# Run with:  bundle exec ruby bench/profile_moves.rb
# Captured baseline: bench/baseline_moves.txt (via rake bench:moves)

$LOAD_PATH.unshift(File.expand_path('lib', File.join(__dir__, '..')))
require 'pgn'
require 'memory_profiler'
require 'benchmark/ips'

EXAMPLES = File.join(__dir__, '..', 'examples')
IMMORTAL = File.read(File.join(EXAMPLES, 'immortal_game.pgn'))
GAME     = PGN.parse(IMMORTAL).freeze
SAN      = GAME.first.moves.map(&:notation).freeze
PLY      = SAN.length

puts "Workload: immortal game, #{PLY} plies"

# --- 1. Replay allocations (move application only, no parse) -----------------
replay_report = MemoryProfiler.report do
  pos = GAME.first.starting_position
  SAN.each { |m| pos = pos.move(m) }
end

puts "\n=== 1. Replay allocations (#{PLY} plies, no parse) ==="
puts "total_allocated objects: #{replay_report.total_allocated}"
puts "total_allocated bytes:   #{replay_report.total_allocated_memsize}"

# --- 2. Board#dup share (the flat-board optimization target) ------------------
dup_report = MemoryProfiler.report { PLY.times { GAME.first.starting_position.board.dup } }

puts "\n=== 2. Board#dup x#{PLY} (target of flat-board COW) ==="
puts "total_allocated objects: #{dup_report.total_allocated}"
puts "total_allocated bytes:   #{dup_report.total_allocated_memsize}"

# --- 3. Board#at(str) share (the at(str) optimization target) ---------------
start_board = GAME.first.starting_position.board
at_report = MemoryProfiler.report { 1000.times { start_board.at('e4') } }

puts "\n=== 3. Board#at(str) x1000 (target of coord-arithmetic at) ==="
puts "total_allocated objects: #{at_report.total_allocated}"
puts "total_allocated bytes:   #{at_report.total_allocated_memsize}"

# --- 4. Replay throughput (fresh game each iter to defeat memoization) ------
puts "\n=== 4. Replay throughput (ips, excluding parse) ==="
Benchmark.ips do |x|
  x.config(time: 5, warmup: 1)
  x.report('replay immortal') do
    PGN::Game.new(SAN, GAME.first.tags, GAME.first.result).positions
  end
end

puts "\nDone. Compare this file against bench/baseline_moves.txt after optimizations."
```

- [ ] **Step 2: Run the harness once and confirm it produces all four sections.**

Run: `bundle exec ruby bench/profile_moves.rb`
Expected: stdout contains the four `===` section headers and numeric lines, no exception. Allocation totals are stable across runs; ips numbers vary by machine.

- [ ] **Step 3: Commit the script (not the report — that is captured in Task 8).**

```bash
git add bench/profile_moves.rb
git commit -m "bench: add move/board allocation + replay profiling harness"
```

---

## Task 7: Parse + parse-and-replay profiling harness

**Files:**
- Create: `bench/profile_parse.rb`

**Interfaces:**
- Consumes: `examples/immortal_game.pgn`, `PGN.parse`, `PGN::Game#positions`, `memory_profiler`, `benchmark/ips`.
- Produces: a runnable script whose stdout is captured into `bench/baseline_parse.txt` in Task 8.

Metrics it reports:
1. **Corpus shape**: number of games in the synthetic corpus (the immortal game repeated `N` times, separated by a blank line).
2. **Parse-only allocations/throughput**: `PGN.parse(CORPUS)` (ips + one allocation report).
3. **Parse + replay allocations/throughput**: `PGN.parse(CORPUS).each(&:positions)` — the full real-world cost of "read a database of games and board-replay each one".

`N` is fixed at `500` so the corpus shape is deterministic and the baseline is reproducible. Capture takes a few minutes; set `BENCH_N` to reduce the size for a quick smoke run.

- [ ] **Step 1: Write `bench/profile_parse.rb`.**

```ruby
# frozen_string_literal: true
# Measures parse and parse+replay throughput/allocations on a synthetic
# multi-game corpus. Run with:  bundle exec ruby bench/profile_parse.rb
# Captured baseline: bench/baseline_parse.txt (via rake bench:parse)

$LOAD_PATH.unshift(File.expand_path('lib', File.join(__dir__, '..')))
require 'pgn'
require 'memory_profiler'
require 'benchmark/ips'

EXAMPLES = File.join(__dir__, '..', 'examples')
IMMORTAL = File.read(File.join(EXAMPLES, 'immortal_game.pgn')).strip
N        = Integer(ENV.fetch('BENCH_N', '500'))
CORPUS   = (IMMORTAL + "\n\n") * N

puts "Corpus: #{N} copies of the immortal game"

# --- 1. Parse-only allocations ------------------------------------------------
parse_report = MemoryProfiler.report { PGN.parse(CORPUS) }
puts "\n=== 1. Parse-only allocations (#{N} games) ==="
puts "total_allocated objects: #{parse_report.total_allocated}"
puts "total_allocated bytes:   #{parse_report.total_allocated_memsize}"

# --- 2. Parse + replay allocations (real-world load) --------------------------
full_report = MemoryProfiler.report { PGN.parse(CORPUS).each(&:positions) }
puts "\n=== 2. Parse + replay allocations (#{N} games) ==="
puts "total_allocated objects: #{full_report.total_allocated}"
puts "total_allocated bytes:   #{full_report.total_allocated_memsize}"

# --- 3. Parse-only throughput -------------------------------------------------
puts "\n=== 3. Parse-only throughput (ips) ==="
Benchmark.ips do |x|
  x.config(time: 5, warmup: 1)
  x.report("parse #{N} games") { PGN.parse(CORPUS) }
end

# --- 4. Parse + replay throughput ---------------------------------------------
puts "\n=== 4. Parse + replay throughput (ips) ==="
Benchmark.ips do |x|
  x.config(time: 5, warmup: 1)
  x.report("parse+replay #{N} games") { PGN.parse(CORPUS).each(&:positions) }
end

puts "\nDone. Compare this file against bench/baseline_parse.txt after optimizations."
```

- [ ] **Step 2: Run the harness once and confirm it produces all four sections.**

Run: `BENCH_N=5 bundle exec ruby bench/profile_parse.rb`
Expected: stdout contains the four `===` headers, the corpus is 5 games, no exception.

- [ ] **Step 3: Commit the script.**

```bash
git add bench/profile_parse.rb
git commit -m "bench: add parse + parse-replay profiling harness"
```

---

## Task 8: `rake bench` task, README note, and committed baseline capture

**Files:**
- Modify: `Rakefile`
- Modify: `README.md`
- Create: `bench/baseline_moves.txt`
- Create: `bench/baseline_parse.txt`

**Interfaces:**
- Produces: `rake bench` (runs both harnesses and writes both baseline files), `rake bench:moves`, `rake bench:parse`, and two committed baseline files at the current HEAD representing pre-optimization performance.

- [ ] **Step 1: Add bench tasks to `Rakefile`.** Replace the file contents with:

```ruby
require "bundler/gem_tasks"

namespace :bench do
  desc "Run move/board profiling and write bench/baseline_moves.txt"
  task :moves do
    sh "bundle exec ruby bench/profile_moves.rb > bench/baseline_moves.txt"
    puts File.read("bench/baseline_moves.txt")
  end

  desc "Run parse profiling and write bench/baseline_parse.txt"
  task :parse do
    sh "bundle exec ruby bench/profile_parse.rb > bench/baseline_parse.txt"
    puts File.read("bench/baseline_parse.txt")
  end
end

desc "Run all benchmarks and (re)write bench/baseline_*.txt"
task :bench => ["bench:moves", "bench:parse"]
```

- [ ] **Step 2: Verify the tasks are wired.**

Run: `bundle exec rake -T bench`
Expected: lists `rake bench`, `rake bench:moves`, `rake bench:parse`.

- [ ] **Step 3: Capture the committed baseline at the current HEAD.**

Run: `bundle exec rake bench`
Expected: both `bench/baseline_moves.txt` and `bench/baseline_parse.txt` are created/refreshed and printed. The parse phase may take a few minutes (500 games × ~5 s benchmark). Verify the four sections appear in each file.

- [ ] **Step 4: Add a "Benchmarks" section to `README.md`**, inserted right before the `## Installation` heading:

```markdown
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
```

- [ ] **Step 5: Commit the task, README, and baseline snapshots.**

```bash
git add Rakefile README.md bench/baseline_moves.txt bench/baseline_parse.txt
git commit -m "bench: add rake bench task, README section, and committed baseline"
```

- [ ] **Step 6: Final full-suite verification.**

Run: `bundle exec rspec`
Expected: the entire suite (all old + new specs) passes.

Run: `bundle exec rake bench`
Expected: completes without error; baseline files refreshed. On the same machine, allocation totals should match the previously committed values when no library code has changed.

---

## Self-Review

**1. Spec coverage vs. the goal.** The goal is an exhaustive regression net + a profiling baseline. Mapping each goal item to a task:
- Exhaustive `Board` coverage → Task 2. ✔
- Exhaustive `Move` coverage → Task 3. ✔
- Exhaustive `MoveCalculator` coverage → Task 4. ✔
- Exhaustive `Position` coverage → Task 5. ✔
- Allocation profiling (`Board#dup`, `at(str)`, replay) → Task 6. ✔
- Parse + parse-replay profiling → Task 7. ✔
- Reproducible `rake bench` + committed baseline → Task 8. ✔
- Each of the three proposed optimizations has a metric that will move: flat-board → Task 6 §2 (`Board#dup` allocations); king_position cache → Task 6 §1/§4 (replay allocations/ips on a game with disambiguation); at(str) → Task 6 §3. ✔

**2. Correctness fixes applied while reviewing.**
- `PGN::Board.start` returns the shared `START` constant. Tests that mutate a board now use `.dup`, preventing random-order failures caused by shared inner arrays.
- The rank-disambiguation `MoveCalculator` test now uses a legal position where both rooks can reach the target square (`R1a2` with rooks on a1 and a3).
- Replaced incorrect `MemoryProfiler` method calls (`allocated_objects`, `allocated_bytes`) with the actual API (`total_allocated`, `total_allocated_memsize`) in both profiling scripts.

**3. Placeholder scan.** No "TBD", "implement later", "add error handling", or "similar to Task N" placeholders. Every code step contains real, runnable Ruby/RSpec/Rake content. ✔

**4. Type / name consistency.**
- `PGN::Board` methods used by tests (`at`, `update`, `change!`, `coordinates_for`, `position_for`, `dup`, `inspect`, `squares`, `START`) all exist in `lib/pgn/board.rb`. ✔
- `PGN::Move` readers (`piece`, `destination`, `promotion`, `check`, `capture`, `disambiguation`, `castle`, `pawn?`, `white?`, `black?`, `check?`, `checkmate?`) all exist in `lib/pgn/move.rb`. ✔
- `PGN::Position` readers (`board`, `castling`, `en_passant`, `halfmove`, `fullmove`, `player`, `to_fen`, `move`, `next_player`, `starting_position`) exist in `lib/pgn/position.rb` / `lib/pgn/game.rb`. ✔
- `PGN::FEN::INITIAL` exists in `lib/pgn/fen.rb`. ✔
- Profiling gems: `benchmark-ips` (require `benchmark/ips`) and `memory_profiler` (require `memory_profiler`) added in Task 1, required in Tasks 6–7. ✔
- Rake task names `bench:moves` / `bench:parse` / `bench` used consistently in Task 8 and the README. ✔
- `MemoryProfiler.report` returns `total_allocated` and `total_allocated_memsize`, matching the committed baseline metrics. ✔

Note for the future optimization plan: the immortal game does not heavily exercise `disambiguate_discovered_check`. To quantify the `king_position` win specifically, the future plan should add a dedicated disambiguation-heavy benchmark fixture. This plan's `bench/profile_moves.rb` measures general replay cost (which still benefits from any king scan via the per-move path); a targeted `king_position` micro-bench is intentionally left to the optimization plan so this plan stays focused on the general baseline.
