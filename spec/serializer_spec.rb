require 'spec_helper'

describe PGN::Serializer do
  describe '#to_s' do
    it 'serializes a simple game with tags and result' do
      game = PGN::Game.new(%w[e4 e5], { 'White' => 'A', 'Black' => 'B' }, '1-0')
      expected = "[White \"A\"]\n[Black \"B\"]\n\n1. e4 e5 1-0\n"
      expect(PGN::Serializer.new(game).to_s).to eq(expected)
    end

    it 'synthesizes a Result tag when there are no tags' do
      game = PGN::Game.new(%w[e4 e5])
      expected = "[Result \"*\"]\n\n1. e4 e5 *\n"
      expect(PGN::Serializer.new(game).to_s).to eq(expected)
    end

    it 'serializes an empty game as just the result' do
      game = PGN::Game.new([], nil, '*')
      expected = "[Result \"*\"]\n\n*\n"
      expect(PGN::Serializer.new(game).to_s).to eq(expected)
    end

    it 'emits * when there is no result' do
      game = PGN::Game.new(%w[e4 e5], { 'White' => 'A' })
      expect(PGN::Serializer.new(game).to_s).to end_with("1. e4 e5 *\n")
    end

    it 'escapes backslashes and quotes in tag values' do
      game = PGN::Game.new(%w[e4], { 'White' => 'A "B" \\C' }, '1-0')
      expect(PGN::Serializer.new(game).to_s).to start_with("[White \"A \\\"B\\\" \\\\C\"]\n")
    end
  end
end
