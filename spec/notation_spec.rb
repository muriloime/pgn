# frozen_string_literal: true

require 'spec_helper'

# Helper: build a Position from a FEN string.
def pos(fen)
  PGN::FEN.new(fen).to_position
end

describe PGN::Notation do
  # ------------------------------------------------------------------
  # Public API
  # ------------------------------------------------------------------
  describe '.san' do
    it 'generates a plain pawn push from coordinates' do
      expect(PGN::Notation.san(pos('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'),
                               'e2', 'e4')).to eq('e4')
    end

    it 'generates a knight move with the piece letter' do
      expect(PGN::Notation.san(pos('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'),
                               'g1', 'f3')).to eq('Nf3')
    end

    it 'generates a non-castling king walk' do
      fen = '4k3/8/8/8/8/8/8/4K3 w - - 0 1'
      expect(PGN::Notation.san(pos(fen), 'e1', 'e2')).to eq('Ke2')
    end

    it 'generates a pawn capture with the origin file' do
      fen = 'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2'
      expect(PGN::Notation.san(pos(fen), 'e4', 'd5')).to eq('exd5')
    end

    it 'generates an en passant capture' do
      fen = 'rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3'
      expect(PGN::Notation.san(pos(fen), 'e5', 'd6')).to eq('exd6')
    end

    it 'generates a pawn promotion' do
      fen = '8/P7/6k1/8/8/8/8/4K3 w - - 0 1'
      expect(PGN::Notation.san(pos(fen), 'a7', 'a8', 'q')).to eq('a8=Q')
    end

    it 'generates a capture promotion' do
      fen = '1n6/P7/6k1/8/8/8/8/4K3 w - - 0 1'
      expect(PGN::Notation.san(pos(fen), 'a7', 'b8', 'q')).to eq('axb8=Q')
    end

    it 'generates kingside castling' do
      fen = 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1'
      expect(PGN::Notation.san(pos(fen), 'e1', 'g1')).to eq('O-O')
    end

    it 'generates queenside castling' do
      fen = 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1'
      expect(PGN::Notation.san(pos(fen), 'e1', 'c1')).to eq('O-O-O')
    end

    it 'generates kingside castling for black' do
      fen = 'r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1'
      expect(PGN::Notation.san(pos(fen), 'e8', 'g8')).to eq('O-O')
    end
  end

  describe '.san disambiguation' do
    it 'disambiguates knights by file' do
      # Knights on c3 and d4 both reach b5.
      fen = 'r1bqkb1r/pp1p1ppp/2n1pn2/8/3NP3/2N5/PPP2PPP/R1BQKB1R w KQkq - 3 6'
      expect(PGN::Notation.san(pos(fen), 'd4', 'b5')).to eq('Ndb5')
      expect(PGN::Notation.san(pos(fen), 'c3', 'b5')).to eq('Ncb5')
    end

    it 'disambiguates rooks by rank when on the same file' do
      # White rooks on a1 and a8 both reach a4 (file a clear).
      fen = 'R7/8/8/4k3/8/8/8/R3K3 w - - 0 1'
      expect(PGN::Notation.san(pos(fen), 'a1', 'a4')).to eq('R1a4')
      expect(PGN::Notation.san(pos(fen), 'a8', 'a4')).to eq('R8a4')
    end

    it 'disambiguates queens by full square when file and rank both clash' do
      # Queens on c1, f1, f4 all reach c4. The f1 queen shares file f with
      # f4 and rank 1 with c1, so only the full square disambiguates.
      fen = '7k/8/8/8/5Q2/8/8/2Q2Q1K w - - 0 1'
      expect(PGN::Notation.san(pos(fen), 'f1', 'c4')).to eq('Qf1c4')
    end

    it 'omits disambiguation when only one piece can legally move there' do
      # Two knights both pseudo-reach d2, but the e4 knight is pinned
      # on the e-file (moving it exposes the king on e1 to the rook on e8),
      # so only the b1 knight can legally play Nd2 — no disambiguation.
      fen = '4r2k/8/8/8/4N3/8/8/1N2K3 w - - 0 1'
      expect(PGN::Notation.san(pos(fen), 'b1', 'd2')).to eq('Nd2')
    end
  end

  describe '.san check and checkmate suffixes' do
    it 'appends + for a checking move' do
      fen = '7k/8/8/8/8/8/6R1/6K1 w - - 0 1'
      expect(PGN::Notation.san(pos(fen), 'g2', 'g8')).to eq('Rg8+')
    end

    it 'appends # for a checkmating move' do
      fen = '6k1/5ppp/8/8/8/8/8/R6K w - - 0 1'
      expect(PGN::Notation.san(pos(fen), 'a1', 'a8')).to eq('Ra8#')
    end

    it 'appends # to a promotion that gives checkmate' do
      # White pawn b7 promotes with check on a king cornered on h8.
      fen = '7k/1P6/8/8/8/8/8/6K1 w - - 0 1'
      expect(PGN::Notation.san(pos(fen), 'b7', 'b8', 'q')).to eq('b8=Q+')
    end

    it 'does not append a suffix for a quiet move' do
      fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
      expect(PGN::Notation.san(pos(fen), 'd2', 'd4')).to eq('d4')
    end
  end

  describe '.san_from_fen' do
    it 'computes SAN directly from a FEN string' do
      expect(PGN::Notation.san_from_fen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
                                        'e2', 'e4')).to eq('e4')
    end

    it 'computes SAN for black to move' do
      fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1'
      expect(PGN::Notation.san_from_fen(fen, 'd7', 'd5')).to eq('d5')
    end
  end
end
