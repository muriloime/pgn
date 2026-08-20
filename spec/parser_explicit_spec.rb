require 'spec_helper'
require 'pgn'

# Explicit, hardcoded expectations for the Racc + StringScanner parser.
# These do not reference the legacy whittle parser and survive its removal;
# they pin the public PGN.parse behavior on the features exercised by the
# fixtures plus representative edge cases.
RSpec.describe PGN, '.parse (racc parser)' do
  def notations(moves)
    moves.map(&:notation)
  end

  def variations_as(move)
    (move.variations || []).map { |v| notations(v) }
  end

  describe 'results' do
    it 'parses a 1-0 result' do
      game = PGN.parse('[White "A"] 1. e4 e5 1-0').first
      expect(game.result).to eq('1-0')
    end

    it 'parses a 0-1 result' do
      game = PGN.parse('[White "A"] 1. e4 e5 0-1').first
      expect(game.result).to eq('0-1')
    end

    it 'parses a 1/2-1/2 draw result' do
      game = PGN.parse('[White "A"] 1. e4 e5 1/2-1/2').first
      expect(game.result).to eq('1/2-1/2')
    end

    it 'parses a * (unknown) result' do
      game = PGN.parse('[White "A"] 1. e4 e5 *').first
      expect(game.result).to eq('*')
    end

    it 'parses a result-only (empty movetext) game' do
      game = PGN.parse('[Event "?"] *').first
      expect(game.result).to eq('*')
      expect(game.moves).to be_empty
    end
  end

  describe 'tags' do
    it 'extracts tag values (stripping surrounding quotes)' do
      game = PGN.parse(%([White "Kasparov"]\n[Black "Deep Blue"] 1. e4 1-0)).first
      expect(game.tags['White']).to eq('Kasparov')
      expect(game.tags['Black']).to eq('Deep Blue')
    end

    it 'keeps the first value on duplicate tag keys' do
      game = PGN.parse(%([White "First"]\n[White "Second"] 1. e4 1-0)).first
      expect(game.tags['White']).to eq('First')
    end

    it 'preserves unescaped double-quotes inside a tag value' do
      game = PGN.parse(File.read('./spec/pgn_files/doublequotes.pgn')).first
      expect(game.tags['Event']).to eq('IRT BLITZ "Sub Zonal"')
    end

    it 'honors the Encoding argument for multibyte tag values' do
      text = File.read('./spec/pgn_files/specialcharacters.pgn')
      games = PGN.parse(text, Encoding::UTF_8)
      expect(games.first.tags['WhiteTeam']).to eq('NARIÑO')
      expect(games.last.tags['Site']).to eq(
        'HOTEL CAFEIRA Calle 18 Nro. 5 – 38 Centro de Pereira – Risaralda'
      )
    end
  end

  describe 'san moves' do
    it 'parses pawn moves and captures' do
      game = PGN.parse('[White "A"] 1. e4 d5 2. exd5 1-0').first
      expect(notations(game.moves)).to eq(%w[e4 d5 exd5])
    end

    it 'parses promotion with check' do
      game = PGN.parse('[White "A"] 1. e7 d8=Q+ 1-0').first
      expect(game.moves[-1].notation).to eq('d8=Q+')
    end

    it 'parses check and checkmate' do
      game = PGN.parse('[White "A"] 1. Qe7+ Qxe7 2. Qxf7# 1-0').first
      expect(notations(game.moves)).to eq(%w[Qe7+ Qxe7 Qxf7#])
    end

    it 'parses castling (O-O and O-O-O)' do
      game = PGN.parse('[White "A"] 1. O-O O-O-O 1-0').first
      expect(notations(game.moves)).to eq(%w[O-O O-O-O])
    end

    it 'normalizes 0-form castling to O-form in move notation' do
      game = PGN.parse(File.read('./spec/pgn_files/alternate_castling.pgn')).first
      expect(game.moves.last.notation).to eq('O-O-O')
    end

    it 'parses major-piece moves with disambiguation' do
      game = PGN.parse('[White "A"] 1. Nf3 Nc6 2. Nef6 Nef6 1-0').first
      expect(notations(game.moves)).to eq(%w[Nf3 Nc6 Nef6 Nef6])
    end

    it 'parses the dont-care move (--) inside a variation' do
      game = PGN.parse('[White "A"] 1. e4 (1. -- d5) e5 1-0').first
      expect(variations_as(game.moves.first)).to eq([%w[-- d5]])
    end
  end

  describe 'annotations' do
    it 'parses numeric annotation glyphs' do
      game = PGN.parse('[White "A"] 1. e4 e5 2. Nf3 $1 Nc6 1-0').first
      expect(game.moves[2].annotation).to eq(['$1'])
    end

    it 'parses punctuation annotations (!?, ?!, !!, ??)' do
      game = PGN.parse('[White "A"] 1. e4!? e5?! 2. Nf3 Nc6 1-0').first
      expect(game.moves[0].annotation).to eq(['!?'])
      expect(game.moves[1].annotation).to eq(['?!'])
    end

    it 'parses multiple annotations on one move' do
      game = PGN.parse(File.read('./spec/pgn_files/two_annotations.pgn')).first
      expect(game.moves[1].annotation).to eq(['$2', '$11'])
    end
  end

  describe 'comments' do
    it 'attaches a comment after a move and cleans whitespace' do
      game = PGN.parse('[White "A"] 1. e4 { a  comment } e5 1-0').first
      expect(game.moves[0].comment).to eq('a comment')
    end

    it 'parses a multiline comment and collapses whitespace' do
      game = PGN.parse(File.read('./spec/pgn_files/multiline_comments.pgn')).first
      expect(game.moves[5].comment).to eq('I pity the fool!')
    end

    it 'parses nested brace comments (lexer recurses inner braces)' do
      game = PGN.parse(File.read('./spec/pgn_files/nested_comments.pgn')).first
      # The lexer recurses and captures the full nested comment; the exact
      # cleaned text is sensitive to the (pre-existing, shared with whittle)
      # double-clean in Game#moves=, so assert stable substrings.
      comment = game.moves[2].comment
      expect(comment).to include('nested')
      expect(comment).to include('comment')
    end

    it 'captures a standalone comment as the game comment (with braces)' do
      game = PGN.parse(File.read('./spec/pgn_files/no_moves.pgn')).last
      expect(game.comment).to eq('{game comment}')
    end
  end

  describe 'variations' do
    it 'parses a single variation attached to a move' do
      game = PGN.parse('[White "A"] 1. e4 (1. d4 d5) e5 1-0').first
      expect(variations_as(game.moves.first)).to eq([%w[d4 d5]])
    end

    it 'parses a nested variation' do
      game = PGN.parse('[White "A"] 1. e4 (1. d4 (1... d5) dxc4) e5 1-0').first
      outer = game.moves.first.variations.first
      expect(notations(outer)).to eq(%w[d4 dxc4])
      expect(variations_as(outer[0])).to eq([%w[d5]])
    end

    it 'compares multiple variations as an order-independent set' do
      game = PGN.parse('[White "A"] 1. e4 (1. d4) (1. Nf3) e5 1-0').first
      expect(variations_as(game.moves.first).sort).to eq([%w[d4], %w[Nf3]].sort)
    end

    it 'parses a variation that itself contains an empty move' do
      game = PGN.parse(File.read('./spec/pgn_files/empty_variation_move.pgn')).first
      expect(game.result).to eq('*')
      expect(game.moves.last.notation).to eq('Ng5')
    end
  end

  describe 'move suffix (comments, NAGs, variations in any order)' do
    it 'attaches two comments before a variation to the move' do
      game = PGN.parse('[White "A"] 1. Bxh7+ Kxh7 {a} {b} (20... Kf8) 2. Ng5+ *').first
      move = game.moves[1]
      expect(move.notation).to eq('Kxh7')
      expect(move.comment).to eq('a b')
      expect(variations_as(move)).to eq([%w[Kf8]])
    end

    it 'attaches a comment after a variation to the same move' do
      game = PGN.parse('[White "A"] 1. e4 (1... c5) {a} (2... f5) 2. Nf3 *').first
      move = game.moves.first
      expect(move.comment).to eq('a')
      expect(variations_as(move).sort).to eq([%w[c5], %w[f5]].sort)
    end

    it 'merges an arbitrary mix of comments, NAGs, and variations' do
      game = PGN.parse('[White "A"] 1. e4 {c1} $1 (1... d5) {c2} $2 *').first
      move = game.moves.first
      expect(move.comment).to eq('c1 c2')
      expect(move.annotation).to eq(%w[$1 $2])
      expect(variations_as(move)).to eq([%w[d5]])
    end

    it 'round-trips a multi-comment move through parse -> serialize -> parse' do
      input = +"[White \"A\"]\n\n1. e4 {a} {b} (1... d5) *\n"
      once = PGN.parse(input, Encoding::UTF_8).first.to_pgn
      twice = PGN.parse(once, Encoding::UTF_8).first.to_pgn
      expect(twice).to eq(once)
    end
  end

  describe 'pgn (verbatim raw text)' do
    it 'returns the verbatim text for a single game' do
      input = "[White \"A\"] 1. e4 1-0\n"
      expect(PGN.parse(input).first.pgn).to eq(input)
    end

    it 'does not mutate a frozen input string' do
      input = "[White \"A\"] 1. e4 1-0\n".freeze
      expect { PGN.parse(input, Encoding::UTF_8) }.not_to raise_error
      expect(input.encoding).to eq(Encoding::UTF_8)
      expect(PGN.parse(input, Encoding::UTF_8).first.pgn).to eq(input)
    end

    it 'partitions consecutive games contiguously' do
      input = "[White \"A\"] 1. e4 1-0\n\n[White \"B\"] 1. d4 0-1\n"
      games = PGN.parse(input)
      expect(games.map(&:pgn)).to eq(["[White \"A\"] 1. e4 1-0\n\n", "[White \"B\"] 1. d4 0-1\n"])
    end

    it 'includes a leading percent comment in the first game pgn' do
      input = "% header\n[White \"A\"] 1. e4 *\n"
      expect(PGN.parse(input).first.pgn).to eq(input)
    end
  end

  describe 'multiple games' do
    it 'returns games in source order' do
      games = PGN.parse("[White \"One\"] 1. e4 1-0\n\n[White \"Two\"] 1. d4 0-1")
      expect(games.map { |g| g.tags['White'] }).to eq(%w[One Two])
    end
  end

  describe 'starting position (FEN tag)' do
    it 'uses the FEN tag for positions' do
      game = PGN.parse(File.read('./spec/pgn_files/fen.pgn')).first
      expect(game.positions.first.to_fen.to_s).to eq(game.tags['FEN'])
    end
  end
end
