module PGN
  # {PGN::Position} encapsulates all of the information necessary to
  # completely understand a chess position. It can be turned into a FEN string
  # or perform a move.
  #
  # @!attribute board
  #   @return [PGN::Board] the board for the position
  #
  # @!attribute player
  #   @return [Symbol] the player who moves next
  #   @example
  #     position.player #=> :white
  #
  # @!attribute castling
  #   @return [Array<String>] the castling moves that are still available
  #   @example
  #     position.castling #=> ["K", "k", "q"]
  #
  # @!attribute en_passant
  #   @return [String] the en passant square if applicable
  #
  # @!attribute halfmove
  #   @return [Integer] the number of halfmoves since the last pawn move or
  #     capture
  #
  # @!attribute fullmove
  #   @return [Integer] the number of fullmoves made so far
  #

  class Position
    PLAYERS  = %i[white black].freeze
    CASTLING = %w[K Q k q].freeze

    attr_accessor :board, :player, :castling, :en_passant, :halfmove, :fullmove
    attr_reader :zobrist

    # @return [PGN::Position] the starting position of a chess game
    #
    def self.start
      PGN::Position.new(
        PGN::Board.start,
        PLAYERS.first
      )
    end

    # @param board [PGN::Board] the board for the position
    # @param player [Symbol] the player who moves next
    # @param castling [Array<String>] the castling moves that are still
    #   available
    # @param en_passant [String, nil] the en passant square if applicable
    # @param halfmove [Integer] the number of halfmoves since the last pawn
    #   move or capture
    # @param fullmove [Integer] the number of fullmoves made so far
    #
    # @example
    #   PGN::Position.new(
    #     PGN::Board.start,
    #     :white,
    #   )
    #
    def initialize(board, player, castling = CASTLING, en_passant = nil,
                   halfmove = 0, fullmove = 1, zobrist: nil)
      self.board      = board
      self.player     = player
      self.castling   = castling
      self.en_passant = en_passant
      self.halfmove   = halfmove
      self.fullmove   = fullmove
      @zobrist = zobrist || Zobrist.seed(board, player, castling, en_passant)
    end

    # @param str [String] the move to make in SAN
    # @return [PGN::Position] the resulting position
    #
    # @example
    #   queens_pawn = PGN::Position.start.move("d4")
    #
    def move(str)
      move       = PGN::Move.new(str, player)
      calculator = PGN::MoveCalculator.new(board, move)

      restrictions = calculator.castling_restrictions
      new_castling = restrictions.empty? ? castling : castling - restrictions
      new_halfmove = calculator.increment_halfmove? ? halfmove + 1 : 0
      new_fullmove = calculator.increment_fullmove? ? fullmove + 1 : fullmove
      no_move      = str == '--'

      new_board  = no_move ? board : calculator.result_board
      new_player = next_player
      new_ep     = calculator.en_passant_square

      new_zobrist = incremental_zobrist(move, calculator, new_board, new_castling, new_ep)

      PGN::Position.new(
        new_board, new_player, new_castling, new_ep, new_halfmove, new_fullmove,
        zobrist: new_zobrist
      )
    end

    # @return [Symbol] the next player to move
    #
    def next_player
      player == :white ? :black : :white
    end

    def inspect
      "\n" + board.inspect
    end

    # @return [PGN::FEN] a {PGN::FEN} object representing the current position
    #
    def to_fen
      PGN::FEN.from_attributes(
        board: board,
        active: player == :white ? 'w' : 'b',
        castling: castling.join(''),
        en_passant: en_passant,
        halfmove: halfmove.to_s,
        fullmove: fullmove.to_s
      )
    end

    # Positions are equal when their board, side to move, castling rights,
    # and en-passant square match. Halfmove/fullmove counters are ignored
    # (matching threefold-repetition semantics).
    def eql?(other)
      other.is_a?(PGN::Position) &&
        player == other.player &&
        castling == other.castling &&
        en_passant == other.en_passant &&
        board_equal?(other.board)
    end

    alias == eql?

    def hash
      zobrist
    end

    private

    # First cut: re-seed from scratch. Correct, and the "keeps the replay
    # hash in sync" spec pins correctness. Task 7 replaces this with the
    # incremental XOR-diff path.
    def incremental_zobrist(_move, calculator, new_board, new_castling, new_ep)
      Zobrist.update(self, calculator, new_board, new_castling, new_ep)
    end

    def board_equal?(other_board)
      0.upto(127).all? { |idx| board.at_index(idx) == other_board.at_index(idx) }
    end
  end
end
