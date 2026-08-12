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
    | SAN_MOVE COMMENT                    { result = MoveText.new(val[0], nil, val[1]) }
    | SAN_MOVE annotation_list            { result = MoveText.new(val[0], val[1]) }
    | SAN_MOVE annotation_list COMMENT    { result = MoveText.new(val[0], val[1], val[2]) }
    | SAN_MOVE COMMENT annotation_list   { result = MoveText.new(val[0], val[2], val[1]) }

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
    t = @lexer.next_token
    return [false, false] unless t
    [translate_type(t.type), t.value]
  end

  private

  def translate_type(sym)
    case sym
    when :string           then :STRING
    when :comment          then :COMMENT
    when :game_termination  then :GAME_TERMINATION
    when :san_move         then :SAN_MOVE
    when :nag              then :NAG
    when :move_number      then :MOVE_NUMBER
    when :tag_name         then :TAG_NAME
    when :lbracket         then '['
    when :rbracket         then ']'
    when :lparen           then '('
    when :rparen           then ')'
    else
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
