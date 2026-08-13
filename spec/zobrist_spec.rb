# frozen_string_literal: true

require 'spec_helper'

describe PGN::Zobrist do
  it 'exposes table, side, castling, and ep_file constants' do
    expect(PGN::Zobrist::TABLE).to be_a(Hash)
    expect(PGN::Zobrist::TABLE.keys.sort).to eq(%w[B K N P Q R b k n p q r].sort)
    expect(PGN::Zobrist::TABLE['P'].length).to eq(128)
    expect(PGN::Zobrist::SIDE).to be_an(Integer)
    expect(PGN::Zobrist::CASTLING).to be_a(Hash)
    expect(PGN::Zobrist::CASTLING.keys.sort).to eq(%w[K Q k q].sort)
    expect(PGN::Zobrist::EP_FILE.length).to eq(8)
  end

  it 'seeds the starting position to a stable integer' do
    first  = PGN::Zobrist.seed(PGN::Board.start, :white, %w[K Q k q], nil)
    second = PGN::Zobrist.seed(PGN::Board.start, :white, %w[K Q k q], nil)
    expect(first).to eq(second)
    expect(first).to be_an(Integer)
  end

  it 'differs when the side to move changes' do
    white_to_move = PGN::Zobrist.seed(PGN::Board.start, :white, %w[K Q k q], nil)
    black_to_move = PGN::Zobrist.seed(PGN::Board.start, :black, %w[K Q k q], nil)
    expect(white_to_move).not_to eq(black_to_move)
  end

  it 'differs when castling rights change' do
    full = PGN::Zobrist.seed(PGN::Board.start, :white, %w[K Q k q], nil)
    no_k = PGN::Zobrist.seed(PGN::Board.start, :white, %w[Q k q], nil)
    expect(full).not_to eq(no_k)
  end

  it 'differs when an en-passant file is present vs absent' do
    with_ep = PGN::Zobrist.seed(PGN::Board.start, :white, %w[K Q k q], 'e3')
    no_ep   = PGN::Zobrist.seed(PGN::Board.start, :white, %w[K Q k q], nil)
    expect(with_ep).not_to eq(no_ep)
  end

  it 'is deterministic across processes (frozen constants)' do
    expect(PGN::Zobrist::TABLE).to be_frozen
    expect(PGN::Zobrist::CASTLING).to be_frozen
    expect(PGN::Zobrist::EP_FILE).to be_frozen
  end
end
