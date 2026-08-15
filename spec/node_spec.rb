require 'spec_helper'

# Helpers for order-independent variation comparison. The parser's
# `variation_list` rule is right-recursive, so a move's variations are stored
# in reverse of their PGN-text order; round-tripping flips that order each
# parse. We therefore compare variation trees as sorted signatures (the same
# approach the existing game_spec round-trip gate uses), and reference
# variations by notation rather than by index.
def node_sig(move)
  [move.notation, (move.variations || []).map { line_sig(_1) }.sort]
end

def line_sig(line)
  line.map { node_sig(_1) }
end

def tree_sig(game)
  game.moves.map { node_sig(_1) }
end

describe PGN::Node do
  let(:game) { PGN.parse(File.read(File.expand_path('pgn_files/variations.pgn', __dir__), encoding: Encoding::ISO_8859_1)).first }
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

  it 'children of the position after 1.e4 e5 are Nf3 (main), Nc3, f4 (any order)' do
    node = root.next.next # after e4 (white), after e5 (black) => before Nf3
    expect(node.children.map(&:notation)).to contain_exactly('Nf3', 'Nc3', 'f4')
    expect(node.next.notation).to eq('Nf3') # mainline continuation is first
    expect(node.variations.map(&:notation)).to contain_exactly('Nc3', 'f4')
  end

  it 'nested variation f5 is a sibling of d5 under the Nc3 node' do
    nc3_node = root.next.next.children.find { |n| n.notation == 'Nc3' }
    expect(nc3_node.children.map(&:notation)).to contain_exactly('d5', 'f5')
  end

  it 'previous walks back to the root' do
    node = root.next.next.next # Nf3 node
    expect(node.previous.notation).to eq('e5')
    expect(node.previous.previous.notation).to eq('e4')
    expect(node.previous.previous.previous).to be_root
  end

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
      nc3_node = root.next.next.children.find { |n| n.notation == 'Nc3' }
      expected = PGN::Position.start.move('e4').move('e5').move('Nc3')
      expect(nc3_node.position.to_fen.to_s).to eq(expected.to_fen.to_s)
    end

    it 'is cached (returns the same object on second call)' do
      node = root.next
      expect(node.position).to equal(node.position)
    end
  end

  describe '#add_variation' do
    it 'appends a single-SAN variation branching before the next move' do
      root.next.next.add_variation('Nc6')
      expect(game.moves[2].variations.map { |v| v.map(&:notation) })
        .to include(['Nc6'], %w[Nc3 d5 exd5], %w[f4 exf4])
    end

    it 'appends a multi-move variation line' do
      root.next.next.add_variation(%w[Nc6 Bc4])
      expect(game.moves[2].variations.map { |v| v.map(&:notation) }).to include(%w[Nc6 Bc4])
    end

    it 'normalizes castling 0 -> O' do
      g = PGN::Game.new(%w[e4 e5 Nf3])
      g.root.next.next.add_variation('0-0')
      expect(g.moves[2].variations.map { |v| v.map(&:notation) }).to include(['O-O'])
    end

    it 'round-trips (variation set stable under re-parse)' do
      root.next.next.add_variation(%w[Nc6 Bc4])
      reparsed = PGN.parse(game.to_pgn).first
      expect(tree_sig(reparsed)).to eq(tree_sig(game))
    end
  end

  describe '#add_variation at a terminal node' do
    it 'raises ArgumentError' do
      g = PGN::Game.new(%w[e4 e5])
      last = g.root.main_line.to_a.last
      expect { last.add_variation('Nf6') }.to raise_error(ArgumentError)
    end
  end

  describe '#add_main_variation' do
    it 'extends the line at a terminal node' do
      g = PGN::Game.new(%w[e4 e5])
      g.root.main_line.to_a.last.add_main_variation('Nf3')
      expect(g.moves.map(&:notation)).to eq(%w[e4 e5 Nf3])
    end

    it 'inserts a new mainline move and demotes the old continuation to a variation' do
      node = root.next.next # position before Nf3
      node.add_main_variation('Nc6')
      expect(game.moves.map(&:notation)).to eq(%w[e4 e5 Nc6])
      # old mainline Nf3 + Nf6 is now a variation of Nc6
      expect(game.moves[2].variations.map { |v| v.map(&:notation) }).to include(%w[Nf3 Nf6])
    end
  end

  describe 'variation reordering' do
    # Storage order of Nf3's variations is reverse of the PGN text
    # (`[f4-line, Nc3-line]`) because the parser reverses variation order.
    # Tests reference variations by notation, never by index.
    let(:branch) { root.next.next }
    let(:nf3) { game.moves[2] }

    def find_variation(notation)
      branch.children.find { |n| n.notation == notation }
    end

    it 'promote moves a variation one slot toward mainline' do
      find_variation('Nc3').promote
      # Nc3 was behind f4 in storage; now it is first (just after the mainline)
      expect(nf3.variations.first.first.notation).to eq('Nc3')
    end

    it 'promote is a no-op for the first variation' do
      find_variation('f4').promote # f4 is already the first stored variation
      expect(nf3.variations.first.first.notation).to eq('f4')
    end

    it 'demote moves a variation one slot toward the end' do
      find_variation('f4').demote
      expect(nf3.variations.last.first.notation).to eq('f4')
    end

    it 'demote at index 0 (mainline) is the inverse swap' do
      branch.next.demote # Nf3 (mainline) -> variation #1
      # the first stored variation (f4) becomes the new mainline
      expect(game.moves[2].notation).to eq('f4')
      expect(game.moves[3].notation).to eq('exf4')
      # old mainline Nf3 + Nf6 is now the first variation of f4
      expect(game.moves[2].variations.first.map(&:notation)).to eq(%w[Nf3 Nf6])
    end

    it 'promote_to_main makes a variation the new mainline' do
      find_variation('Nc3').promote_to_main
      expect(game.moves.map(&:notation)).to eq(%w[e4 e5 Nc3 d5 exd5])
      # old mainline Nf3 + Nf6 is now a variation of Nc3
      expect(game.moves[2].variations.map { |v| v.map(&:notation) }).to include(%w[Nf3 Nf6])
    end

    it 'demote_to_last moves a variation to the end' do
      find_variation('f4').demote_to_last
      expect(nf3.variations.last.first.notation).to eq('f4')
    end

    it 'demote_to_last on the mainline makes it the last variation' do
      branch.next.demote_to_last # Nf3 -> last variation
      # the last stored variation (Nc3) is promoted to mainline
      expect(game.moves[2].notation).to eq('Nc3')
      # old mainline Nf3 + Nf6 is the LAST variation of Nc3
      expect(game.moves[2].variations.last.map(&:notation)).to eq(%w[Nf3 Nf6])
    end

    it 'every reorder round-trips (variation set stable under re-parse)' do
      find_variation('Nc3').promote_to_main
      reparsed = PGN.parse(game.to_pgn).first
      expect(tree_sig(reparsed)).to eq(tree_sig(game))
    end
  end

  describe 'flatten-on-mutation for same-point nested variations' do
    it 'flattens ( V1 ( V2 ) ) into flat siblings on promote_to_main' do
      # 1. e4 ( e5 ( e6 ) ) ( d5 )  — e5, e6, d5 all branch before e4 (at root).
      g = PGN.parse(%([White "x"]\n\n1. e4 ( e5 ( e6 ) ) ( d5 ) *\n).force_encoding(Encoding::ISO_8859_1)).first
      expect(g.root.children.map(&:notation)).to contain_exactly('e4', 'e5', 'e6', 'd5')
      e6 = g.root.children.find { |n| n.notation == 'e6' }
      e6.promote_to_main
      # e6 is now the mainline; e4, e5, d5 are flat variations of e6
      expect(g.moves.map(&:notation)).to eq(['e6'])
      expect(g.moves[0].variations.map { |v| v.first.notation }).to contain_exactly('e4', 'e5', 'd5')
      reparsed = PGN.parse(g.to_pgn).first
      expect(tree_sig(reparsed)).to eq(tree_sig(g))
    end
  end

  describe '#delete' do
    let(:branch) { root.next.next }
    let(:nf3) { game.moves[2] }

    it 'removes a variation' do
      branch.children.find { |n| n.notation == 'f4' }.delete
      expect(nf3.variations.map { |v| v.first.notation }).to contain_exactly('Nc3')
    end

    it 'removing the mainline continuation promotes the first variation' do
      branch.next.delete # delete Nf3 (mainline)
      # the first stored variation (f4) takes its place
      expect(game.moves[2].notation).to eq('f4')
      expect(game.moves[3].notation).to eq('exf4')
      # the remaining variation (Nc3) is now f4's variation
      expect(game.moves[2].variations.map { |v| v.first.notation }).to contain_exactly('Nc3')
    end

    it 'removing the mainline continuation with no variations truncates' do
      g = PGN::Game.new(%w[e4 e5 Nf3 Nf6])
      nf3 = g.root.main_line.to_a[2]
      nf3.delete
      expect(g.moves.map(&:notation)).to eq(%w[e4 e5])
    end

    it 'round-trips after delete' do
      branch.children.find { |n| n.notation == 'f4' }.delete
      reparsed = PGN.parse(game.to_pgn).first
      expect(tree_sig(reparsed)).to eq(tree_sig(game))
    end
  end
end
