# frozen_string_literal: true

require 'strscan'

module PGN
  # {PGN::Lexer} is a {StringScanner}-based tokenizer for PGN. It reuses the
  # same terminal patterns as the legacy whittle parser so tokenization is
  # byte-compatible, but performs far fewer Ruby allocations because the
  # scanning happens in the C-backed StringScanner.
  #
  # The lexer also records, per game, the byte offset of the game's first
  # non-discarded token ({#game_starts}). The parser uses these offsets to
  # slice the verbatim {PGN::Game#pgn} raw text out of the original input,
  # reproducing the legacy accumulator's output exactly.
  #
  # All offsets are byte offsets (StringScanner works in bytes); slicing is
  # done with {String#byteslice} so multibyte (UTF-8) input stays intact.
  #
  class Lexer
    Token = Struct.new(:type, :value, :offset, :line, keyword_init: true) do
      def inspect
        "#<PGN::Lexer::Token #{type.inspect} value=#{value.inspect} @#{offset} L#{line}>"
      end
    end

    # Discarded: insignificant whitespace.
    WSP = /\s+/

    # Discarded: a PGN "rest of line" comment beginning with `%`.
    PGN_COMMENT = /% .*/

    # A tag value string. Allows unescaped double-quotes inside the value
    # (a form seen in real-world PGN files) — only a bare backslash starts
    # an escape. Matches the legacy parser's relaxed string rule.
    STRING = /
      "                          # beginning of string
      (
        [[:print:]&&[^\\]] |    # printing characters except backslash
        \\\\                |    # escaped backslashes
        \\"                      # escaped quotation marks
      )*                         # zero or more of the above
      "                          # end of string
    /x

    # A brace-delimited comment, with recursive nesting via \g<1>.
    COMMENT = /
      (
        \{                           # beginning of comment
        (
          [[:print:]&&[^\\{}]] |   # printing characters except brace and backslash
          \n                     |
          \\\\                   |   # escaped backslashes
          \\\{|\\\}              |   # escaped braces
          \n                     |   # newlines
          \g<1>                      # recursive
        )*                           # zero or more of the above
          \}                           # end of comment
      )
    /x

    # Game termination marker.
    GAME_TERMINATION = %r{
      1-0       |    # white wins
      0-1       |    # black wins
      1/2-1/2 |    # draw
      \*             # ?
    }x

    # A move in standard algebraic notation (incl. castling, promotion,
    # check/mate, the `--` "don't care" move).
    SAN_MOVE = %r{
      (
        --                           |    # "don't care" move (used in variations)
        [O0](-[O0]){1,2}             |    # castling (O-O, O-O-O)
        [a-h][1-8]                   |    # pawn moves (e4, d7)
        [BKNQR][a-h1-8]?x?[a-h][1-8] |    # major piece moves w/ optional specifier
        [a-h][1-8]?x[a-h][1-8]            # pawn captures
      )
      (
        =[BNQR]                            # optional promotion (d8=Q)
      )?
      (
        \+                            |    # check (g5+)
        \#                                 # checkmate (Qe7#)
      )?
    }x

    # A move number indication, e.g. `1.`, `12.`, `1...`.
    MOVE_NUMBER = /[[:digit:]]+\.*/

    # A tag name (letters, digits, underscores).
    TAG_NAME = /[A-Za-z0-9_]+/

    # A numeric annotation glyph (`$1`) or a punctuation annotation (`?!`,
    # `!?`, `??`, ...).
    NAG = /
      \$\d+       | # dollar sign followed by an integer
      [?!][?!]?   # support the most used annotations directly
    /x

    # Order matters: more specific / longer tokens are tried first so that
    # e.g. `1-0` (termination) wins over `1` (move number), and `0-0`
    # (castling) wins over `0` (move number). Whitespace and `%` comments
    # are discarded (consumed but not emitted). Beyond that constraint,
    # rules are ordered most- to least-frequent (one san_move/move_number
    # per ply/full-move vs. a handful of comments/strings per game) so the
    # common case fails the fewest regexes before matching.
    RULES = [
      [:wsp,              WSP,              true],   # discarded
      [:pgn_comment,      PGN_COMMENT,      true],   # discarded
      [:game_termination, GAME_TERMINATION, false],
      [:san_move,         SAN_MOVE,         false],
      [:move_number,      MOVE_NUMBER,      false],
      [:nag,              NAG,              false],
      [:comment,          COMMENT,          false],
      [:string,           STRING,           false],
      [:tag_name,         TAG_NAME,         false]
    ].freeze.each(&:freeze)

    # Byte-dispatch table: maps the leading byte of the next token to the
    # ordered list of RULES indices that could possibly match it. This lets
    # {#scan_one} try one or two regexes for the common tokens instead of
    # walking all nine rules in order (StringScanner#scan was ~23% of parse
    # CPU and the rule loop ~38% inclusive per profiling). The order within
    # each list mirrors RULES, so tokenization is byte-compatible with the
    # linear scan. Indices: 0 wsp, 1 pgn_comment, 2 game_termination,
    # 3 san_move, 4 move_number, 5 nag, 6 comment, 7 string, 8 tag_name.
    BYTE_DISPATCH = begin
      h = {
        9 => [0], 10 => [0], 11 => [0], 12 => [0], 13 => [0], 32 => [0], # whitespace
        37 => [1],                                            # % pgn_comment
        42 => [2],                                            # * game_termination
        34 => [7],                                            # " string
        123 => [6],                                           # { comment
        36 => [5], 63 => [5], 33 => [5], # $ ? ! nag
        48 => [2, 3, 4, 8], 49 => [2, 4, 8], # 0, 1 (term/castle/num/tag)
        95 => [8] # _ tag_name
      }
      (50..57).each { |b| h[b] = [4, 8] }                  # 2..9 move_number/tag_name
      [66, 75, 78, 79, 81, 82].each { |b| h[b] = [3, 8] }  # B K N O Q R san_move/tag
      (97..104).each { |b| h[b] = [3, 8] }                 # a-h pawn san_move/tag
      # other tag_name letters
      ((65..90).to_a + (105..122).to_a - [66, 75, 78, 79, 81, 82]).each do |b|
        h[b] = [8]
      end
      h.each_value(&:freeze)
      h.freeze
    end

    # Fallback for bytes not in BYTE_DISPATCH: try every rule in order.
    ALL_RULES = (0...RULES.length).to_a.freeze

    # Single-character literals, matched by their byte value: [type, frozen value].
    LITERAL_BYTES = {
      91 => [:lbracket, '['], # [
      93 => [:rbracket, ']'], # ]
      40 => [:lparen,   '('], # (
      41 => [:rparen,   ')'] # )
    }.freeze

    def initialize(input)
      @input = input
      @ss = StringScanner.new(input)
      @game_starts = []
      @between_games = true # at start we are "between" games
    end

    attr_reader :game_starts

    # The list of {Token}s for the whole input. Convenience for specs.
    def tokens
      result = []
      while (t = next_token)
        result << t
      end
      result
    end

    # Returns the next {Token}, or +nil+ at end of input.
    def next_token
      type, value = next_token_pair
      return nil unless type

      Token.new(type: type, value: value, offset: @last_offset,
                line: line_at(@last_offset))
    end

    # Fast path for the parser: returns [type, value] for the next
    # non-discarded token, or +nil+ at end of input. Does not allocate a
    # {Token} Struct, and +scan_one+ returns the matched string directly
    # (stashing its type/discarded flag in ivars) so the only array
    # allocated per token is the [type, value] pair Racc requires.
    def next_token_pair
      until @ss.eos?
        off = @ss.pos

        if (lit = LITERAL_BYTES[@input.getbyte(off)])
          type, value = lit
          @ss.pos = off + 1
          note_token(type, off)
          @last_offset = off
          return [type, value]
        end

        value = scan_one
        next if @scan_discarded

        note_token(@scan_type, off)
        @last_offset = off
        return [@scan_type, value]
      end
      nil
    end

    private

    # Try each terminal rule in order; return the matched string for the
    # first match (stashing its type and discarded flag in +@scan_type+ /
    # +@scan_discarded+ so the caller avoids allocating a 3-element tuple),
    # or raise if nothing matches at the current position. Uses
    # {BYTE_DISPATCH} to try only the rules that can match the leading byte.
    def scan_one
      indices = BYTE_DISPATCH[@input.getbyte(@ss.pos)] || ALL_RULES
      indices.each do |i|
        type, re, discarded = RULES[i]
        next unless (m = @ss.scan(re))

        @scan_type = type
        @scan_discarded = discarded
        return m
      end
      raise UnconsumedInputError,
            "Unmatched input #{@input.byteslice(@ss.pos..).inspect} on line #{line_at(@ss.pos)}"
    end

    # Track per-game content-start offsets for verbatim pgn slicing.
    # game_termination belongs to the current game and marks that the NEXT
    # non-discarded token begins a new game.
    def note_token(type, off)
      if type == :game_termination
        @between_games = true
      elsif @between_games
        @game_starts << off
        @between_games = false
      end
    end

    # Line number at a byte offset, computed lazily only for error messages
    # and the spec `tokens` helper. Keeping a running `@line` on the parse hot
    # path (one `str.count("\n")` per token) was ~6% of parse CPU for a value
    # the parser never reads.
    def line_at(off)
      1 + @input.byteslice(0, off).count("\n")
    end
  end

  # Raised when the lexer cannot match the input at the current position.
  class UnconsumedInputError < StandardError; end
end
