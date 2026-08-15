# frozen_string_literal: true

require 'io/console'

module PGN
  class MoveText
    attr_accessor :notation, :annotation, :comment, :variations

    def initialize(notation, annotation = nil, comment = nil, variations = [])
      @notation = notation
      @annotation = annotation
      @comment = clean_text(comment)
      @variations = variations
    end

    def ==(other)
      to_s == other.to_s
    end

    def eql?(other)
      self == other
    end

    def hash
      @notation.hash
    end

    def to_s
      @notation
    end

    def clean_text(text)
      return unless text

      text = text[1..-2] if text.start_with?('{') && text.end_with?('}')
      text.gsub(/\s+/, ' ').strip
    end
  end

  # {PGN::Game} holds all of the information about a game. It is either
  # the result of parsing a PGN file, or created by hand.
  #
  # A {PGN::Game} has an interactive {#play} method, and can also return
  # a list of positions in {PGN::Position} format or FEN.
  #
  # @!attribute tags
  #   @return [Hash<String, String>] metadata about the game
  #   @example
  #     game.tags #=> {"White" => "Kasparov", "Black" => "Deep Blue"}
  #
  # @!attribute moves
  #   @return [Array<String>] a list of the moves in standard algebraic
  #     notation
  #   @example
  #     game.moves #=> ["e4", "c5", "Nf3", "d6", "d4", "cxd4"]
  #
  # @!attribute result
  #   @return [String] the outcome of the game
  #   @example
  #     game.result #=> "1-0"
  #
  class Game
    attr_accessor :tags, :result, :pgn, :comment
    attr_reader :moves

    LEFT  = /(a|\x1B\[D)\z/
    RIGHT = /(d|\x1B\[C)\z/
    EXIT  = /(q|\x03)\z/

    # @param moves [Array<String>] a list of moves in SAN
    # @param tags [Hash<String, String>] metadata about the game
    # @param result [String] the outcome of the game
    #
    def initialize(moves, tags = nil, result = nil, pgn = nil, comment = nil)
      self.moves   = moves
      self.tags    = tags
      self.result  = result
      self.pgn     = pgn
      self.comment = comment
    end

    # @param moves [Array<String>] a list of moves in SAN
    #
    # Standardize castling moves to use O's instead of 0's
    #
    def moves=(moves)
      @moves = moves.map { |m| standardize_castling(m) }
    end

    # @return [String] a canonical PGN string for this game, ending with a
    #   trailing newline.
    #
    def to_pgn
      PGN::Serializer.new(self).to_s
    end

    def initial_fen
      tags && tags['FEN']
    end

    def starting_position
      @starting_position ||= if initial_fen
                               PGN::FEN.new(initial_fen).to_position
                             else
                               PGN::Position.start
                             end
    end

    # @return [Array<PGN::Position>] list of the {PGN::Position}s in the game
    #
    def positions
      @positions ||= each_position.to_a
    end

    # @return [Enumerator, self] with a block: yields each {PGN::Position}
    #   in order (starting position, then one per move) and returns self.
    #   Without a block: returns an Enumerator that yields the same.
    #
    # The replay loop is shared with {#positions} so eager and lazy paths
    # produce identical position objects in identical order.
    def each_position
      return enum_for(:each_position) unless block_given?

      position = starting_position
      yield position
      moves.each do |move|
        position = position.move(move.notation)
        yield position
      end
      self
    end

    # @return [Array<String>] list of the fen representations of the positions
    #
    def fen_list
      positions.map { |p| p.to_fen.inspect }
    end

    # Whether any position has occurred three times in this game (the
    # threefold-repetition draw). Uses {PGN::Position#hash} (the Zobrist
    # hash of the FEN-relevant state), streaming {#each_position} so the
    # full position array need not be materialized for this check.
    #
    # @return [Boolean]
    def threefold?
      counts = Hash.new(0)
      each_position { |position| counts[position.hash] += 1 }
      counts.any? { |_, count| count >= 3 }
    end

    # The terminal status of the game: :checkmate, :stalemate, or :draw
    # (insufficient material, 50-move rule, or threefold repetition). nil
    # if the game is still in progress. Requires the native extension for
    # checkmate/stalemate detection.
    #
    # @return [Symbol, nil]
    def outcome
      final = positions.last
      result = final&.outcome
      return result if result
      return :draw if threefold?

      nil
    end

    # Interactively step through the game
    #
    # Use +d+ to move forward, +a+ to move backward, and +^C+ to exit.
    #
    def play
      index = 0
      hist = Array.new(3, '')

      loop do
        puts "\e[H\e[2J"
        puts positions[index].inspect
        hist[0..2] = (hist[1..2] << $stdin.getch)

        case hist.join
        when LEFT
          index -= 1 if index.positive?
        when RIGHT
          index += 1 if index < moves.length
        when EXIT
          break
        end
      end
    end

    private

    # A MoveText is reused as-is (no new object) when its notation needs no
    # '0'->'O' fix; otherwise a new MoveText is built. clean_text is idempotent
    # (it only strips a *single* outermost brace pair), so reusing or rebuilding
    # a MoveText never corrupts a comment that still contains inner braces.
    def standardize_castling(entry)
      return MoveText.new(entry.include?('0') ? entry.gsub('0', 'O') : entry) if entry.is_a?(String)

      notation = entry.notation.include?('0') ? entry.notation.gsub('0', 'O') : entry.notation
      return entry if notation.equal?(entry.notation)

      MoveText.new(notation, entry.annotation, entry.comment, entry.variations)
    end
  end
end
