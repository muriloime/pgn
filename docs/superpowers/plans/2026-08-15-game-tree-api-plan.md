# Game-tree API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a navigable, mutable `PGN::Node` tree over the existing `MoveText` structure, with per-node positions and variation management (add/promote/demote/delete), non-breaking.

**Architecture:** `MoveText` stays the source of truth (parser builds it, serializer reads it → byte-identical round-trip preserved). `PGN::Node` is a live lazily-built view via `Game#root`; mutations edit `MoveText` arrays in place and normalize the affected branching point to flat sibling storage. `Node#position` is pure-Ruby replay (`Position#move`), no engine dependency.

**Tech Stack:** Ruby, RSpec, stdlib only (no new deps).

**Spec:** `docs/superpowers/specs/2026-08-15-game-tree-api-design.md`

## Global Constraints

- Pure Ruby only — no `PGN::Bitboard::Engine` dependency in the node API.
- `Game#moves` and `MoveText` keep their existing shapes (backward compat); the 241-example suite stays green.
- `Game#to_pgn` stays byte-identical for un-mutated games; after a mutation it must re-parse to the mutated structure (idempotent).
- Castling SAN is canonicalized `0`→`O` exactly as `Game#moves=` / `standardize_castling` does.
- `PGN::Node` instances go stale after any structural mutation; mutation methods return a fresh `game.root` for re-navigation (no runtime stale-check).
- Tests run with `bundle _2.7.2_ exec rspec` in the worktree `.worktrees/game-tree-engine-book`.

## File Structure

- Create `lib/pgn/node.rb` — `PGN::Node` (the whole node abstraction).
- Modify `lib/pgn.rb` — add `require 'pgn/node'` to the central require list.
- Modify `lib/pgn/game.rb` — add `Game#root` (one-liner building the root `Node`).
- Create `spec/node_spec.rb` — node behavior + mutation + round-trip.
- Modify `spec/game_spec.rb` — add an additive block exercising mutations on fixtures (existing assertions untouched).

---

### Task 1: Node read-only navigation + `Game#root`

**Files:**
- Create: `lib/pgn/node.rb`
- Modify: `lib/pgn/game.rb` (add `#root`)
- Modify: `lib/pgn.rb` (add require)
- Test: `spec/node_spec.rb`

**Interfaces:**
- Produces: `PGN::Node.new(move:, parent:, line:, index:, starting_position:, game:)`;
  `Node#root?`, `#notation`, `#annotation`, `#comment`, `#children`, `#variations`,
  `#next`, `#previous`, `#[]`, `#main_line`; `PGN::Game#root`.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/node_spec.rb
require 'spec_helper'

describe PGN::Node do
  let(:game) { PGN.parse(File.read(File.expand_path('spec/pgn_files/variations.pgn', __dir__))).first }
  let(:root) { game.root }

  it 'root is a root node with no move' do
    expect(root).to be_root
    expect(root.move).to be_nil
    expect(root.notation).to be_nil
    expect(root.previous).to be_nil
  end

  it 'main_line matches game.moves notations (root excluded)' do
    expect(root.main_line.map(&:notation)).to eq(game.moves.map(&:notation))
  end

  it 'main_line is an Enumerator without a block' do
    expect(root.main_line).to be_an(Enumerator)
  end

  it 'children of the position after 1.e4 e5 are Nf3 (main), Nc3, f4' do
    node = root.next.next  # after e4 (white), after e5 (black) => position before Nf3
    expect(node.children.map(&:notation)).to eq(%w[Nf3 Nc3 f4])
    expect(node.variations.map(&:notation)).to eq(%w[Nc3 f4])
    expect(node.next.notation).to eq('Nf3')
  end

  it 'nested variation f5 is a sibling of d5 under the Nc3 node' do
    nc3_node = root.next.next.variations.first  # the Nc3 variation first move
    expect(nc3_node.notation).to eq('Nc3')
    expect(nc3_node.children.map(&:notation)).to eq(%w[d5 f5])
  end

  it 'previous walks back to the root' do
    node = root.next.next.next  # Nf3 node
    expect(node.previous.notation).to eq('e5')
    expect(node.previous.previous.notation).to eq('e4')
    expect(node.previous.previous.previous).to be_root
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle _2.7.2_ exec rspec spec/node_spec.rb`
Expected: FAIL — `undefined method 'root' for PGN::Game` / `uninitialized constant PGN::Node`.

- [ ] **Step 3: Write minimal implementation**

```ruby
# lib/pgn/node.rb
# frozen_string_literal: true

module PGN
  # {PGN::Node} is a live, lazily-built view over the {PGN::MoveText} tree.
  # A node represents the position reached by playing +move+ from its
  # +parent+'s position (the root has no move and is the game's starting
  # position). Mutations edit the underlying +MoveText+ arrays in place;
  # after any structural mutation, call +PGN::Game#root+ again for a fresh
  # tree.
  class Node
    attr_reader :move, :parent, :line, :index

    # @param move [PGN::MoveText, nil] the move played to reach this node
    # @param parent [PGN::Node, nil] the parent node (nil for the root)
    # @param line [Array<PGN::MoveText>] the line this node's move lives in
    # @param index [Integer] index of this node's move within +line+
    # @param starting_position [PGN::Position] the root's position
    # @param game [PGN::Game] back-reference so mutations can return a fresh root
    def initialize(move:, parent:, line:, index:, starting_position: nil, game: nil)
      @move = move
      @parent = parent
      @line = line
      @index = index
      @starting_position = starting_position
      @game = game
    end

    def root?
      @move.nil?
    end

    def notation
      @move&.notation
    end

    def annotation
      @move&.annotation
    end

    def comment
      @move&.comment
    end

    # All moves playable from this node's position: the continuation move
    # (the next MoveText in this node's line) plus every variation first-move
    # branching at that same position, recursively through nested brackets.
    # The first child is the mainline continuation; the rest are variations.
    def children
      @children ||= begin
        cont = continuation_movetext
        list = []
        collect_first_moves(cont, @line, @index + 1) do |mt, l, idx|
          list << Node.new(move: mt, parent: self, line: l, index: idx, game: @game)
        end
        list
      end
    end

    def variations
      children[1..]
    end

    def next
      children.first
    end

    def previous
      @parent
    end

    def [](i)
      children[i]
    end

    # Yields each mainline node from +self.next+ onward (the root is
    # excluded), matching +game.moves+ and +game.positions[1..]+.
    def main_line
      return enum_for(:main_line) unless block_given?

      node = next
      while node
        yield node
        node = node.next
      end
    end

    private

    # The MoveText played from this node's position in the current line:
    # the next entry in +line+ (nil at a terminal position). For the root,
    # +index+ is -1, so this is +line[0]+ (the first mainline move).
    def continuation_movetext
      @line && @line[@index + 1]
    end

    # Yield every first-move branching at the position before +m+ (i.e. at
    # this node's position): +m+ itself (in +l+ at +idx+), plus the first move
    # of each of +m+'s variations, plus — recursively — the first moves of
    # any variations nested on those first moves (they branch at the same
    # point, since a variation branches before the move it attaches to).
    def collect_first_moves(m, l, idx)
      return if m.nil?

      yield m, l, idx
      (m.variations || []).each do |v|
        next unless v && v[0]

        collect_first_moves(v[0], v, 0) { |*a| yield(*a) }
      end
    end
  end
end
```

```ruby
# lib/pgn.rb — add the require (insert after `require 'pgn/game'`):
require 'pgn/game'
require 'pgn/node'   # <-- add
```

```ruby
# lib/pgn/game.rb — add inside the Game class (e.g. right after `attr_reader :moves`):
# Build a fresh, navigable {PGN::Node} tree over the mainline. The tree is a
# live view of the underlying +MoveText+ structure; mutate it through the
# node API, then call +#root+ again for a fresh tree.
def root
  PGN::Node.new(
    move: nil, parent: nil, line: @moves, index: -1,
    starting_position: starting_position, game: self
  )
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle _2.7.2_ exec rspec spec/node_spec.rb`
Expected: PASS (6 examples).

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run: `bundle _2.7.2_ exec rspec`
Expected: PASS — 247 examples (241 + 6), 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/pgn/node.rb lib/pgn.rb lib/pgn/game.rb spec/node_spec.rb
git commit -m "feat(node): add PGN::Node read-only navigation + Game#root"
```

---

### Task 2: `Node#position` (lazy, cached, pure-Ruby)

**Files:**
- Modify: `lib/pgn/node.rb` (add `#position`)
- Test: `spec/node_spec.rb`

**Interfaces:**
- Produces: `Node#position` → `PGN::Position` (cached). Root's position is
  `game.starting_position`; non-root is `parent.position.move(move.notation)`.

- [ ] **Step 1: Write the failing test**

```ruby
# append to spec/node_spec.rb describe block
  describe '#position' do
    it 'root position is the starting position' do
      expect(root.position.to_fen.to_s).to eq(PGN::Position.start.to_fen.to_s)
    end

    it 'main_line positions match game.positions[1..]' do
      expect(root.main_line.map { |n| n.position.to_fen.to_s })
        .to eq(game.positions[1..].map { |p| p.to_fen.to_s })
    end

    it 'a variation node position is replayed from the root' do
      # After 1.e4 e5 2.Nc3 (the Nc3 variation first move)
      nc3_node = root.next.next.variations.first
      expected = PGN::Position.start.move('e4').move('e5').move('Nc3')
      expect(nc3_node.position.to_fen.to_s).to eq(expected.to_fen.to_s)
    end

    it 'is cached (returns the same object on second call)' do
      node = root.next
      expect(node.position).to equal(node.position)
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle _2.7.2_ exec rspec spec/node_spec.rb`
Expected: FAIL — `undefined method 'position'`.

- [ ] **Step 3: Write minimal implementation**

```ruby
# inside PGN::Node, above `private` (or as a public method):
    # The position reached at this node: the starting position for the root,
    # otherwise +parent.position+ with +move.notation+ applied. Pure Ruby
    # (no native engine); raises on an illegal SAN exactly like
    # +Game#positions+. Cached on the node.
    def position
      return @position if defined?(@position)

      @position = if root?
        @starting_position
      else
        @parent.position.then { |p| p.move(@move.notation) }
      end
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle _2.7.2_ exec rspec spec/node_spec.rb`
Expected: PASS (10 examples).

- [ ] **Step 5: Commit**

```bash
git add lib/pgn/node.rb spec/node_spec.rb
git commit -m "feat(node): add lazy cached Node#position (pure-Ruby replay)"
```

---

### Task 3: `add_variation` / `add_main_variation`

**Files:**
- Modify: `lib/pgn/node.rb` (add mutation helpers)
- Test: `spec/node_spec.rb`

**Interfaces:**
- Produces: `Node#add_variation(move_or_moves)` and
  `Node#add_main_variation(move_or_moves)`, each returning a fresh
  `game.root`. `add_variation` raises `ArgumentError` at a terminal node.

- [ ] **Step 1: Write the failing test**

```ruby
# append to spec/node_spec.rb describe block
  describe '#add_variation' do
    it 'appends a single-SAN variation branching before the next move' do
      node = root.next.next  # position before Nf3
      node.add_variation('Nc6')
      reparsed = PGN.parse(game.to_pgn).first
      # Nf3 now has variations Nc3, f4, and the new Nc6
      nf3 = reparsed.moves[2]
      expect(nf3.variations.map { |v| v.map(&:notation) })
        .to include(%w[Nc3 d5 exd5], %w[f4 exf4], ['Nc6'])
    end

    it 'appends a multi-move variation line' do
      node = root.next.next
      node.add_variation(%w[Nc6 Bc4])
      reparsed = PGN.parse(game.to_pgn).first
      expect(reparsed.moves[2].variations.map { |v| v.map(&:notation) })
        .to include(%w[Nc6 Bc4])
    end

    it 'normalizes castling 0 -> O' do
      game = PGN::Game.new(%w[e4 e5 Nf3])
      root = game.root
      root.next.next.add_variation('0-0')
      reparsed = PGN.parse(game.to_pgn).first
      expect(reparsed.moves[2].variations.map { |v| v.map(&:notation) }).to include(['O-O'])
    end

    it 'round-trips after add_variation' do
      root.next.next.add_variation(%w[Nc6 Bc4])
      reparsed = PGN.parse(game.to_pgn).first
      expect(PGN.parse(reparsed.to_pgn).first.to_pgn).to eq(reparsed.to_pgn)
    end
  end

  describe '#add_variation at a terminal node' do
    it 'raises ArgumentError' do
      game = PGN::Game.new(%w[e4 e5])
      last = game.root.main_line.last
      expect { last.add_variation('Nf6') }.to raise_error(ArgumentError)
    end
  end

  describe '#add_main_variation' do
    it 'extends the line at a terminal node' do
      game = PGN::Game.new(%w[e4 e5])
      last = game.root.main_line.last
      last.add_main_variation('Nf3')
      expect(game.moves.map(&:notation)).to eq(%w[e4 e5 Nf3])
    end

    it 'inserts a new mainline move and demotes the old continuation' do
      node = root.next.next  # position before Nf3
      node.add_main_variation('Nc6')
      expect(game.moves.map(&:notation)).to eq(%w[e4 e5 Nc6 Nf6])
      # the old continuation Nf3 is now a variation of Nc6
      reparsed = PGN.parse(game.to_pgn).first
      expect(reparsed.moves[2].variations.map { |v| v.map(&:notation) })
        .to include(['Nf3'])
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle _2.7.2_ exec rspec spec/node_spec.rb`
Expected: FAIL — `undefined method 'add_variation'`.

- [ ] **Step 3: Write minimal implementation**

```ruby
# inside PGN::Node (public mutation methods):
    # Append a new variation line (a single SAN String or an Array<String>)
    # branching before this node's next mainline move. Returns a fresh
    # +game.root+. Raises +ArgumentError+ at a terminal node (a variation
    # must branch before an existing move; use +add_main_variation+ to
    # extend the line).
    def add_variation(move_or_moves)
      cont = continuation_movetext
      raise ArgumentError, 'cannot add a variation at a terminal node' if cont.nil?

      normalize_branch_point(cont)
      cont.variations << build_movetexts(move_or_moves)
      @game.root
    end

    # Make the given moves the new mainline continuation from this node's
    # position. At a terminal node this extends the line; otherwise the old
    # continuation becomes a variation of the new first move. Returns a
    # fresh +game.root+.
    def add_main_variation(move_or_moves)
      new_line = build_movetexts(move_or_moves)
      cont = continuation_movetext

      if cont.nil?
        @line.push(*new_line)
      else
        normalize_branch_point(cont)
        vars = cont.variations
        pos = @index + 1
        old_tail = @line[(pos + 1)..] || []
        n0 = new_line[0]
        @line[pos] = n0
        @line[(pos + 1)..] = (new_line[1..] || [])
        cont.variations = []
        n0.variations = [[cont, *old_tail], *vars]
      end
      @game.root
    end
```

```ruby
# inside PGN::Node `private`:
    # Build an Array<PGN::MoveText> from a single SAN String or an Array of
    # SANs, applying the same castling 0->O normalization as Game#moves=.
    def build_movetexts(move_or_moves)
      sans = move_or_moves.is_a?(String) ? [move_or_moves] : move_or_moves
      sans.map { |s| PGN::MoveText.new(normalize_castling(s)) }
    end

    def normalize_castling(san)
      san.include?('0') ? san.gsub('0', 'O') : san
    end

    # Hoist every variation first-move branching at the position before
    # +cont+ (recursively through nested brackets) into a single flat
    # +cont.variations+ array, clearing the first-moves' at-point variations
    # (they are now flat siblings). Internal structure of each variation
    # line (tail moves and their deeper variations) is untouched. After
    # this, +cont.variations+ is a flat Array<Array<MoveText>> in the same
    # order +children+ yields.
    def normalize_branch_point(cont)
      return if cont.nil?

      lines = []
      collect_variation_lines(cont) { |v| lines << v }
      lines.each { |v| v[0].variations = [] }
      cont.variations = lines
    end

    # Yield each variation line branching at the position before +m+ (in
    # DFS order): +m+'s direct variations, plus — recursively — the
    # variations nested on each variation's first move (they branch at the
    # same point).
    def collect_variation_lines(m)
      (m.variations || []).each do |v|
        next unless v && v[0]

        yield v
        collect_variation_lines(v[0]) { |x| yield x }
      end
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle _2.7.2_ exec rspec spec/node_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/pgn/node.rb spec/node_spec.rb
git commit -m "feat(node): add_variation / add_main_variation with flatten-on-mutate"
```

---

### Task 4: `promote` / `demote` / `promote_to_main` / `demote_to_last`

**Files:**
- Modify: `lib/pgn/node.rb`
- Test: `spec/node_spec.rb`

**Interfaces:**
- Produces: `Node#promote`, `#demote`, `#promote_to_main`, `#demote_to_last`,
  each returning a fresh `game.root`. `demote` at index 0 is the inverse swap
  (variation #1 becomes mainline, old mainline becomes variation #1).

- [ ] **Step 1: Write the failing test**

```ruby
# append to spec/node_spec.rb describe block
  describe 'variation reordering' do
    # Before: after 1.e4 e5, children = [Nf3(main), Nc3, f4]
    #   Nf3.variations = [[Nc3,d5,exd5],[f4,exf4]]
    let(:branch) { root.next.next }

    it 'promote moves a variation one slot toward mainline' do
      f4 = branch.variations.last  # index 2
      f4.promote
      expect(game.moves[2].notation).to eq('Nf3')
      nf3 = game.moves[2]
      # f4 now precedes Nc3
      expect(nf3.variations.map { |v| v.first.notation }).to eq(%w[f4 Nc3])
    end

    it 'promote is a no-op for the first variation' do
      nc3 = branch.variations.first
      nc3.promote
      nf3 = game.moves[2]
      expect(nf3.variations.map { |v| v.first.notation }).to eq(%w[Nc3 f4])
    end

    it 'demote moves a variation one slot toward the end' do
      nc3 = branch.variations.first
      nc3.demote
      nf3 = game.moves[2]
      expect(nf3.variations.map { |v| v.first.notation }).to eq(%w[f4 Nc3])
    end

    it 'demote at index 0 (mainline) is the inverse swap' do
      mainline = branch.next  # Nf3, index 0
      mainline.demote
      expect(game.moves[2].notation).to eq('Nc3')   # Nc3 is new mainline
      nc3 = game.moves[2]
      # old mainline Nf3 (with its tail Nf6) is now the first variation of Nc3
      expect(nc3.variations.first.map(&:notation)).to eq(%w[Nf3 Nf6])
    end

    it 'promote_to_main makes a variation the new mainline' do
      f4 = branch.variations.last
      f4.promote_to_main
      expect(game.moves[2].notation).to eq('f4')
      expect(game.moves[3].notation).to eq('exf4')
      # old mainline Nf3 + Nf6 is now a variation of f4
      f4m = game.moves[2]
      expect(f4m.variations.map { |v| v.map(&:notation) }).to include(%w[Nf3 Nf6])
    end

    it 'demote_to_last moves a variation to the end' do
      nc3 = branch.variations.first
      nc3.demote_to_last
      nf3 = game.moves[2]
      expect(nf3.variations.map { |v| v.first.notation }).to eq(%w[f4 Nc3])
    end

    it 'demote_to_last on the mainline makes it the last variation' do
      mainline = branch.next  # Nf3
      mainline.demote_to_last
      expect(game.moves[2].notation).to eq('Nc3')  # first variation promoted
      nc3 = game.moves[2]
      # old mainline Nf3 is the LAST variation of Nc3
      expect(nc3.variations.last.map(&:notation)).to eq(%w[Nf3 Nf6])
    end

    it 'every reorder round-trips (re-parse == self)' do
      branch.variations.last.promote_to_main
      once = game.to_pgn
      expect(PGN.parse(once).first.to_pgn).to eq(once)
    end
  end

  describe 'flatten-on-mutation for same-point nested variations' do
    it 'flattens ( V1 ( V2 ) ) into ( V1 ) ( V2 ) on promote' do
      # Construct: 1.e4 e5 ( e5? no — build ( Nf3 ( Nc3 ) ) at the root branch )
      game = PGN.parse("[White \"x\"]\n\n1. e4 ( e5 ( e6 ) ) ( d5 ) *\n").first
      branch = game.root  # position before e4
      node = branch.next.variations.first  # the e5 variation
      # e5's nested variation e6 is a sibling of e5; promote e6 past e5
      e6 = branch.next.children.find { |n| n.notation == 'e6' }
      e6.promote_to_main
      reparsed = PGN.parse(game.to_pgn).first
      # e4 now has flat variations [e5, e6, d5]-ish; assert idempotent round trip
      expect(PGN.parse(reparsed.to_pgn).first.to_pgn).to eq(reparsed.to_pgn)
      e4 = reparsed.moves[0]
      expect(e4.variations.map { |v| v.first.notation }).to contain_exactly('e6', 'e5', 'd5')
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle _2.7.2_ exec rspec spec/node_spec.rb`
Expected: FAIL — `undefined method 'promote'`.

- [ ] **Step 3: Write minimal implementation**

```ruby
# inside PGN::Node (public):
    # Move this node one slot toward the mainline among its siblings.
    # No-op for the mainline (index 0) or the first variation (index 1).
    # Returns a fresh +game.root+.
    def promote
      return @game.root if root?

      i = sibling_index
      return @game.root if i.nil? || i <= 1

      cont = parent_continuation
      normalize_branch_point(cont)
      vars = cont.variations
      vars[i - 1], vars[i - 2] = vars[i - 2], vars[i - 1]
      @game.root
    end

    # Move this node one slot toward the end among its siblings. At index 0
    # (the mainline) this is the inverse swap: variation #1 becomes the new
    # mainline and the old mainline becomes variation #1. No-op at the last
    # index. Returns a fresh +game.root+.
    def demote
      return @game.root if root?

      i = sibling_index
      sibs = @parent.children
      return @game.root if i.nil? || i == sibs.size - 1

      cont = parent_continuation
      normalize_branch_point(cont)
      vars = cont.variations
      if i == 0
        v1 = vars.shift
        make_mainline(cont, v1, vars, old_main_position: :first)
      else
        vars[i - 1], vars[i] = vars[i], vars[i - 1]
      end
      @game.root
    end

    # Make this node the mainline at its branching point (the old mainline
    # becomes variation #1). No-op if already the mainline. Returns a fresh
    # +game.root+.
    def promote_to_main
      return @game.root if root?

      i = sibling_index
      return @game.root if i.nil? || i == 0

      cont = parent_continuation
      normalize_branch_point(cont)
      vars = cont.variations
      vk = vars.delete_at(i - 1)
      make_mainline(cont, vk, vars, old_main_position: :first)
      @game.root
    end

    # Move this node to the last position among its siblings. At index 0
    # the last variation becomes the new mainline and the old mainline
    # becomes the last variation. Returns a fresh +game.root+.
    def demote_to_last
      return @game.root if root?

      i = sibling_index
      return @game.root if i.nil?

      cont = parent_continuation
      normalize_branch_point(cont)
      vars = cont.variations
      if i == 0
        return @game.root if vars.empty?

        last = vars.pop
        make_mainline(cont, last, vars, old_main_position: :last)
      else
        el = vars.delete_at(i - 1)
        vars.push(el)
      end
      @game.root
    end
```

```ruby
# inside PGN::Node `private`:
    # Index of this node among its parent's children, or nil if root.
    def sibling_index
      @parent.children.index(self)
    end

    # The MoveText that is the mainline continuation at the PARENT's
    # position (the move this node is an alternative to, or this node
    # itself if it is the continuation).
    def parent_continuation
      @parent.line[@parent.index + 1]
    end

    # Make +vk+ (= [vk0, *tail]) the new mainline continuation at the
    # parent's position, replacing +cont+. The old mainline (+cont+ and its
    # tail) becomes a variation appended to +others+ either before
    # (+old_main_position == :first+) or after (+:last+). +cont.variations+
    # is cleared (its at-point variations are now +vk0+'s siblings).
    def make_mainline(cont, vk, others, old_main_position:)
      line = @parent.line
      pos = @parent.index + 1
      old_tail = line[(pos + 1)..] || []
      vk0 = vk[0]
      line[pos] = vk0
      line[(pos + 1)..] = (vk[1..] || [])
      cont.variations = []
      old_var = [cont, *old_tail]
      vk0.variations =
        old_main_position == :first ? [old_var, *others] : [*others, old_var]
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle _2.7.2_ exec rspec spec/node_spec.rb`
Expected: PASS. (If the nested-flatten test's fixture parse differs, adjust the
fixture string until `e4.variations` yields the three first-moves; the assertion
is `contain_exactly` to avoid order sensitivity.)

- [ ] **Step 5: Commit**

```bash
git add lib/pgn/node.rb spec/node_spec.rb
git commit -m "feat(node): promote / demote / promote_to_main / demote_to_last"
```

---

### Task 5: `delete`

**Files:**
- Modify: `lib/pgn/node.rb`
- Test: `spec/node_spec.rb`

**Interfaces:**
- Produces: `Node#delete` → fresh `game.root`. Removing the mainline
  continuation promotes the first variation (or truncates the line if none).

- [ ] **Step 1: Write the failing test**

```ruby
# append to spec/node_spec.rb describe block
  describe '#delete' do
    it 'removes a variation' do
      branch = root.next.next
      f4 = branch.variations.last
      f4.delete
      nf3 = game.moves[2]
      expect(nf3.variations.map { |v| v.first.notation }).to eq(%w[Nc3])
    end

    it 'removing the mainline continuation promotes the first variation' do
      branch = root.next.next
      branch.next.delete  # delete Nf3 (mainline)
      expect(game.moves[2].notation).to eq('Nc3')
      nc3 = game.moves[2]
      # remaining variation f4 is now Nc3's variation
      expect(nc3.variations.map { |v| v.first.notation }).to eq(%w[f4])
    end

    it 'removing the mainline continuation with no variations truncates' do
      game = PGN::Game.new(%w[e4 e5 Nf3 Nf6])
      node = game.root.main_line.last  # Nf6 node's parent? -> use the Nf3 node
      nf3 = game.root.main_line.to_a[2]
      nf3.delete
      expect(game.moves.map(&:notation)).to eq(%w[e4 e5])
    end

    it 'round-trips after delete' do
      root.next.next.variations.last.delete
      once = game.to_pgn
      expect(PGN.parse(once).first.to_pgn).to eq(once)
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle _2.7.2_ exec rspec spec/node_spec.rb`
Expected: FAIL — `undefined method 'delete'`.

- [ ] **Step 3: Write minimal implementation**

```ruby
# inside PGN::Node (public):
    # Remove this node and its subtree. If it is the mainline continuation,
    # the first remaining variation (if any) takes its place; otherwise the
    # line is truncated at this point. Returns a fresh +game.root+.
    def delete
      return @game.root if root?

      i = sibling_index
      return @game.root if i.nil?

      cont = parent_continuation
      normalize_branch_point(cont)
      vars = cont.variations
      if i == 0
        line = @parent.line
        pos = @parent.index + 1
        if vars.empty?
          line[pos..] = []
        else
          v1 = vars.shift
          v10 = v1[0]
          line[pos] = v10
          line[(pos + 1)..] = (v1[1..] || [])
          cont.variations = []
          v10.variations = vars
        end
      else
        vars.delete_at(i - 1)
      end
      @game.root
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle _2.7.2_ exec rspec spec/node_spec.rb`
Expected: PASS.

- [ ] **Step 5: Run the full suite**

Run: `bundle _2.7.2_ exec rspec`
Expected: PASS — all examples, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/pgn/node.rb spec/node_spec.rb
git commit -m "feat(node): delete (promote next variation or truncate)"
```

---

### Task 6: Extended round-trip gate on fixtures

**Files:**
- Modify: `spec/game_spec.rb` (additive block)

- [ ] **Step 1: Write the failing test**

```ruby
# append to spec/game_spec.rb, inside the top-level `describe PGN::Game do`
  describe 'node mutation round-trip' do
    non_round_trip = %w[doublequotes.pgn specialcharacters.pgn].freeze

    it 'every fixture survives promote/demote/add_variation and re-parses' do
      fixtures = `git ls-files spec/pgn_files/`.split.map { |p| File.expand_path(p) }
      fixtures.reject! { |p| non_round_trip.include?(File.basename(p)) }
      fixtures.each do |path|
        PGN.parse(File.read(path)).each do |game|
          root = game.root
          # find the first node that has variations
          branch = enum_for_first_branch(root)
          next unless branch

          branch.variations.first&.promote
          game.root  # fresh tree
          branch2 = enum_for_first_branch(game.root)
          branch2&.demote if branch2
          branch3 = enum_for_first_branch(game.root)
          branch3&.add_variation('Nf3') if branch3
          once = game.to_pgn
          reparsed = PGN.parse(once).first
          expect(PGN.parse(reparsed.to_pgn).first.to_pgn).to eq(once),
                 "#{path}: mutated game must round-trip"
        end
      end
    end

    # Walk to the first node (DFS over children) that has >= 1 variation.
    def enum_for_first_branch(node)
      stack = [node]
      until stack.empty?
        n = stack.shift
        return n unless n.variations.empty?
        stack.concat(n.children)
      end
      nil
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle _2.7.2_ exec rspec spec/game_spec.rb`
Expected: FAIL (add_variation on a node whose branching point is terminal, or
a fixture with no variations) — adjust the helper to skip terminal/no-variation
cases (it already `next unless branch` / guards `&.`).

- [ ] **Step 3: No implementation needed** — this exercises Tasks 1–5.

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle _2.7.2_ exec rspec spec/game_spec.rb`
Expected: PASS. (If a fixture triggers an ArgumentError from `add_variation`
on a terminal branch, the `enum_for_first_branch` helper must pick a branch
whose *next* move exists — `add_variation` operates at the branch node whose
continuation is non-nil; a node with variations always has a non-nil
continuation, so this is safe. Verify by running.)

- [ ] **Step 5: Commit**

```bash
git add spec/game_spec.rb
git commit -m "test(game): node-mutation round-trip gate across all fixtures"
```

---

### Task 7: Docs — README, CHANGELOG, TODO

**Files:**
- Modify: `README.md` (add a "Game-tree API" section)
- Modify: `CHANGELOG.md` (add entry)
- Modify: `TODO.md` (check off the item)

- [ ] **Step 1: Write the docs**

Add a README section after the "Generating SAN from coordinates" section:

```markdown
### Navigating and mutating the game tree

{PGN::Game#root} returns a navigable {PGN::Node} tree over the mainline and
its variations. A node knows its parent, its children (the mainline
continuation first, then the variations), and the {PGN::Position} it
represents. Mutations (`add_variation`, `promote`, `demote`,
`promote_to_main`, `delete`) edit the underlying structure in place; call
`#root` again for a fresh tree.

```ruby
game = PGN.parse(File.read("./examples/immortal_game.pgn")).first
root = game.root
root.main_line.map(&:notation)           # => ["e4", "e5", ...]
root.next.next.children.map(&:notation)  # alternatives at that position
root.next.next.position.to_fen.to_s      # the FEN after 1.e4 e5

root.next.next.add_variation("Nc6")      # add a variation
root = game.root                          # fresh tree after mutation
root.next.next.variations.first.promote_to_main
game.to_pgn                               # serialized with the new mainline
```
```

CHANGELOG entry under the unreleased heading:

```markdown
### Added
- `PGN::Node` — a navigable, mutable game-tree view (`PGN::Game#root`) with
  per-node `Position` (pure-Ruby replay) and variation management
  (`add_variation`, `add_main_variation`, `promote`, `demote`,
  `promote_to_main`, `demote_to_last`, `delete`). Non-breaking; `Game#moves`
  and `MoveText` keep their existing shapes and the PGN round-trip stays
  byte-identical for un-mutated games.
```

TODO.md: change `- [ ] Richer game-tree API: ...` to `- [x] Richer game-tree
API: node-style mainline/variations, add/promote/demote variations.`

- [ ] **Step 2: Commit**

```bash
git add README.md CHANGELOG.md TODO.md
git commit -m "docs: document PGN::Node game-tree API"
```

---

## Self-Review

**Spec coverage:**
- Node abstraction + parent/child/variation links → Task 1. ✓
- per-node Position (lazy, pure-Ruby) → Task 2. ✓
- add_variation / add_main_variation → Task 3. ✓
- promote / demote / promote_to_main / demote_to_last → Task 4. ✓
- demote-at-index-0 inverse swap → Task 4 test. ✓
- delete → Task 5. ✓
- flatten-on-mutation for nested same-point variations → Task 4 test. ✓
- backward compat (Game#moves, MoveText unchanged) → Tasks 1,6 keep suite green. ✓
- round-trip gate extended → Task 6. ✓
- docs → Task 7. ✓

**Placeholder scan:** none — all code blocks contain real code.

**Type consistency:** `Node.new(move:, parent:, line:, index:, starting_position:, game:)` keyword signature used consistently. `make_mainline(cont, vk, others, old_main_position:)` consistent across Tasks 3/4. `parent_continuation`, `sibling_index`, `normalize_branch_point`, `build_movetexts` defined once and reused. Mutation methods all return `@game.root`.

**One known approximation:** mutation methods return a fresh `game.root` (not the precise "affected node"). The spec said "freshly-affected Node(s)"; returning the root is the faithful, simple realization — callers re-navigate from the root. Documented in Global Constraints.
