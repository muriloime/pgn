# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PGN::MoveText, '#clean_text' do
  it 'strips a single outermost brace pair' do
    mt = PGN::MoveText.new('e4', nil, '{a comment}')
    expect(mt.comment).to eq('a comment')
  end

  it 'is idempotent on a nested-brace comment' do
    mt = PGN::MoveText.new('e4', nil, '{a {b} c}')
    once = mt.comment
    # Re-running clean_text (as MoveText.new would) must not strip the inner braces.
    twice = PGN::MoveText.new('e4', nil, once).comment
    expect(twice).to eq(once)
    expect(twice).to eq('a {b} c')
  end

  it 'collapses whitespace and strips' do
    mt = PGN::MoveText.new('e4', nil, "{  multi\nline  }")
    expect(mt.comment).to eq('multi line')
  end

  it 'returns nil for a nil comment' do
    expect(PGN::MoveText.new('e4').comment).to be_nil
  end
end

RSpec.describe PGN::Game, '#moves= with braced comments' do
  it 'reuses a MoveText unchanged when no castling fix is needed' do
    mt = PGN::MoveText.new('e4', nil, 'a {b} c')
    game = PGN::Game.new([mt])
    expect(game.moves.first).to be(mt)
    expect(game.moves.first.comment).to eq('a {b} c')
  end

  it 'rebuilds without corrupting a nested-brace comment when fixing castling' do
    mt = PGN::MoveText.new('0-0', nil, 'a {b} c')
    game = PGN::Game.new([mt])
    expect(game.moves.first.notation).to eq('O-O')
    expect(game.moves.first.comment).to eq('a {b} c')
  end
end
