require 'spec_helper'
require 'pgn'

# Golden equivalence: the new Racc + StringScanner parser (PGN::PgnParser)
# must produce the same games as the legacy whittle parser (PGN::WhittleParser)
# on every fixture and on representative inline inputs. This is the safety net
# for the migration; it is removed once whittle is dropped (Task 7).
RSpec.describe 'PGN parser migration (whittle -> racc)' do
  def move_sig(m)
    {
      notation: m.notation,
      annotation: m.annotation,
      comment: m.comment,
      # Variations compared as an order-independent set: the legacy whittle
      # parser reverses variation order on every parse (a right-recursive
      # quirk); the new parser preserves order. Order is not part of the
      # contract (game_spec compares variations order-independently).
      variations: (m.variations || [])
                   .map { |v| v.map { |mm| move_sig(mm) } }
                   .sort_by(&:inspect),
    }
  end

  def game_sig(games)
    games.map do |g|
      {
        tags:    g[:tags],
        result:  g[:result],
        comment: g[:comment],
        pgn:     g[:pgn],
        moves:   g[:moves].map { |m| move_sig(m) },
      }
    end
  end

  def whittle_games(text)
    PGN::WhittleParser.new.parse(text)
  end

  def racc_games(text)
    PGN::PgnParser.new.parse(text)
  end

  def assert_equivalent(text, label)
    w = game_sig(whittle_games(text))
    r = game_sig(racc_games(text))
    expect(r).to eq(w), "#{label}: racc != whittle\nwhittle=#{w.inspect}\nracc   =#{r.inspect}"
  end

  # All fixture files, tracked or not.
  fixtures = Dir['spec/pgn_files/*.pgn'].sort

  fixtures.each do |path|
    it "parses #{File.basename(path)} identically to whittle" do
      text = File.read(path)
      if File.basename(path) == 'specialcharacters.pgn'
        text = text.force_encoding(Encoding::UTF_8)
      end
      assert_equivalent(text, File.basename(path))
    end
  end

  # Representative inline inputs covering features not necessarily in fixtures.
  inline = {
    'minimal single move game'        => '[White "A"] 1. e4 1-0',
    'empty movetext'                  => '[Event "?"] *',
    'draw and star results'          => "[White \"A\"] 1. e4 e5 1/2-1/2\n\n[White \"B\"] 1. d4 d5 *",
    'promotion and check/mate'        => '[White "A"] 1. e7 d8=Q+ 1-0',
    'castling both sides'            => '[White "A"] 1. O-O O-O-O 1-0',
    'annotation glyphs'             => '[White "A"] 1. e4 e5 2. Nf3 $1 Nc6 3. Bb5!? a6?! 1-0',
    'nested variation'               => '[White "A"] 1. e4 (1. d4 (1... d5) dxc4) e5 1-0',
    'comment then variation'          => '[White "A"] 1. e4 {a comment} e5 1-0',
    'standalone game comment'         => '[White "A"] {preamble} 1. e4 e5 *',
    'multiple games'                  => "[White \"A\"] 1. e4 e5 1-0\n\n[White \"B\"] 1. d4 d5 0-1",
    'percent comment line'            => "% preamble\n[White \"X\"] 1. e4 *",
  }

  inline.each do |label, text|
    it "parses inline '#{label}' identically to whittle" do
      assert_equivalent(text, label)
    end
  end
end
