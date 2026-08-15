# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PGN::Position, 'outcome' do
  skip 'native extension PGN::Bitboard::Engine not compiled' unless PGN::Bitboard.const_defined?(:Engine)

  it 'is nil for the start position' do
    expect(PGN::Position.start.outcome).to be_nil
  end

  it 'detects checkmate (fool\'s mate)' do
    pos = PGN::FEN.new('rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3').to_position
    expect(pos.outcome).to eq(:checkmate)
    expect(pos.checkmate?).to be(true)
    expect(pos.stalemate?).to be(false)
  end

  it 'detects stalemate' do
    pos = PGN::FEN.new('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1').to_position
    expect(pos.outcome).to eq(:stalemate)
    expect(pos.stalemate?).to be(true)
    expect(pos.in_check?).to be(false)
  end

  it 'detects insufficient material: K vs K' do
    pos = PGN::FEN.new('4k3/8/8/8/8/8/8/4K3 w - - 0 1').to_position
    expect(pos.insufficient_material?).to be(true)
    expect(pos.outcome).to eq(:draw)
  end

  it 'detects insufficient material: K+B vs K' do
    pos = PGN::FEN.new('4k3/8/8/8/8/8/8/3BK3 w - - 0 1').to_position
    expect(pos.insufficient_material?).to be(true)
  end

  it 'detects insufficient material: K+N vs K' do
    pos = PGN::FEN.new('4k3/8/8/8/8/8/8/3NK3 w - - 0 1').to_position
    expect(pos.insufficient_material?).to be(true)
  end

  it 'does not consider K+Q vs K insufficient' do
    pos = PGN::FEN.new('4k3/8/8/8/8/8/8/3QK3 w - - 0 1').to_position
    expect(pos.insufficient_material?).to be(false)
  end

  it 'detects the 50-move rule' do
    pos = PGN::FEN.new('4k3/8/8/8/8/8/8/4K3 w - - 100 60').to_position
    expect(pos.fifty_move?).to be(true)
    expect(pos.outcome).to eq(:draw)
  end

  it 'does not trigger 50-move before 100 halfmoves' do
    pos = PGN::FEN.new('4k3/8/8/8/8/8/8/4K3 w - - 99 60').to_position
    expect(pos.fifty_move?).to be(false)
  end
end

RSpec.describe PGN::Game, 'outcome' do
  skip 'native extension PGN::Bitboard::Engine not compiled' unless PGN::Bitboard.const_defined?(:Engine)

  it 'is nil for a game in progress' do
    game = PGN::Game.new(%w[e4 e5 Nf3 Nc6])
    expect(game.outcome).to be_nil
  end

  it 'detects a checkmate game (scholar\'s mate)' do
    game = PGN::Game.new(%w[e4 e5 Bc4 Nc6 Qh5 Nf6 Qxf7])
    expect(game.outcome).to eq(:checkmate)
  end

  it 'detects a stalemate game' do
    # Black king h8, white queen f7, white king g6; black to move is stalemated.
    game = PGN::Game.new(
      %w[],
      { 'FEN' => '7k/5Q2/6K1/8/8/8/8/8 b - - 0 1' },
      '1/2-1/2'
    )
    expect(game.outcome).to eq(:stalemate)
  end

  it 'detects threefold repetition' do
    # 1. Nf3 Nf6 2. Ng1 Ng8 repeats the start position three times.
    game = PGN::Game.new(%w[Nf3 Nf6 Ng1 Ng8 Nf3 Nf6 Ng1 Ng8])
    expect(game.threefold?).to be(true)
    expect(game.outcome).to eq(:draw)
  end

  it 'does not claim threefold without three repeats' do
    game = PGN::Game.new(%w[Nf3 Nf6 Ng1])
    expect(game.threefold?).to be(false)
  end
end
