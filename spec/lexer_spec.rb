require 'spec_helper'
require 'pgn/lexer'

RSpec.describe PGN::Lexer do
  def lex(input)
    PGN::Lexer.new(input).tokens
  end

  it 'returns nil on empty input' do
    expect(PGN::Lexer.new('').next_token).to be_nil
  end

  it 'discards whitespace' do
    toks = lex("   \n\t  e4")
    expect(toks.map { |t| [t.type, t.value] }).to eq([[:san_move, 'e4']])
  end

  it 'discards % rest-of-line comments' do
    toks = lex("% a comment line\n[Event \"X\"]")
    expect(toks.map(&:type)).to eq(%i[lbracket tag_name string rbracket])
  end

  it 'tokenizes the four single-character literals' do
    toks = lex('[]()')
    expect(toks.map { |t| [t.type, t.value] }).to eq(
      [[:lbracket, '['], [:rbracket, ']'], [:lparen, '('], [:rparen, ')']]
    )
  end

  it 'tokenizes a tag pair' do
    toks = lex('[White "Kasparov"]')
    expect(toks.map { |t| [t.type, t.value] }).to eq(
      [[:lbracket, '['], [:tag_name, 'White'], [:string, '"Kasparov"'], [:rbracket, ']']]
    )
  end

  it 'allows unescaped double-quotes inside a string value' do
    toks = lex('[Event "IRT BLITZ "Sub Zonal""]')
    expect(toks[2].value).to eq('"IRT BLITZ "Sub Zonal""')
  end

  it 'handles an escaped backslash in a string' do
    input = %([X "a\\\\b"])
    expect(lex(input)[2].value).to eq(%("a\\\\b"))
  end

  it 'handles an escaped quote in a string' do
    input = %([X "a\\"b"])
    expect(lex(input)[2].value).to eq(%("a\\"b"))
  end

  it 'tokenizes a brace comment including newlines' do
    toks = lex("{line one\nline two}")
    expect(toks.size).to eq(1)
    expect(toks[0].type).to eq(:comment)
    expect(toks[0].value).to eq("{line one\nline two}")
  end

  it 'tokenizes nested brace comments recursively' do
    toks = lex('{outer {inner} tail}')
    expect(toks[0].value).to eq('{outer {inner} tail}')
  end

  it 'tokenizes all game terminations' do
    %w[1-0 0-1 1/2-1/2 *].each do |term|
      expect(lex(term).map { |t| [t.type, t.value] }).to eq([[:game_termination, term]])
    end
  end

  it 'prefers a game termination over a move number (1-0, 0-1)' do
    expect(lex('1-0')[0].type).to eq(:game_termination)
    expect(lex('0-1')[0].type).to eq(:game_termination)
  end

  it 'prefers castling (0-0) over a move number (0)' do
    t = lex('0-0')[0]
    expect(t.type).to eq(:san_move)
    expect(t.value).to eq('0-0')
  end

  it 'prefers a draw result (1/2-1/2) over a move number (1)' do
    expect(lex('1/2-1/2')[0].value).to eq('1/2-1/2')
  end

  it 'tokenizes move number indications' do
    expect(lex('1.')[0].value).to eq('1.')
    expect(lex('12.')[0].value).to eq('12.')
    expect(lex('1...')[0].value).to eq('1...')
  end

  it 'tokenizes san moves: pawn, capture, promotion, check, mate' do
    expect(lex('e4')[0].value).to eq('e4')
    expect(lex('exd5')[0].value).to eq('exd5')
    expect(lex('e8=Q')[0].value).to eq('e8=Q')
    expect(lex('Qe7+')[0].value).to eq('Qe7+')
    expect(lex('Qxf7#')[0].value).to eq('Qxf7#')
  end

  it 'tokenizes castling (O and 0 forms) and the dont-care move' do
    expect(lex('O-O')[0].value).to eq('O-O')
    expect(lex('O-O-O')[0].value).to eq('O-O-O')
    expect(lex('--')[0].value).to eq('--')
  end

  it 'tokenizes major-piece moves with disambiguation' do
    expect(lex('Nf3')[0].value).to eq('Nf3')
    expect(lex('Nef6')[0].value).to eq('Nef6')
    expect(lex('Raxc1')[0].value).to eq('Raxc1')
  end

  it 'tokenizes numeric annotation glyphs and punctuation annotations' do
    expect(lex('$4')[0].value).to eq('$4')
    expect(lex('??')[0].value).to eq('??')
    expect(lex('?!')[0].value).to eq('?!')
    expect(lex('!?')[0].value).to eq('!?')
  end

  it 'records byte offsets on every token' do
    toks = lex('1. e4 e5 1-0')
    expect(toks[0].offset).to eq(0) # "1."
    expect(toks[1].offset).to eq(3)  # "e4"
    expect(toks[2].offset).to eq(6)  # "e5"
    expect(toks[3].offset).to eq(9)  # "1-0"
  end

  it 'counts lines as it consumes newlines' do
    toks = lex("[X \"1\"]\n[Y \"2\"]")
    expect(toks.last.line).to eq(2)
  end

  it 'records per-game content-start offsets' do
    input = "[Event \"A\"]\n\n1. e4 e5 1-0\n\n[Event \"B\"]\n\n1. d4 d5 0-1"
    lex = PGN::Lexer.new(input)
    lex.tokens
    # game_starts has one entry per game (game 0's is recorded but game 0's
    # pgn span starts at 0 by construction; games 1+ start at their offset).
    expect(lex.game_starts.size).to eq(2)
    # game 1's content-start is the '[' of "[Event \"B\"]"
    second_game = input.index('[Event "B"]')
    expect(lex.game_starts[1]).to eq(second_game)
  end

  it 'tokenizes UTF-8 (multibyte) input without error' do
    input = "[Site \"HOTEL – Pereira\"]\n1. e4 e5 *\n".force_encoding(Encoding::UTF_8)
    toks = PGN::Lexer.new(input).tokens
    expect(toks[1].value).to eq('Site')
    expect(toks[2].value).to eq('"HOTEL – Pereira"')
  end

  it 'raises on unmatched input' do
    expect { lex('@bogus') }.to raise_error(PGN::UnconsumedInputError)
  end
end
