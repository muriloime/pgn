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
