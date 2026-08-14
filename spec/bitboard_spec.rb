require 'spec_helper'

RSpec.describe PGN::Bitboard::Engine do
  let(:startpos) { 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1' }

  # The native extension is optional from the gem's perspective; skip the
  # whole suite if it isn't compiled in this environment.
  skip 'native extension PGN::Bitboard::Engine not compiled' unless PGN::Bitboard.const_defined?(:Engine)

  it 'perfts the start position' do
    e = described_class.new(startpos)
    expect(e.perft(1)).to eq(20)
    expect(e.perft(2)).to eq(400)
    expect(e.perft(3)).to eq(8902)
    expect(e.perft(4)).to eq(197_281)
  end

  it 'perfts Kiwipete' do
    e = described_class.new('r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1')
    expect(e.perft(1)).to eq(48)
    expect(e.perft(3)).to eq(97_862)
  end

  it 'raises on a bad FEN' do
    expect { described_class.new('not a fen') }.to raise_error(ArgumentError)
  end

  it 'lists legal moves in sorted UCI' do
    e = described_class.new(startpos)
    moves = e.legal_moves
    expect(moves.length).to eq(20)
    expect(moves).to eq(moves.sort)
    expect(moves).to include('e2e4', 'g1f3', 'd2d4')
  end

  it 'answers legal? with UCI' do
    e = described_class.new(startpos)
    expect(e.legal?('e2e4')).to be(true)
    expect(e.legal?('e2e5')).to be(false)
    expect(e.legal?('g1f3')).to be(true)
  end

  it 'encodes promotions in legal_moves' do
    e = described_class.new('8/P7/8/8/8/8/8/4k2K w - - 0 1')
    moves = e.legal_moves
    expect(moves).to include('a7a8q', 'a7a8r', 'a7a8b', 'a7a8n')
  end

  it 'recognizes castling as legal' do
    e = described_class.new('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1')
    expect(e.legal?('e1g1')).to be(true)
    expect(e.legal?('e1c1')).to be(true)
  end
end
