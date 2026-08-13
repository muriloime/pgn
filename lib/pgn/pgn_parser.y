# frozen_string_literal: true

class PGN::PgnParser

token STRING COMMENT GAME_TERMINATION SAN_MOVE NAG MOVE_NUMBER TAG_NAME

rule

  pgn_database:
      /* empty */                         { result = [] }
    | pgn_database pgn_game               { result = val[0] << val[1] }

  pgn_game:
      tag_section movetext_section
      {
        result = val[1].pop
        result = {
          tags:    val[0],
          result:  result,
          moves:   val[1],
          pgn:     nil,
          comment: (@game_comment.tap { @game_comment = nil }),
        }
      }

  tag_section:
      tag_pair                            { result = val[0] }
    | tag_pair tag_section
      {
        # Right-recursive with section.merge(pair) reproduces the legacy
        # whittle parser's tag semantics exactly: reverse source insertion
        # order, and first-occurrence-wins on duplicate keys. This keeps
        # serialized tag order byte-compatible with the legacy behavior.
        result = val[1].merge(val[0])
      }

  tag_pair:
      '[' TAG_NAME STRING ']'              { result = { val[1] => val[2][1...-1] } }

  movetext_section:
      element_sequence GAME_TERMINATION   { result = val[0] << val[1] }

  element_sequence:
      /* empty */                         { result = [] }
    | element_sequence element
      {
        result = val[1].nil? ? val[0] : val[0] << val[1]
      }

  element:
      MOVE_NUMBER                         { result = nil }
    | san_move_annotated
    | san_move_annotated variation_list
      {
        result = val[0]
        result.variations = val[1]
        result
      }
    | COMMENT
      {
        # A standalone comment (not attached to a move) becomes the game
        # comment; the last such comment in the game wins.
        @game_comment = val[0]
        result = nil
      }

  san_move_annotated:
      SAN_MOVE                            { result = MoveText.new(val[0]) }
    | SAN_MOVE move_trailer                { result = MoveText.new(val[0], *val[1]) }

  # [annotation_list, comment], in whichever order they followed the move.
  move_trailer:
      COMMENT                             { result = [nil, val[0]] }
    | annotation_list                      { result = [val[0], nil] }
    | annotation_list COMMENT              { result = [val[0], val[1]] }
    | COMMENT annotation_list              { result = [val[1], val[0]] }

  annotation_list:
      NAG                                 { result = [val[0]] }
    | annotation_list NAG                  { result = val[0] << val[1] }

  variation_list:
      variation                           { result = [val[0]] }
    | variation variation_list
      {
        # Right-recursive prepend reproduces the legacy whittle parser's
        # variation-order reversal on every parse. This keeps parsed-game
        # serialization byte-compatible with the legacy behavior; the quirk
        # can be fixed in a separate change.
        result = val[1] << val[0]
      }

  variation:
      '(' element_sequence ')'            { result = val[1] }

---- inner

  def parse(input)
    @lexer = PGN::Lexer.new(input)
    @input = input
    games = do_parse
    assign_pgn!(games)
    games
  end

  def next_token
    pair = @lexer.next_token_pair
    return [false, false] unless pair
    type, value = pair
    [translate_type(type), value]
  end

  private

  # Punctuation tokens are racc'd by their literal character (taken from
  # PGN::Lexer::LITERAL_BYTES, the single source of truth for those
  # characters); everything else is racc'd by the upcased lexer symbol.
  # A complete frozen lookup keeps this a plain hash read for every token
  # instead of allocating two Strings (`to_s` + `upcase`) per token.
  TOKEN_TRANSLATIONS = PGN::Lexer::LITERAL_BYTES.values.to_h.merge(
    string: :STRING, comment: :COMMENT, game_termination: :GAME_TERMINATION,
    san_move: :SAN_MOVE, nag: :NAG, move_number: :MOVE_NUMBER, tag_name: :TAG_NAME
  ).freeze

  def translate_type(sym)
    TOKEN_TRANSLATIONS.fetch(sym) do
      raise "PGN::Lexer produced an unknown token type: #{sym.inspect}"
    end
  end

  # Slice the verbatim raw PGN text per game out of the original input using
  # the per-game content-start byte offsets recorded by the lexer.
  #
  # Game 0 spans from byte 0; game k (k >= 1) spans from its first
  # non-discarded token's offset; each game ends where the next game begins
  # (or at EOF for the last game). Leading/trailing discarded tokens (a
  # game's leading `%` comment, or the whitespace between games) fold into
  # the adjacent game's span, reproducing the legacy accumulator output.
  def assign_pgn!(games)
    starts = @lexer.game_starts
    total  = @input.bytesize
    games.each_with_index do |game, k|
      start = (k == 0) ? 0 : starts[k]
      fin   = (k + 1 < games.length) ? starts[k + 1] : total
      game[:pgn] = @input.byteslice(start...fin)
    end
  end
