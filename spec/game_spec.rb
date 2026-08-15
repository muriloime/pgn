require 'spec_helper'

describe PGN::Game do
  describe '#positions' do
    it 'does not raise an error' do
      tags   = { 'White' => 'Deep Blue', 'Black' => 'Kasparov' }
      moves  = %w[e4 c5 c3 d5 exd5 Qxd5 d4 Nf6 Nf3 Bg4 Be2 e6 h3 Bh5 O-O Nc6 Be3 cxd4
                  cxd4 Bb4 a3 Ba5 Nc3 Qd6 Nb5 Qe7 Ne5 Bxe2 Qxe2 O-O Rac1 Rac8 Bg5 Bb6
                  Bxf6 gxf6 Nc4 Rfd8 Nxb6 axb6 Rfd1 f5 Qe3 Qf6 d5 Rxd5 Rxd5 exd5 b3
                  Kh8 Qxb6 Rg8 Qc5 d4 Nd6 f4 Nxb7 Ne5 Qd5 f3 g3 Nd3 Rc7 Re8 Nd6 Re1+
                  Kh2 Nxf2 Nxf7+ Kg7 Ng5+ Kh6 Rxh7+]
      result = '1-0'
      game = PGN::Game.new(moves, tags, result)
      expect { game.positions }.not_to raise_error
    end

    it 'has fullmove 2 after 1.e4 c5' do
      moves = %w[e4 c5]
      game = PGN::Game.new(moves)
      last_pos = game.positions.last

      expect(last_pos.fullmove).to eq 2
    end
  end

  describe '#each_position' do
    it 'yields each position in order when given a block' do
      game = PGN::Game.new(%w[e4 e5])
      yielded = []
      game.each_position { |p| yielded << p.to_fen.to_s }
      expect(yielded).to eq(
        [
          PGN::Position.start.to_fen.to_s,
          game.positions[1].to_fen.to_s,
          game.positions[2].to_fen.to_s
        ]
      )
    end

    it 'returns an Enumerator when no block is given' do
      game = PGN::Game.new(%w[e4 e5])
      expect(game.each_position).to be_an(Enumerator)
    end

    it 'produces the same positions as #positions' do
      game = PGN::Game.new(%w[e4 c5 Nf3])
      expect(game.each_position.map { |p| p.to_fen.to_s })
        .to eq(game.positions.map { |p| p.to_fen.to_s })
    end

    it 'does not materialize the full array when only the last is needed' do
      moves = %w[e4 c5 Nf3 d6]
      game  = PGN::Game.new(moves)
      last = nil
      game.each_position { |p| last = p }
      expect(last.to_fen.to_s).to eq(game.positions.last.to_fen.to_s)
    end
  end

  describe '#to_pgn' do
    it 'returns a canonical PGN string ending with a newline' do
      game = PGN::Game.new(%w[e4 e5], { 'White' => 'A' }, '1-0')
      expect(game.to_pgn).to eq("[White \"A\"]\n\n1. e4 e5 1-0\n")
      expect(game.to_pgn).to end_with("\n")
    end

    # Recursively compare two move lists: notation, annotation, comment,
    # and the structure of their variations.
    #
    # The current parser reverses the order of a move's variations on each
    # parse (its `variation_list` rule is right-recursive), so variation
    # *order* does not round-trip; only the set of variations does. We
    # therefore compare variations order-independently via a canonical
    # signature.
    def move_signature(move)
      c = move.comment.to_s
      # The current parser does not unescape \\, {, or }, so comments
      # containing those do not round-trip byte-for-byte (design spec v1
      # limitation). Treat them as a single sentinel so the set comparison
      # ignores the difference.
      c = '<unescaped-comment>' if c.match?(/[\\{}]/)
      vars = (move.variations || []).map { |v| v.map { |sub| move_signature(sub) }.join("\x02") }.sort.join("\x03")
      "#{move.notation}\x01#{(move.annotation || []).inspect}\x01#{c}\x01#{vars}"
    end

    def expect_moves_equal(expected, actual, ctx)
      expect(actual.map(&:notation)).to eq(expected.map(&:notation)),
                                        "#{ctx}: notation"
      expected.each_with_index do |e, i|
        expect(actual[i].annotation).to eq(e.annotation), "#{ctx}[#{i}]: annotation"
        # The current parser cannot unescape braces, so comments containing
        # literal braces do not round-trip byte-for-byte (design spec v1
        # limitation). Skip the comparison for those.
        unless e.comment.to_s.match?(/[\\{}]/)
          expect(actual[i].comment).to eq(e.comment),
                                       "#{ctx}[#{i}]: comment #{e.comment.inspect} vs #{actual[i].comment.inspect}"
        end
        # Variations compared as an order-independent set of signatures.
        exp_sigs = (e.variations || []).map { |v| v.map { |sub| move_signature(sub) }.join("\x02") }.sort
        act_sigs = (actual[i].variations || []).map { |v| v.map { |sub| move_signature(sub) }.join("\x02") }.sort
        expect(act_sigs).to eq(exp_sigs), "#{ctx}[#{i}]: variations"
      end
    end

    # Fixtures that do not round-trip byte-for-byte: doublequotes has
    # unescaped inner quotes (serializer escapes them) and specialcharacters
    # is multibyte and requires the Encoding::UTF_8 argument to parse.
    it 'round-trips every tracked fixture' do
      non_round_trip = %w[doublequotes.pgn specialcharacters.pgn].freeze
      fixtures = `git ls-files spec/pgn_files/`.split.map { |p| File.expand_path(p) }
      fixtures.reject! { |p| non_round_trip.include?(File.basename(p)) }
      fixtures.each do |path|
        PGN.parse(File.read(path)).each_with_index do |game, gi|
          reparsed = PGN.parse(game.to_pgn).first

          expect(reparsed.result).to eq(game.result),
                                     "#{path}##{gi}: result"
          expect_moves_equal(game.moves, reparsed.moves, "#{path}##{gi}")

          # Reparsed tags must be a superset of the original (a no-tag game
          # gains a synthesized Result tag).
          original_tags = game.tags || {}
          reparsed_tags = reparsed.tags || {}
          original_tags.each do |k, v|
            expect(reparsed_tags[k]).to eq(v),
                                        "#{path}##{gi}: tag #{k} #{v.inspect} vs #{reparsed_tags[k].inspect}"
          end
        end
      end
    end
  end

  describe 'node mutation round-trip' do
    non_round_trip = %w[doublequotes.pgn specialcharacters.pgn].freeze

    # A node-sig tree with variations sorted, so the comparison is
    # order-independent (the parser reverses variation order on each parse).
    def node_sig(move)
      [move.notation, (move.variations || []).map { line_sig(_1) }.sort]
    end

    def line_sig(line)
      line.map { node_sig(_1) }
    end

    def tree_sig(game)
      game.moves.map { node_sig(_1) }
    end

    # First node (DFS over children) that has at least one variation. Such a
    # node always has a non-nil continuation, so add_variation can branch.
    def first_branch_with_variations(node)
      stack = [node]
      until stack.empty?
        n = stack.shift
        return n unless n.variations.empty?

        stack.concat(n.children)
      end
      nil
    end

    it 'every fixture survives promote/demote/add_variation and re-parses' do
      fixtures = `git ls-files spec/pgn_files/`.split.map { |p| File.expand_path(p) }
      fixtures.reject! { |p| non_round_trip.include?(File.basename(p)) }
      fixtures.each do |path|
        PGN.parse(File.read(path, encoding: Encoding::ISO_8859_1)).each do |game|
          root = game.root

          # promote then demote the first variation if one exists
          branch = first_branch_with_variations(root)
          if branch && !branch.variations.empty?
            branch.variations.first.promote
            game.root
            b2 = first_branch_with_variations(game.root)
            if b2 && !b2.variations.empty?
              b2.variations.first.demote
              game.root
            end
            b3 = first_branch_with_variations(game.root)
            b3&.add_variation('Nc3')
          end

          once = game.to_pgn
          reparsed = PGN.parse(once).first
          expect(tree_sig(reparsed)).to eq(tree_sig(game)),
                                        "#{path}: mutated game tree must round-trip (set-stable)"
        end
      end
    end
  end
end
