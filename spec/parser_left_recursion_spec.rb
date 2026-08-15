# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'left-recursive parser list rules' do
  let(:pgn) do
    +<<~PGN
      [Event "A"]
      [Site "B"]
      [Event "C"]
      [White "W"]
      [Black "X"]

      1. e4 (1...c5 (1...d5)) (1...e5) *
    PGN
  end
  let(:game) { PGN.parse(pgn).first }

  it 'preserves the legacy reversed tag order' do
    expect(game.tags.keys).to eq(%w[Black White Event Site])
  end

  it 'keeps first-occurrence-wins on duplicate tags' do
    expect(game.tags['Event']).to eq('A')
  end

  it 'preserves the legacy reversed variation order' do
    variations = game.moves.first.variations.map { |v| v.map(&:notation) }
    expect(variations).to eq([%w[e5], %w[c5]])
  end

  it 'keeps nested variations inside their parent' do
    c5 = game.moves.first.variations.last
    expect(c5.map(&:notation)).to eq(%w[c5])
    expect(c5.first.variations.map { |v| v.map(&:notation) }).to eq([%w[d5]])
  end
end
