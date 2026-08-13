# Performance / Internals (Group 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the pure-Ruby PGN/FEN hot paths faster and add an incremental position hash, with no public behavior or byte-output changes and no new dependencies.

**Architecture:** Three additive, independently-shippable changes to `lib/pgn`: (1) a `Board#fen_board_string` that serializes FEN directly from the 0x88 `@cells` array, replacing `FEN#board_string`'s round-trip through `Board#squares`; (2) a lazy `Game#each_position` enumerator that shares the replay loop with the existing eager `Game#positions`; (3) a frozen `PGN::Zobrist` module plus an incremental update helper, with `Position` storing `@zobrist`, seeding it in `#initialize`, and maintaining it in `#move`, exposing `Position#hash`/`#eql?`/`#==`.

**Tech Stack:** Ruby 3.x stdlib, RSpec, `memory_profiler` + `benchmark/ips` (already in the Gemfile development group), Racc/StringScanner (unchanged).

## Global Constraints

- Pure Ruby only; no new runtime dependencies; no C extension.
- Public output (FEN, PGN) stays byte-identical to `main`; the full spec suite (`bundle exec rspec`) stays green.
- No *new* RuboCop offenses introduced in the files you change. Some files (e.g. `lib/pgn/position.rb`, `lib/pgn/fen.rb`) already have offenses on `main`; do not increase the total offense count on those files.
- Every change is validated against `bench/baseline_*.txt`: run `bundle exec rake bench` after the final task and `git diff` the baselines; allocations must drop or stay flat, throughput must rise or stay flat.
  - Exception: maintaining the Zobrist hash adds a small per-position allocation in the replay benchmark (section 1 of `baseline_moves.txt`). That increase is an acceptable, documented trade-off for `Position#hash`.
- TDD throughout: write the failing test, run it red, implement minimally, run it green, then commit.
- Commit messages follow the existing `type(scope): summary` convention (e.g. `perf(fen): ...`).

## File Structure

- `lib/pgn/board.rb` — add `#fen_board_string` (reads `@cells` directly in FEN order). Public `#squares` unchanged.
- `lib/pgn/fen.rb` — rewrite `FEN#board_string` to delegate to `board.fen_board_string`; delete the `squares.transpose.reverse` + run-length code.
- `lib/pgn/game.rb` — add `#each_position` (enumerator/yield); refactor `#positions` to reuse it.
- `lib/pgn/zobrist.rb` — new file: frozen `Zobrist` table constants, a `seed(...)` helper used by `Position#initialize`, and an `update(...)` helper used by `Position#move` to keep the hash incrementally correct.
- `lib/pgn.rb` — `require 'pgn/zobrist'` immediately before `require 'pgn/position'`.
- `lib/pgn/position.rb` — store `@zobrist`; seed it in `#initialize`; maintain it in `#move`; add `#hash`, `#eql?`, `#==`.
- `spec/fen_spec.rb`, `spec/board_spec.rb`, `spec/game_spec.rb`, `spec/position_spec.rb`, `spec/zobrist_spec.rb` (new) — tests.
- `bench/profile_moves.rb` — add a FEN-generation allocation/throughput section and a "last position only" lazy-vs-eager section.

---

## Task 1: Direct 0x88 FEN board-string builder

**Files:**
- Modify: `lib/pgn/board.rb` (add `#fen_board_string` after `#square_name`)
- Modify: `lib/pgn/fen.rb` (`#board_string`)
- Test: `spec/board_spec.rb`, `spec/fen_spec.rb`

**Interfaces:**
- Consumes: `Board#@cells` (128-cell 0x88 array, index `rank*16+file`).
- Produces: `PGN::Board#fen_board_string` → `String`, e.g. `"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"`. Byte-identical to the current `PGN::FEN#board_string`.

- [ ] **Step 1: Write the failing test in `spec/board_spec.rb`**

Add inside the existing `describe PGN::Board do` block, after the `#dup` examples:

```ruby
  describe '#fen_board_string' do
    it 'serializes the start position to the FEN board string' do
      expect(PGN::Board.start.fen_board_string)
        .to eq('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR')
    end

    it 'collapses runs of empty squares into digits' do
      board = PGN::FEN.new('8/8/8/8/8/8/8/8 w - - 0 1').board
      expect(board.fen_board_string).to eq('8/8/8/8/8/8/8/8')
    end

    it 'serializes a mid-game board byte-for-byte like FEN#board_string' do
      fen = 'r1bqkb1r/pp1p1ppp/2n1pn2/8/3NP3/2N5/PPP2PPP/R1BQKB1R w KQkq - 3 6'
      board = PGN::FEN.new(fen).board
      expect(board.fen_board_string).to eq(fen.split.first)
    end

    it 'serializes rank 8 first and rank 1 last (FEN order)' do
      board = PGN::FEN.new('4k3/8/8/8/8/8/8/4K3 w - - 0 1').board
      expect(board.fen_board_string).to eq('4k3/8/8/8/8/8/8/4K3')
    end
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/board_spec.rb -e 'fen_board_string'`
Expected: FAIL with `NoMethodError` for `PGN::Board#fen_board_string`.

- [ ] **Step 3: Implement `Board#fen_board_string` in `lib/pgn/board.rb`**

Add this method immediately after `#square_name` (before `private`):

```ruby
    # Serializes the board to the FEN board-string portion (ranks 8→1,
    # files a→h, runs of empty squares collapsed to a digit) by walking
    # the 0x88 `@cells` array directly. This avoids rebuilding the 8x8
    # `squares` array on every FEN generation.
    #
    # @return [String] e.g. "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"
    def fen_board_string
      rows = []
      7.downto(0) do |rank|
        s = String.new
        run = 0
        0.upto(7) do |file|
          piece = @cells[(rank * 16) + file]
          if piece.nil?
            run += 1
          else
            s << run.to_s if run.positive?
            run = 0
            s << piece
          end
        end
        s << run.to_s if run.positive?
        rows << s
      end
      rows.join('/')
    end
```

- [ ] **Step 4: Run the board spec to verify it passes**

Run: `bundle exec rspec spec/board_spec.rb -e 'fen_board_string'`
Expected: PASS (4 examples).

- [ ] **Step 5: Rewrite `FEN#board_string` to delegate**

In `lib/pgn/fen.rb`, replace the body of `board_string`:

```ruby
    def board_string
      board.fen_board_string
    end
```

- [ ] **Step 6: Run the full FEN + board suites**

Run: `bundle exec rspec spec/fen_spec.rb spec/board_spec.rb`
Expected: PASS (all green; the `board_string round-trip` examples confirm byte-identical output).

- [ ] **Step 7: Run RuboCop on the touched files**

Run: `bundle exec rubocop lib/pgn/board.rb lib/pgn/fen.rb spec/board_spec.rb`
Expected: no *new* offenses (fix any your edit introduced before continuing).

- [ ] **Step 8: Commit**

```bash
git add lib/pgn/board.rb lib/pgn/fen.rb spec/board_spec.rb
git commit -m "perf(fen): serialize FEN board string directly from 0x88 cells"
```

---

## Task 2: FEN-generation benchmark section

**Files:**
- Modify: `bench/profile_moves.rb`

**Interfaces:**
- Consumes: `PGN::Game#positions` (unchanged), `PGN::Position#to_fen`.
- Produces: a new printed section `=== 5. FEN generation ...` in `bench/baseline_moves.txt`.

- [ ] **Step 1: Add the FEN benchmark section to `bench/profile_moves.rb`**

Append, before the final `puts "Done..."` line:

```ruby
# --- 5. FEN generation (target of the direct-0x88 FEN builder) -------------
positions = GAME.first.positions

fen_report = MemoryProfiler.report do
  positions.each { |p| p.to_fen.to_s }
end

puts "\n=== 5. FEN generation x#{positions.length} (target of direct-0x88 FEN) ==="
puts "total_allocated objects: #{fen_report.total_allocated}"
puts "total_allocated bytes:   #{fen_report.total_allocated_memsize}"

puts "\n=== 6. FEN throughput (ips) ==="
Benchmark.ips do |x|
  x.config(time: 5, warmup: 1)
  x.report('fen immortal') do
    positions.each { |p| p.to_fen.to_s }
  end
end
```

- [ ] **Step 2: Run the moves benchmark and record the new baseline**

Run: `bundle exec rake bench:moves`
Expected: prints sections 1–6, writes `bench/baseline_moves.txt`.

- [ ] **Step 3: Inspect the diff vs. the old baseline**

Run: `git diff bench/baseline_moves.txt`
Expected: the previous sections 1–4 are unchanged (within benchmark-ips variance), and new sections 5–6 are present. The FEN allocation count is the committed baseline for this section (future regressions are measured against it).

- [ ] **Step 4: Commit**

```bash
git add bench/profile_moves.rb bench/baseline_moves.txt
git commit -m "bench: add FEN-generation allocation/throughput section"
```

---

## Task 3: Lazy `Game#each_position`

**Files:**
- Modify: `lib/pgn/game.rb` (`#positions`, add `#each_position`)
- Test: `spec/game_spec.rb`

**Interfaces:**
- Consumes: `PGN::Game#starting_position` (unchanged), `PGN::Position#move` (unchanged).
- Produces: `PGN::Game#each_position` (with a block: yields each `PGN::Position` in order, returns `self`; without a block: returns an `Enumerator` yielding positions). `PGN::Game#positions` still returns an `Array` (memoized), now defined as `each_position.to_a`.

- [ ] **Step 1: Write the failing test in `spec/game_spec.rb`**

Add a new `describe '#each_position'` block after the existing `describe '#positions'` block:

```ruby
  describe '#each_position' do
    it 'yields each position in order when given a block' do
      game = PGN::Game.new(%w[e4 e5])
      expect { |b| game.each_position(&b) }.to yield_successive_args(
        PGN::Position.start, game.positions[1], game.positions[2]
      )
    end

    it 'returns an Enumerator when no block is given' do
      game = PGN::Game.new(%w[e4 e5])
      expect(game.each_position).to be_an(Enumerator)
    end

    it 'produces the same positions as #positions' do
      game = PGN::Game.new(%w[e4 c5 Nf3])
      expect(game.each_position.to_a).to eq(game.positions)
    end

    it 'does not materialize the full array when only the last is needed' do
      moves = %w[e4 c5 Nf3 d6]
      game  = PGN::Game.new(moves)
      last = nil
      game.each_position { |p| last = p }
      expect(last).to eq(game.positions.last)
    end
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/game_spec.rb -e 'each_position'`
Expected: FAIL with `NoMethodError` for `PGN::Game#each_position`.

- [ ] **Step 3: Implement `#each_position` and refactor `#positions` in `lib/pgn/game.rb`**

Replace the existing `positions` method (the `@positions ||= begin ... end` block) with:

```ruby
    # @return [Enumerator, self] with a block: yields each {PGN::Position}
    #   in order (starting position, then one per move) and returns self.
    #   Without a block: returns an Enumerator that yields the same.
    #
    # The replay loop is shared with {#positions} so eager and lazy paths
    # produce identical position objects in identical order.
    def each_position
      return enum_for(:each_position) unless block_given?

      position = starting_position
      yield position
      moves.each do |move|
        position = position.move(move.notation)
        yield position
      end
      self
    end

    # @return [Array<PGN::Position>] list of the {PGN::Position}s in the game
    #
    def positions
      @positions ||= each_position.to_a
    end
```

- [ ] **Step 4: Run the game spec to verify it passes**

Run: `bundle exec rspec spec/game_spec.rb`
Expected: PASS (both `#positions` and `#each_position` examples green).

- [ ] **Step 5: Run the full suite to confirm no regression**

Run: `bundle exec rspec`
Expected: PASS (all examples green).

- [ ] **Step 6: Run RuboCop**

Run: `bundle exec rubocop lib/pgn/game.rb spec/game_spec.rb`
Expected: no *new* offenses.

- [ ] **Step 7: Commit**

```bash
git add lib/pgn/game.rb spec/game_spec.rb
git commit -m "perf(game): add lazy each_position enumerator, share replay loop"
```

---

## Task 4: Lazy-vs-eager benchmark section

**Files:**
- Modify: `bench/profile_moves.rb`

**Interfaces:**
- Consumes: `PGN::Game#each_position` (from Task 3), `PGN::Game#positions`.
- Produces: a new printed section `=== 7. Last-position-only ...` comparing lazy and eager allocation.

- [ ] **Step 1: Add the lazy-vs-eager section to `bench/profile_moves.rb`**

Append, before the final `puts "Done..."` line:

```ruby
# --- 7. Last-position-only: lazy each_position vs eager positions ---------
lazy_report = MemoryProfiler.report do
  last = nil
  GAME.first.each_position { |p| last = p }
  last
end

eager_report = MemoryProfiler.report do
  GAME.first.positions.last
end

puts "\n=== 7. Last-position-only (#{PLY} plies): lazy vs eager ==="
puts "lazy  total_allocated objects: #{lazy_report.total_allocated}"
puts "lazy  total_allocated bytes:   #{lazy_report.total_allocated_memsize}"
puts "eager total_allocated objects: #{eager_report.total_allocated}"
puts "eager total_allocated bytes:   #{eager_report.total_allocated_memsize}"
```

- [ ] **Step 2: Run the moves benchmark**

Run: `bundle exec rake bench:moves`
Expected: section 7 prints; `lazy` allocates far fewer objects than `eager` (the eager path materializes and retains all `PLY+1` positions; the lazy path only keeps the current one).

- [ ] **Step 3: Commit**

```bash
git add bench/profile_moves.rb bench/baseline_moves.txt
git commit -m "bench: add lazy-vs-eager last-position-only section"
```

---

## Task 5: Zobrist table + seeding helper

**Files:**
- Create: `lib/pgn/zobrist.rb`
- Modify: `lib/pgn.rb` (require it)
- Test: `spec/zobrist_spec.rb`

**Interfaces:**
- Consumes: `PGN::Board#at_index` (unchanged).
- Produces: `PGN::Zobrist` module with:
  - `Zobrist.table` → `Hash<String, Array<Integer>>` mapping each piece char to a 128-element array of 64-bit random Integers (index by 0x88 index).
  - `Zobrist.side` → `Integer` (side-to-move XOR).
  - `Zobrist.castling` → `Hash<String, Integer>` for `'K','Q','k','q'`.
  - `Zobrist.ep_file` → `Array<Integer>` (8 entries, index by file 0..7).
  - `Zobrist.seed(board, player, castling, en_passant)` → `Integer`.
  - `Zobrist.update(position, move, calculator, new_board, new_castling, new_ep)` → `Integer` (used by Task 7).

- [ ] **Step 1: Write the failing test `spec/zobrist_spec.rb`**

```ruby
require 'spec_helper'

describe PGN::Zobrist do
  it 'exposes table, side, castling, and ep_file constants' do
    expect(PGN::Zobrist.table).to be_a(Hash)
    expect(PGN::Zobrist.table.keys.sort).to eq(%w[B K N P Q R b k n p q r].sort)
    expect(PGN::Zobrist.table['P'].length).to eq(128)
    expect(PGN::Zobrist.side).to be_an(Integer)
    expect(PGN::Zobrist.castling).to be_a(Hash)
    expect(PGN::Zobrist.castling.keys.sort).to eq(%w[K Q k q].sort)
    expect(PGN::Zobrist.ep_file.length).to eq(8)
  end

  it 'seeds the starting position to a stable integer' do
    first  = PGN::Zobrist.seed(PGN::Board.start, :white, %w[K Q k q], nil)
    second = PGN::Zobrist.seed(PGN::Board.start, :white, %w[K Q k q], nil)
    expect(first).to eq(second)
    expect(first).to be_an(Integer)
  end

  it 'differs when the side to move changes' do
    white_to_move = PGN::Zobrist.seed(PGN::Board.start, :white, %w[K Q k q], nil)
    black_to_move = PGN::Zobrist.seed(PGN::Board.start, :black, %w[K Q k q], nil)
    expect(white_to_move).not_to eq(black_to_move)
  end

  it 'differs when castling rights change' do
    full = PGN::Zobrist.seed(PGN::Board.start, :white, %w[K Q k q], nil)
    no_k = PGN::Zobrist.seed(PGN::Board.start, :white, %w[Q k q], nil)
    expect(full).not_to eq(no_k)
  end

  it 'differs when an en-passant file is present vs absent' do
    with_ep = PGN::Zobrist.seed(PGN::Board.start, :white, %w[K Q k q], 'e3')
    no_ep   = PGN::Zobrist.seed(PGN::Board.start, :white, %w[K Q k q], nil)
    expect(with_ep).not_to eq(no_ep)
  end

  it 'is deterministic across processes (frozen constants)' do
    expect(PGN::Zobrist.table).to be_frozen
    expect(PGN::Zobrist.castling).to be_frozen
    expect(PGN::Zobrist.ep_file).to be_frozen
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/zobrist_spec.rb`
Expected: FAIL with `NameError` for `PGN::Zobrist`.

- [ ] **Step 3: Create `lib/pgn/zobrist.rb`**

```ruby
# frozen_string_literal: true

module PGN
  # Zobrist hashing keys for incremental position hashing. All keys are
  # fixed 64-bit pseudo-random Integers generated once at load time from a
  # frozen seed so hashes are stable for the life of the process.
  #
  # Indexing is by 0x88 square index (0..127); off-board indices are
  # allocated but never read.
  module Zobrist
    SEED = 0x1234_5678_9abc_def1

    # Deterministic pseudo-random generator so hashes are stable per
    # process and across machines (no Kernel#rand).
    def self.gen
      @gen ||= Random.new(SEED)
    end
    private_class_method :gen

    def self.rand64
      gen.rand(1 << 64)
    end
    private_class_method :rand64

    PIECES = %w[P N B R Q K p n b r q k].freeze

    table = {}
    PIECES.each do |piece|
      table[piece] = Array.new(128) { rand64 }
    end
    TABLE = table.freeze

    SIDE = rand64
    CASTLING = { 'K' => rand64, 'Q' => rand64, 'k' => rand64, 'q' => rand64 }.freeze
    EP_FILE = Array.new(8) { rand64 }.freeze

    # @param board [PGN::Board]
    # @param player [Symbol] :white or :black
    # @param castling [Array<String>] e.g. %w[K Q k q]
    # @param en_passant [String, nil] e.g. "e3" or nil
    # @return [Integer] the Zobrist hash of the position
    def self.seed(board, player, castling, en_passant)
      h = 0
      0.upto(7) do |rank|
        0.upto(7) do |file|
          idx = (rank * 16) + file
          piece = board.at_index(idx)
          h ^= TABLE[piece][idx] if piece
        end
      end
      h ^= SIDE if player == :black
      castling.to_a.each { |right| h ^= CASTLING[right] if CASTLING.key?(right) }
      h ^= EP_FILE[en_passant.getbyte(0) - 97] if en_passant && !en_passant.empty?
      h
    end
  end
end
```

- [ ] **Step 4: Require it from `lib/pgn.rb`**

Add `require 'pgn/zobrist'` immediately before `require 'pgn/position'`:

```ruby
require 'pgn/move_calculator'
require 'pgn/zobrist'
require 'pgn/position'
```

- [ ] **Step 5: Run the Zobrist spec**

Run: `bundle exec rspec spec/zobrist_spec.rb`
Expected: PASS (6 examples).

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS (loading the new file must not break anything).

- [ ] **Step 7: Run RuboCop**

Run: `bundle exec rubocop lib/pgn/zobrist.rb spec/zobrist_spec.rb lib/pgn.rb`
Expected: no *new* offenses.

- [ ] **Step 8: Commit**

```bash
git add lib/pgn/zobrist.rb lib/pgn.rb spec/zobrist_spec.rb
git commit -m "feat(zobrist): add deterministic Zobrist key table and seed helper"
```

---

## Task 6: Incremental hash on `Position` + equality

**Files:**
- Modify: `lib/pgn/position.rb`
- Test: `spec/position_spec.rb`

**Interfaces:**
- Consumes: `PGN::Zobrist.seed`, `PGN::Zobrist::SIDE`, `PGN::Zobrist::CASTLING`, `PGN::Zobrist::EP_FILE`.
- Produces:
  - `PGN::Position#zobrist` → `Integer` (the current hash).
  - `PGN::Position#hash` → `Integer`.
  - `PGN::Position#eql?`/`#==` → `Boolean`, comparing board cells, player, castling and en_passant (ignoring halfmove/fullmove, matching repetition semantics).

- [ ] **Step 1: Write the failing test in `spec/position_spec.rb`**

Merge the following block into the **second** existing outer `describe PGN::Position do` block (the one with `.start attributes`, `#next_player`, etc.):

```ruby
  describe '#zobrist and equality' do
    it 'seeds the start position with a stable hash' do
      expect(PGN::Position.start.zobrist).to be_an(Integer)
      expect(PGN::Position.start.zobrist).to eq(PGN::Position.start.zobrist)
    end

    it 'updates the hash after a move (and matches a fresh seed)' do
      start = PGN::Position.start
      after = start.move('e4')
      expect(after.zobrist).to eq(
        PGN::Zobrist.seed(after.board, after.player, after.castling, after.en_passant)
      )
    end

    it 'is equal to an independently built equivalent position' do
      a = PGN::Position.start.move('e4').move('e5')
      b = PGN::Position.start.move('e4').move('e5')
      expect(a).to eq(b)
      expect(a.hash).to eq(b.hash)
    end

    it 'is not equal when only the side to move differs' do
      a = PGN::Position.start
      b = PGN::Position.start.move('e4')
      expect(a).not_to eq(b)
    end

    it 'is not equal when castling rights differ' do
      fen = 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1'
      a = PGN::FEN.new(fen).to_position
      b = a.move('O-O')
      expect(a).not_to eq(b)
    end

    it 'ignores halfmove and fullmove counters for equality' do
      a = PGN::Position.new(PGN::Board.start, :white, %w[K Q k q], nil, 0, 1)
      b = PGN::Position.new(PGN::Board.start, :white, %w[K Q k q], nil, 7, 9)
      expect(a).to eq(b)
      expect(a.hash).to eq(b.hash)
    end

    it 'keeps the replay hash in sync with a fresh seed for a whole game' do
      moves = %w[e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be2 e6]
      pos = PGN::Position.start
      moves.each do |m|
        pos = pos.move(m)
        expect(pos.zobrist).to eq(
          PGN::Zobrist.seed(pos.board, pos.player, pos.castling, pos.en_passant)
        ), "drift after #{m}"
      end
    end
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/position_spec.rb -e 'zobrist'`
Expected: FAIL with `NoMethodError` for `PGN::Position#zobrist`.

- [ ] **Step 3: Implement incremental hash and equality in `lib/pgn/position.rb`**

a) Group the existing `attr_accessor` lines and add `attr_reader :zobrist`:

```ruby
    attr_accessor :board, :player, :castling, :en_passant, :halfmove, :fullmove
    attr_reader :zobrist
```

b) Update `#initialize` to accept an optional `zobrist:` keyword (this lets `#move` supply a precomputed value and avoids double-seeding):

```ruby
    def initialize(board, player, castling = CASTLING, en_passant = nil,
                   halfmove = 0, fullmove = 1, zobrist: nil)
      self.board      = board
      self.player     = player
      self.castling   = castling
      self.en_passant = en_passant
      self.halfmove   = halfmove
      self.fullmove   = fullmove
      @zobrist = zobrist || Zobrist.seed(board, player, castling, en_passant)
    end
```

c) Refactor `#move` to be compact and pass the new zobrist into the constructor:

```ruby
    def move(str)
      move       = PGN::Move.new(str, player)
      calculator = PGN::MoveCalculator.new(board, move)

      restrictions = calculator.castling_restrictions
      new_castling = restrictions.empty? ? castling : castling - restrictions
      new_halfmove = calculator.increment_halfmove? ? halfmove + 1 : 0
      new_fullmove = calculator.increment_fullmove? ? fullmove + 1 : fullmove
      no_move      = str == '--'

      new_board  = no_move ? board : calculator.result_board
      new_player = next_player
      new_ep     = calculator.en_passant_square

      new_zobrist = incremental_zobrist(move, calculator, new_board, new_castling, new_ep)

      PGN::Position.new(
        new_board, new_player, new_castling, new_ep, new_halfmove, new_fullmove,
        zobrist: new_zobrist
      )
    end
```

d) Add a private fallback helper (Task 7 turns this into a true incremental update):

```ruby
    private

    # First cut: re-seed from scratch. Correct, and the "keeps the replay
    # hash in sync" spec pins correctness. Task 7 replaces this with the
    # incremental XOR-diff path.
    def incremental_zobrist(_move, _calculator, new_board, new_castling, new_ep)
      Zobrist.seed(new_board, next_player, new_castling, new_ep)
    end
```

e) Add equality at the end of the class (just before the final `end`):

```ruby
    # Positions are equal when their board, side to move, castling rights,
    # and en-passant square match. Halfmove/fullmove counters are ignored
    # (matching threefold-repetition semantics).
    def eql?(other)
      other.is_a?(PGN::Position) &&
        player == other.player &&
        castling == other.castling &&
        en_passant == other.en_passant &&
        board_equal?(other.board)
    end

    alias == eql?

    def hash
      zobrist
    end

    private

    def board_equal?(other_board)
      0.upto(127).all? { |idx| board.at_index(idx) == other_board.at_index(idx) }
    end
```

**Note:** `Position#initialize` already triggers `Metrics/ParameterLists` on `main`. Adding the `zobrist:` keyword keeps the same cop violation lines (optional count and total count still exceed the default thresholds), so no *additional* offense is introduced.

- [ ] **Step 4: Run the position spec**

Run: `bundle exec rspec spec/position_spec.rb -e 'zobrist'`
Expected: PASS (all 7 examples; the `keeps the replay hash in sync` spec confirms the hash matches a fresh seed after every move).

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS (no regression; `Position#==`/`#hash` are new and only consumed by the new specs in this pass).

- [ ] **Step 6: Run RuboCop**

Run: `bundle exec rubocop lib/pgn/position.rb spec/position_spec.rb`
Expected: no *new* offenses introduced by your edits (the existing `Metrics/ParameterLists`, `Style/AccessorGrouping`, etc. on `lib/pgn/position.rb` should remain unchanged in count).

- [ ] **Step 7: Commit**

```bash
git add lib/pgn/position.rb spec/position_spec.rb
git commit -m "feat(position): Zobrist hash + equality, seeded incrementally through constructor"
```

---

## Task 7: Make the hash truly incremental on the move hot path

**Files:**
- Modify: `lib/pgn/zobrist.rb` (add `Zobrist.update` + private helpers)
- Modify: `lib/pgn/position.rb` (replace the fallback `incremental_zobrist` body)
- Test: `spec/position_spec.rb` (existing sync spec is the correctness gate)

**Interfaces:**
- Consumes: `PGN::Zobrist::TABLE`, `Zobrist::SIDE`, `Zobrist::CASTLING`, `Zobrist::EP_FILE`; `PGN::MoveCalculator::CASTLING`; `PGN::MoveCalculator` private helpers accessed via `send`/`instance_variable_get`.
- Produces: `Position#move` no longer rescans the whole board; it XORs only the squares that changed.

- [ ] **Step 1: Confirm the correctness gate is already in place**

The existing `keeps the replay hash in sync with a fresh seed for a whole game` spec (Task 6) is the regression gate: the incremental hash must equal a fresh seed after every move. No new test is needed for correctness; this task only changes *how* the hash is computed.

- [ ] **Step 2: Add the incremental update helper to `lib/pgn/zobrist.rb`**

Append to `PGN::Zobrist`, before the final `end`:

```ruby
    # Derive the hash for the position after a move by XOR-ing only the
    # state that changed: side to move, removed castling rights, the old/new
    # en-passant file, and the piece(s) on every touched square.
    #
    # @param position [PGN::Position] the pre-move position
    # @param move [PGN::Move]
    # @param calculator [PGN::MoveCalculator]
    # @param new_board [PGN::Board]
    # @param new_castling [Array<String>]
    # @param new_ep [String, nil]
    # @return [Integer]
    def self.update(position, move, calculator, new_board, new_castling, new_ep)
      h = position.zobrist ^ SIDE

      (position.castling - new_castling).each do |right|
        h ^= CASTLING[right] if CASTLING.key?(right)
      end

      h ^= ep_file_key(position.en_passant)
      h ^= ep_file_key(new_ep)

      each_changed_index(move, calculator) do |idx|
        h ^= piece_key(position.board.at_index(idx), idx)
        h ^= piece_key(new_board.at_index(idx), idx)
      end

      h
    end

    def self.ep_file_key(ep)
      return 0 if ep.nil? || ep.empty?

      EP_FILE[ep.getbyte(0) - 97]
    end
    private_class_method :ep_file_key

    def self.piece_key(piece, idx)
      return 0 if piece.nil?

      TABLE[piece][idx]
    end
    private_class_method :piece_key

    # Yields each 0x88 index whose piece may have changed during the move.
    # For castling this comes from MoveCalculator::CASTLING; for normal
    # moves it is origin, destination, and the en-passant-captured pawn.
    def self.each_changed_index(move, calculator)
      if move.castle
        MoveCalculator::CASTLING[move.castle].each_key { |idx| yield idx }
      else
        origin = calculator.instance_variable_get(:@origin_idx)
        yield origin if origin
        yield calculator.send(:dest_idx)
        if (ep = calculator.send(:en_passant_capture))
          yield ep
        end
      end
    end
    private_class_method :each_changed_index
```

- [ ] **Step 3: Replace the fallback helper in `lib/pgn/position.rb`**

Change the private `incremental_zobrist` method in `Position` to delegate to `Zobrist.update`:

```ruby
    private

    def incremental_zobrist(move, calculator, new_board, new_castling, new_ep)
      Zobrist.update(self, move, calculator, new_board, new_castling, new_ep)
    end
```

- [ ] **Step 4: Run the position spec**

Run: `bundle exec rspec spec/position_spec.rb -e 'zobrist'`
Expected: PASS — the `keeps the replay hash in sync` spec must still pass, proving the incremental hash equals a fresh seed after every move (including captures, promotions, en passant, and castling).

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS.

- [ ] **Step 6: Run RuboCop**

Run: `bundle exec rubocop lib/pgn/position.rb lib/pgn/zobrist.rb`
Expected: no *new* offenses.

- [ ] **Step 7: Commit**

```bash
git add lib/pgn/position.rb lib/pgn/zobrist.rb
git commit -m "perf(position): compute Zobrist hash incrementally per move"
```

---

## Task 8: Final verification + baseline update

**Files:**
- Read-only: `bench/baseline_moves.txt`, `bench/baseline_parse.txt`

- [ ] **Step 1: Run the full spec suite**

Run: `bundle exec rspec`
Expected: PASS, same count as `main` plus the new examples (no failures).

- [ ] **Step 2: Run RuboCop across the changed files**

Run: `bundle exec rubocop lib/pgn/board.rb lib/pgn/fen.rb lib/pgn/game.rb lib/pgn/position.rb lib/pgn/zobrist.rb spec/board_spec.rb spec/game_spec.rb spec/position_spec.rb spec/zobrist_spec.rb`
Expected: no *new* offenses on the files you touched. Existing offenses in `fen.rb` / `position.rb` should not increase in count.

- [ ] **Step 3: Regenerate the bench baselines**

Run: `bundle exec rake bench`
Expected: writes `bench/baseline_moves.txt` (now includes sections 5–7) and `bench/baseline_parse.txt`.

- [ ] **Step 4: Diff the baselines vs. the pre-branch state**

Run: `git diff $(git merge-base main HEAD) bench/baseline_moves.txt bench/baseline_parse.txt`
Expected:
- Sections 1–4 of `baseline_moves.txt` flat or improved (within benchmark-ips variance).
- Section 1 (replay) may show a modest allocation increase because every `Position` now carries `@zobrist`; this is the documented trade-off for `Position#hash`.
- New sections 5–7 present, with FEN allocations lower than the implicit pre-change cost and `lazy` allocating far fewer objects than `eager` in section 7.
- `baseline_parse.txt` flat (this pass does not touch the parser).

- [ ] **Step 5: Commit the baselines**

```bash
git add bench/baseline_moves.txt
git commit -m "bench: refresh baselines after perf/internals pass"
```

- [ ] **Step 6: Summarize results**

Update `CHANGELOG.md` (Unreleased section) with a short bullet summarizing the three changes and the measured allocation/throughput deltas, matching the existing CHANGELOG style. Commit:

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): note perf/internals pass"
```

---

## Self-Review

**Spec coverage:**
- Direct 0x88 FEN builder → Task 1 (board spec) + existing `board_string round-trip` fen spec.
- FEN benchmark → Task 2.
- Lazy `each_position` → Task 3 (game spec) + Task 4 (bench).
- Zobrist table + seed → Task 5 (zobrist spec).
- Incremental hash + equality → Task 6 (position spec); true incremental in Task 7 (sync spec is the gate).
- Final verification → Task 8.

**Placeholder scan:** No `TBD`/`TODO`/`fill in details`. Task 7 explicitly derives castling changed squares from the existing `MoveCalculator::CASTLING` table, so there is no hand-rolled castling square math to verify.

**Type consistency:** `Board#fen_board_string`, `Game#each_position`, `Zobrist.seed`/`Zobrist.update`, `Position#zobrist`/`#hash`/`#eql?`/`#==`, and the `zobrist:` keyword in `Position#initialize` are named consistently across tasks and match the design doc.
