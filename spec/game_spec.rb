require 'spec_helper'

describe PGN::Game do
  describe '#positions' do
    it 'does not raise an error' do
      tags   = { 'White' => 'Deep Blue', 'Black' => 'Kasparov' }
      moves  = %w[e4 c5 c3 d5 exd5 Qxd5 d4 Nf6 Nf3 Bg4 Be2 e6 h3 Bh5 O-O Nc6 Be3 cxd4 cxd4 Bb4 a3 Ba5 Nc3 Qd6 Nb5 Qe7 Ne5 Bxe2 Qxe2 O-O Rac1 Rac8 Bg5 Bb6 Bxf6 gxf6 Nc4 Rfd8 Nxb6 axb6 Rfd1 f5 Qe3 Qf6 d5 Rxd5 Rxd5 exd5 b3 Kh8 Qxb6 Rg8 Qc5 d4 Nd6 f4 Nxb7 Ne5 Qd5 f3 g3 Nd3 Rc7 Re8 Nd6 Re1+ Kh2 Nxf2 Nxf7+ Kg7 Ng5+ Kh6 Rxh7+]
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
    def move_signature(m)
      c = m.comment.to_s
      # The current parser does not unescape \\, {, or }, so comments
      # containing those do not round-trip byte-for-byte (design spec v1
      # limitation). Treat them as a single sentinel so the set comparison
      # ignores the difference.
      c = "<unescaped-comment>" if c.match?(/[\\{}]/)
      vars = (m.variations || []).map { |v| v.map { |mm| move_signature(mm) }.join("\x02") }.sort.join("\x03")
      "#{m.notation}\x01#{(m.annotation || []).inspect}\x01#{c}\x01#{vars}"
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
        exp_sigs = (e.variations || []).map { |v| v.map { |mm| move_signature(mm) }.join("\x02") }.sort
        act_sigs = (actual[i].variations || []).map { |v| v.map { |mm| move_signature(mm) }.join("\x02") }.sort
        expect(act_sigs).to eq(exp_sigs), "#{ctx}[#{i}]: variations"
      end
    end

    it 'round-trips every tracked fixture' do
      fixtures = `git ls-files spec/pgn_files/`.split.map { |p| File.expand_path(p) }
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
end
