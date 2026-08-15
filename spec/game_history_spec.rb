# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PGN::Game, 'mutable history' do
  skip 'native extension PGN::Bitboard::Engine not compiled' unless PGN::Bitboard.const_defined?(:Engine)

  let(:game) { PGN::Game.new(%w[e4 e5]) }

  it 'appends a move with #push and invalidates the position cache' do
    expect(game.positions.length).to eq(3) # start, e4, e5
    game.push('Nf3')
    expect(game.moves.map(&:notation)).to eq(%w[e4 e5 Nf3])
    expect(game.positions.length).to eq(4)
    expect(game.current_position.board.at('f3')).to eq('N')
  end

  it 'rejects an illegal move with ArgumentError' do
    expect { game.push('e5') }.to raise_error(ArgumentError, /illegal move/)
    expect(game.moves.length).to eq(2) # unchanged
  end

  it 'removes and returns the last move with #pop' do
    last = game.pop
    expect(last.notation).to eq('e5')
    expect(game.moves.map(&:notation)).to eq(%w[e4])
    expect(game.positions.length).to eq(2)
  end

  it 'returns nil when popping an empty game' do
    empty = PGN::Game.new([])
    expect(empty.pop).to be_nil
  end

  it 'normalizes castling on push' do
    game = PGN::Game.new(%w[e4 e5 Nf3 Nc6 Bc4 Bc5 O-O Nf6 d3])
    game.push('0-0')
    expect(game.moves.last.notation).to eq('O-O')
  end

  it 'lets a freshly pushed game reach a checkmate outcome' do
    game = PGN::Game.new(%w[e4 e5 Bc4 Nc6 Qh5 Nf6])
    game.push('Qxf7#')
    expect(game.outcome).to eq(:checkmate)
  end
end
