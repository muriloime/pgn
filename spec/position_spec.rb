require 'spec_helper'

describe PGN::Position do

  describe "start" do

    it "should have fullmove 1" do
      pos = PGN::Position.start
      pos.fullmove.should == 1
    end
    
  end
  
  context "disambiguating moves" do
    describe "using SAN square disambiguation" do
      pos = PGN::FEN.new("r1bqkb1r/pp1p1ppp/2n1pn2/8/3NP3/2N5/PPP2PPP/R1BQKB1R w KQkq - 3 6").to_position
      next_pos = pos.move("Ndb5")

      it "should move the specified piece" do
        next_pos.board.at("d4").should be_nil
      end

      it "should not move the other piece" do
        next_pos.board.at("c3").should == "N"
      end
    end

    describe "using discovered check" do
      pos = PGN::FEN.new("rnbqk2r/p1pp1ppp/1p2pn2/8/1bPP4/2N1P3/PP3PPP/R1BQKBNR w KQkq - 0 5").to_position
      next_pos = pos.move("Ne2")

      it "should move the piece that doesn't give discovered check" do
        next_pos.board.at("g1").should be_nil
      end

      it "shouldn't move the other piece" do
        next_pos.board.at("c3").should == "N"
      end
    end

    describe "with two pawns on the same file" do
      pos = PGN::FEN.new("r2q1rk1/4bppp/p3n3/1p2n3/4N3/1B2BP2/PP3P1P/R2Q1RK1 w - - 4 19").to_position
      next_pos = pos.move("f4")

      it "should move the pawn in front" do
        next_pos.board.at("f3").should be_nil
      end

      it "should not move the other pawn" do
        next_pos.board.at("f2").should == "P"
      end
    end
  end
end

# New exhaustive coverage below. Existing `should` examples above are
# intentionally left untouched.

describe PGN::Position do
  describe '.start attributes' do
    it 'has the expected starting state' do
      pos = PGN::Position.start
      expect(pos.player).to eq(:white)
      expect(pos.castling).to eq(%w[K Q k q])
      expect(pos.en_passant).to be_nil
      expect(pos.halfmove).to eq(0)
      expect(pos.fullmove).to eq(1)
    end
  end

  describe '#next_player' do
    it 'toggles white to black and back' do
      expect(PGN::Position.start.next_player).to eq(:black)
      expect(PGN::Position.start.move('e4').next_player).to eq(:white)
    end
  end

  describe '#move' do
    it 'returns a new PGN::Position and does not mutate the source' do
      pos = PGN::Position.start
      nxt = pos.move('e4')
      expect(nxt).to be_a(PGN::Position)
      expect(nxt).not_to be(pos)
      expect(pos.board.at('e4')).to be_nil
      expect(pos.player).to eq(:white)
    end

    it 'toggles the player to move' do
      expect(PGN::Position.start.move('e4').player).to eq(:black)
      expect(PGN::Position.start.move('e4').move('e5').player).to eq(:white)
    end

    it 'updates state after 1.e4' do
      nxt = PGN::Position.start.move('e4')
      expect(nxt.en_passant).to eq('e3')
      expect(nxt.halfmove).to eq(0)
      expect(nxt.fullmove).to eq(1)
      expect(nxt.board.at('e4')).to eq('P')
      expect(nxt.board.at('e2')).to be_nil
    end

    it 'updates state after 1.e4 e5' do
      nxt = PGN::Position.start.move('e4').move('e5')
      expect(nxt.player).to eq(:white)
      expect(nxt.en_passant).to eq('e6')
      expect(nxt.fullmove).to eq(2)
    end

    it 'propagates castling restrictions' do
      fen = 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1'
      nxt = PGN::FEN.new(fen).to_position.move('O-O')
      expect(nxt.castling.sort).to eq(%w[k q])
    end
  end

  describe '#to_fen' do
    it 'round-trips the start position to FEN::INITIAL' do
      expect(PGN::Position.start.to_fen.to_s).to eq(PGN::FEN::INITIAL)
    end

    it 'round-trips an arbitrary position through FEN' do
      fen = 'r1bqkb1r/pp1p1ppp/2n1pn2/8/3NP3/2N5/PPP2PPP/R1BQKB1R w KQkq - 3 6'
      parsed = PGN::FEN.new(fen).to_position
      expect(parsed.to_fen.to_s).to eq(fen)
    end
  end
end
