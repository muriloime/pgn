# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'UCI-style castling normalization' do
  let(:fen) { 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1' }
  let(:pos) { PGN::FEN.new(fen).to_position }

  it 'parses 0-0 / 0-0-0 the same as O-O / O-O-O in PGN::Move' do
    expect(PGN::Move.new('0-0', :white).castle).to eq('K')
    expect(PGN::Move.new('0-0-0', :white).castle).to eq('Q')
    expect(PGN::Move.new('0-0', :black).castle).to eq('k')
    expect(PGN::Move.new('0-0-0', :black).castle).to eq('q')
    expect(PGN::Move.new('0-0', :white).piece).to be_nil
  end

  it 'normalizes parsed 0-0 movetext to O-O on a game' do
    game = PGN::Game.new(%w[0-0])
    expect(game.moves.first.notation).to eq('O-O')
  end

  it 'Notation.san produces O-O / O-O-O for the king two-file moves' do
    expect(PGN::Notation.san(pos, 'e1', 'g1')).to eq('O-O')
    expect(PGN::Notation.san(pos, 'e1', 'c1')).to eq('O-O-O')
  end

  it 'Position#legal? accepts both O-O and UCI e1g1 castling' do
    expect(pos.legal?('O-O')).to be(true)
    expect(pos.legal?('O-O-O')).to be(true)
    expect(pos.legal?('e1g1')).to be(true)
    expect(pos.legal?('e1c1')).to be(true)
  end

  it 'serializes castling as O-O, never 0-0' do
    game = PGN::Game.new(%w[e4 e5 O-O])
    expect(game.to_pgn).to include('O-O')
    expect(game.to_pgn).not_to include('0-0')
  end
end
