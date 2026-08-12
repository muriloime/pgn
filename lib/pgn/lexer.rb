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
    WSP = /\s+/.freeze

    # Discarded: a PGN "rest of line" comment beginning with `%`.
    PGN_COMMENT = /% .*/.freeze

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
    /x.freeze

    # A brace-delimited comment, with recursive nesting via \g<1>.
    COMMENT = /
      (
        \{                           # beginning of comment
        (
          [[:print:]&&[^\\\{\}]] |   # printing characters except brace and backslash
          \n                     |
          \\\\                   |   # escaped backslashes
          \\\{|\\\}              |   # escaped braces
          \n                     |   # newlines
          \g<1>                      # recursive
        )*                           # zero or more of the above
          \}                           # end of comment
      )
    /x.freeze

    # Game termination marker.
    GAME_TERMINATION = %r{
      1-0       |    # white wins
      0-1       |    # black wins
      1\/2-1\/2 |    # draw
      \*             # ?
    }x.freeze

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
    }x.freeze

    # A move number indication, e.g. `1.`, `12.`, `1...`.
    MOVE_NUMBER = /[[:digit:]]+\.*/.freeze

    # A tag name (letters, digits, underscores).
    TAG_NAME = /[A-Za-z0-9_]+/.freeze

    # A numeric annotation glyph (`$1`) or a punctuation annotation (`?!`,
    # `!?`, `??`, ...).
    NAG = /
      \$\d+       | # dollar sign followed by an integer
      [\?!][\?!]?   # support the most used annotations directly
    /x.freeze

    # Order matters: more specific / longer tokens are tried first so that
    # e.g. `1-0` (termination) wins over `1` (move number), and `0-0`
    # (castling) wins over `0` (move number). Whitespace and `%` comments
    # are discarded (consumed but not emitted).
    RULES = [
      [:wsp,              WSP,              true],   # discarded
      [:pgn_comment,      PGN_COMMENT,      true],   # discarded
      [:comment,          COMMENT,          false],
      [:string,           STRING,           false],
      [:game_termination, GAME_TERMINATION, false],
      [:san_move,         SAN_MOVE,         false],
      [:nag,              NAG,              false],
      [:move_number,      MOVE_NUMBER,      false],
      [:tag_name,         TAG_NAME,         false],
    ].freeze.each(&:freeze)

    # Single-character literals, matched by their byte value.
    LITERAL_BYTES = {
      91 => :lbracket,   # [
      93 => :rbracket,   # ]
      40 => :lparen,     # (
      41 => :rparen,     # )
    }.freeze

    def initialize(input)
      @input = input
      @ss = StringScanner.new(input)
      @line = 1
      @game_starts = []
      @between_games = true   # at start we are "between" games
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
      until @ss.eos?
        off = @ss.pos

        if (lit = LITERAL_BYTES[@input.getbyte(off)])
          @ss.pos = off + 1
          note_token(lit, off)
          return Token.new(type: lit, value: @input.byteslice(off, 1),
                           offset: off, line: @line)
        end

        type, value = scan_one
        advance_line(value)
        if type == :wsp || type == :pgn_comment
          # discarded: keep looping without emitting
          next
        end
        note_token(type, off)
        return Token.new(type: type, value: value, offset: off, line: @line)
      end
      nil
    end

    private

    # Try each terminal rule in order; return [type, matched_string] for
    # the first match, or raise if nothing matches at the current position.
    def scan_one
      RULES.each do |(type, re, _discarded)|
        if (m = @ss.scan(re))
          return [type, m]
        end
      end
      raise UnconsumedInputError,
            "Unmatched input #{@input.byteslice(@ss.pos..).inspect} on line #{@line}"
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

    def advance_line(str)
      @line += str.count("\n")
    end
  end

  # Raised when the lexer cannot match the input at the current position.
  class UnconsumedInputError < StandardError; end
end
