require 'spec_helper'

describe PGN::Serializer do
  describe '#to_s' do
    it 'serializes a simple game with tags and result' do
      game = PGN::Game.new(%w[e4 e5], { 'White' => 'A', 'Black' => 'B' }, '1-0')
      expected = "[White \"A\"]\n[Black \"B\"]\n\n1. e4 e5 1-0\n"
      expect(PGN::Serializer.new(game).to_s).to eq(expected)
    end

    it 'synthesizes a Result tag when there are no tags' do
      game = PGN::Game.new(%w[e4 e5])
      expected = "[Result \"*\"]\n\n1. e4 e5 *\n"
      expect(PGN::Serializer.new(game).to_s).to eq(expected)
    end

    it 'serializes an empty game as just the result' do
      game = PGN::Game.new([], nil, '*')
      expected = "[Result \"*\"]\n\n*\n"
      expect(PGN::Serializer.new(game).to_s).to eq(expected)
    end

    it 'emits * when there is no result' do
      game = PGN::Game.new(%w[e4 e5], { 'White' => 'A' })
      expect(PGN::Serializer.new(game).to_s).to end_with("1. e4 e5 *\n")
    end

    it 'escapes backslashes and quotes in tag values' do
      game = PGN::Game.new(%w[e4], { 'White' => 'A "B" \\C' }, '1-0')
      expect(PGN::Serializer.new(game).to_s).to start_with("[White \"A \\\"B\\\" \\\\C\"]\n")
    end

    it 'serializes castling as O-O / O-O-O' do
      game = PGN::Game.new(%w[O-O O-O-O])
      expect(PGN::Serializer.new(game).to_s).to eq("[Result \"*\"]\n\n1. O-O O-O-O *\n")
    end

    it 'emits a single annotation after the notation' do
      moves = [PGN::MoveText.new('e4', ['$4'])]
      game = PGN::Game.new(moves, { 'White' => 'A' }, '1-0')
      expect(PGN::Serializer.new(game).to_s).to eq("[White \"A\"]\n\n1. e4 $4 1-0\n")
    end

    it 'emits symbolic annotations verbatim' do
      moves = [PGN::MoveText.new('e4', ['??'])]
      game = PGN::Game.new(moves, { 'White' => 'A' }, '1-0')
      expect(PGN::Serializer.new(game).to_s).to eq("[White \"A\"]\n\n1. e4 ?? 1-0\n")
    end

    it 'emits multiple annotations in order' do
      moves = [PGN::MoveText.new('d4'), PGN::MoveText.new('d5', ['$2', '$11'])]
      game = PGN::Game.new(moves, { 'White' => 'A' }, '1/2-1/2')
      expect(PGN::Serializer.new(game).to_s).to eq("[White \"A\"]\n\n1. d4 d5 $2 $11 1/2-1/2\n")
    end

    it 'wraps move comments in braces with spaces' do
      moves = [PGN::MoveText.new('e4', nil, 'good move')]
      game = PGN::Game.new(moves, { 'White' => 'A' }, '1-0')
      expect(PGN::Serializer.new(game).to_s).to eq("[White \"A\"]\n\n1. e4 { good move } 1-0\n")
    end

    it 'reproduces the variations.pgn movetext shape, including 2... after variations' do
      game = PGN.parse(File.read('./spec/pgn_files/variations.pgn')).first
      expected = "[Black \"Petrov\"]\n[White \"Somebody\"]\n\n" \
                "1. e4 e5 2. Nf3 { comment } " \
                "(2. f4 exf4 { final variation }) " \
                "(2. Nc3 { other } 2... d5 (2... f5) 3. exd5) " \
                "2... Nf6 *\n"
      expect(PGN::Serializer.new(game).to_s).to eq(expected)
    end

    it 'emits a game comment as the first movetext token' do
      game = PGN::Game.new([], nil, '*', nil, 'game comment')
      expect(PGN::Serializer.new(game).to_s).to eq("[Result \"*\"]\n\n{ game comment } *\n")
    end

    it 'numbers the first move 1... when starting from a FEN with black to move' do
      fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1'
      game = PGN::Game.new(%w[e5], { 'FEN' => fen }, '*')
      expected = "[FEN \"#{fen}\"]\n\n1... e5 *\n"
      expect(PGN::Serializer.new(game).to_s).to eq(expected)
    end

    it 'serializes -- moves verbatim and alternates color/fullmove' do
      game = PGN::Game.new(%w[-- e4])
      expect(PGN::Serializer.new(game).to_s).to eq("[Result \"*\"]\n\n1. -- e4 *\n")
    end
  end
end
