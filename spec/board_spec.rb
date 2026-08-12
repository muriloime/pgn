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
