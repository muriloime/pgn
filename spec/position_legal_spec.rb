# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PGN::Position, '#legal?' do
  skip 'native extension PGN::Bitboard::Engine not compiled' unless PGN::Bitboard.const_defined?(:Engine)

  let(:start) { PGN::Position.start }

  it 'accepts SAN pawn moves' do
    expect(start.legal?('e4')).to be(true)
    expect(start.legal?('d4')).to be(true)
    expect(start.legal?('e5')).to be(false) # no pawn on e5 can move
  end

  it 'accepts SAN piece moves' do
    expect(start.legal?('Nf3')).to be(true)
    expect(start.legal?('Nc3')).to be(true)
    expect(start.legal?('Nb1')).to be(false) # no piece can move to b1 from start
  end

  it 'accepts UCI strings' do
    expect(start.legal?('e2e4')).to be(true)
    expect(start.legal?('e2e5')).to be(false)
    expect(start.legal?('g1f3')).to be(true)
    expect(start.legal?('b1a3')).to be(true) # knight on b1 can reach a3
    expect(start.legal?('b1b3')).to be(false) # knights do not move two squares
  end

  it 'accepts SAN with check/mate suffixes' do
    # Scholar's mate position before the queen move: 1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6?? 4. Qxf7#
    pos = PGN::FEN.new('r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4').to_position
    expect(pos.legal?('Qxf7#')).to be(true)
    expect(pos.legal?('Qxf7+')).to be(true)
    expect(pos.legal?('Qxf7')).to be(true)
  end

  it 'accepts redundant disambiguation in SAN' do
    # Two knights (b1 and f1) can reach d2; "Nbd2" and "Nfd2" are both legal,
    # and the unambiguous "Nd2" is rejected as ambiguous.
    pos = PGN::FEN.new('4k3/8/8/8/8/8/8/1N3NK1 w - - 0 1').to_position
    expect(pos.legal?('Nbd2')).to be(true)
    expect(pos.legal?('Nfd2')).to be(true)
    expect(pos.legal?('Nd2')).to be(false) # ambiguous, no disambiguation
  end

  it 'handles castling SAN and UCI' do
    pos = PGN::FEN.new('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1').to_position
    expect(pos.legal?('O-O')).to be(true)
    expect(pos.legal?('O-O-O')).to be(true)
    expect(pos.legal?('e1g1')).to be(true)
    expect(pos.legal?('e1c1')).to be(true)
  end

  it 'handles promotion SAN and UCI' do
    pos = PGN::FEN.new('8/P7/8/8/8/8/8/4k2K w - - 0 1').to_position
    expect(pos.legal?('a8=Q')).to be(true)
    expect(pos.legal?('a8=N')).to be(true)
    expect(pos.legal?('a7a8q')).to be(true)
    expect(pos.legal?('a7a8n')).to be(true)
  end

  it 'handles en passant SAN' do
    pos = PGN::FEN.new('rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3').to_position
    expect(pos.legal?('exd6')).to be(true)
    expect(pos.legal?('e5d6')).to be(true)
  end

  it 'rejects moves that leave the king in check' do
    # White king on e1, rook pinning the knight on e2 to the king along the e-file.
    pos = PGN::FEN.new('4r3/8/8/8/8/8/4N3/4K3 w - - 0 1').to_position
    expect(pos.legal?('Nf4')).to be(false) # knight moves away, king is in check from rook
  end

  it 'returns false for malformed input' do
    expect(start.legal?('z9z9')).to be(false)
    expect(start.legal?('Qxh8')).to be(false) # no legal queen move from start
    expect(start.legal?('')).to be(false)
  end

  it 'respects the side to move' do
    # Black to move; a white move should be illegal.
    pos = PGN::FEN.new('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1').to_position
    expect(pos.legal?('e4')).to be(false)
    expect(pos.legal?('e5')).to be(true)
  end
end

RSpec.describe PGN::Position, '#legal_moves_san' do
  skip 'native extension PGN::Bitboard::Engine not compiled' unless PGN::Bitboard.const_defined?(:Engine)

  it 'returns 20 sorted SAN moves for the start position' do
    sans = PGN::Position.start.legal_moves_san
    expect(sans.length).to eq(20)
    expect(sans).to eq(sans.sort)
    expect(sans).to include('e4', 'Nf3', 'd4', 'a3')
  end

  it 'includes castling and promotion SAN' do
    pos = PGN::FEN.new('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1').to_position
    sans = pos.legal_moves_san
    expect(sans).to include('O-O', 'O-O-O')
  end

  it 'produces SAN whose moves are all legal? and vice versa' do
    pos = PGN::FEN.new('r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4').to_position
    sans = pos.legal_moves_san
    uci = pos.legal_moves
    expect(sans.length).to eq(uci.length)
    expect(sans.all? { |s| pos.legal?(s) }).to be(true)
  end

  it 'round-trips: every legal UCI maps to a SAN that legal? accepts' do
    pos = PGN::FEN.new('rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3').to_position
    pos.legal_moves.each do |uci|
      from = uci[0, 2]
      to = uci[2, 2]
      promo = uci[5]
      san = PGN::Notation.san(pos, from, to, promo)
      expect(pos.legal?(san)).to be(true), "#{san} (from #{uci}) should be legal"
    end
  end
end
