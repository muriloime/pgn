module PGN
  # {PGN::Serializer} converts a {PGN::Game} into a canonical PGN string.
  #
  # Serialization is purely structural: it reads tags, moves, comments,
  # annotations, variations, and result from the game and emits valid PGN
  # without replaying any moves on a board. Move numbering state is seeded
  # from `game.starting_position` so games starting from a FEN tag (e.g.
  # with black to move) are numbered correctly.
  #
  # @see PGN::Game#to_pgn
  #
  class Serializer
    # @param game [PGN::Game] the game to serialize
    def initialize(game)
      @game = game
    end

    # @return [String] a canonical PGN string ending with a trailing newline
    def to_s
      tag_section + "\n\n" + movetext_section + "\n"
    end

    private

    # Tag section: one tag pair per line in the order of `game.tags`. If
    # `tags` is nil or empty, synthesize a `[Result "..."]` tag so the output
    # stays parseable by the current grammar (which requires at least one
    # tag pair).
    def tag_section
      tags = @game.tags
      if tags.nil? || tags.empty?
        %([Result "#{result_token}"])
      else
        tags.map { |key, value| %([#{key} "#{escape_tag(value)}"]) }.join("\n")
      end
    end

    # Movetext section: optional game comment, then the move line, then the
    # result, all joined by spaces.
    def movetext_section
      tokens = []
      if @game.comment && !@game.comment.empty?
        tokens << "{ #{escape_comment(@game.comment)} }"
      end
      line = emit_line(@game.moves, starting_fullmove, starting_player)
      tokens << line unless line.empty?
      tokens << result_token
      tokens.join(" ")
    end

    # The result token: the game's result if present and non-empty, else "*".
    def result_token
      (@game.result.nil? || @game.result.empty?) ? "*" : @game.result
    end

    # Emit a single line (mainline or variation) of movetext, tracking the
    # numbering state described in the design spec.
    def emit_line(moves, fullmove, player)
      tokens = []
      prev_player = nil
      prev_had_extras = false

      moves.each do |move|
        if player == :white
          tokens << "#{fullmove}."
          tokens << move_token(move, fullmove, player)
        else # black
          need_number = prev_player.nil? || prev_had_extras || prev_player != :white
          tokens << "#{fullmove}..." if need_number
          tokens << move_token(move, fullmove, player)
        end

        prev_player = player
        prev_had_extras = has_extras?(move)
        fullmove += 1 if player == :black
        player = opposite(player)
      end

      tokens.join(" ")
    end

    # A move token: notation plus trailing extras (annotation, comment,
    # variations), joined by spaces. Variations are serialized recursively
    # from the position *before* the move (the same fullmove/player).
    def move_token(move, fullmove, player)
      parts = [move.notation]
      (move.annotation || []).each { |a| parts << a }
      if move.comment && !move.comment.empty?
        parts << "{ #{escape_comment(move.comment)} }"
      end
      (move.variations || []).each do |variation|
        parts << "(#{emit_line(variation, fullmove, player)})"
      end
      parts.join(" ")
    end

    # Whether a move carries any annotation, comment, or variation.
    def has_extras?(move)
      (!move.annotation.nil? && !move.annotation.empty?) ||
        (!move.comment.nil? && !move.comment.empty?) ||
        (!move.variations.nil? && !move.variations.empty?)
    end

    def starting_fullmove
      @game.starting_position.fullmove
    end

    def starting_player
      @game.starting_position.player
    end

    def opposite(player)
      player == :white ? :black : :white
    end

    # Escape backslashes and double quotes for a tag value. The block form of
    # gsub is used so the replacement string is taken literally (gsub's
    # string replacement would otherwise re-interpret backslashes).
    def escape_tag(value)
      value.to_s
           .gsub("\\") { "\\\\" }
           .gsub('"') { "\\\"" }
    end

    # Escape backslashes and braces for a comment body (block form, so the
    # replacement string is taken literally — gsub's string replacement
    # would otherwise re-interpret backslashes).
    #
    # Note: the current parser's `MoveText#clean_text` does not unescape,
    # so comments containing literal braces (e.g. the `nested_comments.pgn`
    # fixture) will not round-trip byte-for-byte until parser improvements
    # (sub-project 3) add unescaping. This matches the design spec's
    # acknowledged v1 limitation.
    def escape_comment(text)
      text.to_s
          .gsub("\\") { "\\\\" }
          .gsub("{") { "\\{" }
          .gsub("}") { "\\}" }
    end
  end
end
