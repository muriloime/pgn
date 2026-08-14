require "spec_helper"

RSpec.describe PGN::Bitboard::Engine do
  let(:startpos) { "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" }

  # The native extension is optional from the gem's perspective; skip the
  # whole suite if it isn't compiled in this environment.
  unless PGN::Bitboard.const_defined?(:Engine)
    skip "native extension PGN::Bitboard::Engine not compiled"
  end

  it "perfts the start position" do
    e = described_class.new(startpos)
    expect(e.perft(1)).to eq(20)
    expect(e.perft(2)).to eq(400)
    expect(e.perft(3)).to eq(8902)
    expect(e.perft(4)).to eq(197281)
  end

  it "perfts Kiwipete" do
    e = described_class.new("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
    expect(e.perft(1)).to eq(48)
    expect(e.perft(3)).to eq(97862)
  end

  it "raises on a bad FEN" do
    expect { described_class.new("not a fen") }.to raise_error(ArgumentError)
  end
end
