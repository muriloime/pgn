# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PGN::EPD do
  let(:start_epd) { 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -' }

  it 'parses the placement/side/castling/ep fields' do
    epd = PGN::EPD.new(start_epd)
    pos = epd.to_position
    expect(pos.player).to eq(:white)
    expect(pos.castling).to eq(%w[K Q k q])
    expect(pos.en_passant).to be_nil
    expect(pos.halfmove).to eq(0)
    expect(pos.fullmove).to eq(1)
  end

  it 'round-trips a simple position' do
    expect(PGN::EPD.new(start_epd).to_s).to eq(start_epd)
  end

  it 'preserves trailing operation fields verbatim' do
    epd = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - bm e4; id "start";'
    expect(PGN::EPD.new(epd).to_s).to eq(epd)
    expect(PGN::EPD.new(epd).ops).to eq('bm e4; id "start";')
  end

  it 'normalizes nil castling/ep to "-"' do
    epd = PGN::EPD.new('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w')
    expect(epd.castling).to eq('-')
    expect(epd.en_passant).to eq('-')
  end
end

RSpec.describe PGN::FEN, '#to_epd' do
  it 'drops the move counters from the start position' do
    expect(PGN::FEN.start.to_epd).to eq('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -')
  end

  it 'preserves castling and en passant' do
    fen = 'rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3'
    expect(PGN::FEN.new(fen).to_epd).to eq('rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6')
  end
end
