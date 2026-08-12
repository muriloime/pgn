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
