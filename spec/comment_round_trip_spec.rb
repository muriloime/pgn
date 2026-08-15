# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'comment round-tripping' do
  it 'round-trips nested braces through parse -> serialize -> parse' do
    input = +"[White \"A\"]\n\n1. e4 {this {is a} nested {comment}} *\n"
    g1 = PGN.parse(input, Encoding::UTF_8).first
    g2 = PGN.parse(g1.to_pgn, Encoding::UTF_8).first
    expect(g2.moves.first.comment).to eq(g1.moves.first.comment)
    expect(g2.moves.first.comment).to eq('this {is a} nested {comment}')
  end

  it 'is stable: serialize -> parse -> serialize is idempotent' do
    input = +"[White \"A\"]\n\n1. e4 {this {is a} nested {comment}} *\n"
    once = PGN.parse(input, Encoding::UTF_8).first.to_pgn
    twice = PGN.parse(once, Encoding::UTF_8).first.to_pgn
    expect(twice).to eq(once)
  end

  it 'round-trips escaped braces and backslashes' do
    input = +"[White \"A\"]\n\n1. e4 {a \\{literal\\} back\\\\slash} *\n"
    g = PGN.parse(input, Encoding::UTF_8).first
    expect(g.moves.first.comment).to eq('a {literal} back\\slash')
    reparsed = PGN.parse(g.to_pgn, Encoding::UTF_8).first
    expect(reparsed.moves.first.comment).to eq(g.moves.first.comment)
  end

  it 'round-trips the nested_comments fixture comment body' do
    input = File.binread('spec/pgn_files/nested_comments.pgn')
    g = PGN.parse(input, Encoding::UTF_8).first
    reparsed = PGN.parse(g.to_pgn, Encoding::UTF_8).first
    expect(reparsed.moves.map(&:comment)).to eq(g.moves.map(&:comment))
  end
end
