# frozen_string_literal: true

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
    def initialize(board, player, castling = CASTLING, en_passant = nil, halfmove = 0, fullmove = 1)
      self.board      = board
      self.player     = player
      self.castling   = castling
      self.en_passant = en_passant
      self.halfmove   = halfmove
      self.fullmove   = fullmove
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

      PGN::Position.new(
        no_move ? board : calculator.result_board,
        next_player,
        new_castling,
        calculator.en_passant_square,
        new_halfmove,
        new_fullmove
      )
    end

    # @return [Symbol] the next player to move
    #
    def next_player
      player == :white ? :black : :white
    end

    # The perft node count at +depth+ from this position, computed by the
    # native bitboard engine via a FEN round-trip. Requires the compiled
    # native extension (the shipped gem); raises NameError if it is absent.
    #
    # @param depth [Integer] search depth, >= 0
    # @return [Integer]
    #
    def perft(depth)
      raise ArgumentError, 'depth must be a non-negative Integer' unless depth.is_a?(Integer) && depth >= 0

      PGN::Bitboard::Engine.new(to_fen.to_s).perft(depth)
    end

    # All legal moves from this position as sorted UCI strings
    # (e.g. "e2e4", "e1g1" for castling, "e7e8q" for promotion), computed
    # by the native bitboard engine via a FEN round-trip. Requires the
    # compiled native extension; raises NameError if it is absent.
    #
    # @return [Array<String>] sorted lexicographically
    #
    def legal_moves
      PGN::Bitboard::Engine.new(to_fen.to_s).legal_moves
    end

    # All legal moves from this position as sorted SAN strings, computed
    # by delegating the native engine's UCI move list through
    # {PGN::Notation.san}. Requires the compiled native extension; raises
    # NameError if it is absent.
    #
    # @return [Array<String>] sorted lexicographically
    #
    def legal_moves_san
      engine = PGN::Bitboard::Engine.new(to_fen.to_s)
      engine.legal_moves.map { |uci| uci_to_san(uci) }.sort
    end

    # Whether +move+ is legal. Accepts SAN ("Nf3", "e4", "O-O", "a8=Q",
    # "Qxf7#") or UCI ("g1f3", "e2e4", "e1g1", "a7a8q"). Requires the
    # compiled native extension; raises NameError if it is absent.
    #
    # UCI is handed straight to the engine. SAN is resolved against the
    # engine's legal move list: a SAN string is legal only when it points
    # at exactly one legal move (so an ambiguous "Nd2" with two knights
    # is rejected, while "Nbd2"/"Nfd2" are accepted). The engine remains
    # the single source of truth for legality (king safety, pins, etc.).
    #
    # @param move [String] SAN or UCI
    # @return [Boolean]
    def legal?(move)
      engine = PGN::Bitboard::Engine.new(to_fen.to_s)
      return engine.legal?(move) if uci?(move)

      parsed = PGN::Move.new(move, player)
      return false if parsed.destination.nil? && parsed.castle.nil?

      candidates = engine.legal_moves.select { |uci| matches_san?(uci, parsed) }
      candidates.size == 1
    rescue StandardError
      false
    end

    def inspect
      "\n#{board.inspect}"
    end

    # @return [PGN::FEN] a {PGN::FEN} object representing the current position
    #
    def to_fen
      PGN::FEN.from_attributes(
        board: board,
        active: player == :white ? 'w' : 'b',
        castling: castling.join,
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
        zobrist == other.zobrist &&
        board == other.board
    end

    alias == eql?

    def hash
      zobrist
    end

    # The Zobrist hash of the position. Computed lazily on first access and
    # cached, so the replay hot path (which never asks for the hash) pays
    # nothing; consumers like threefold-repetition checks pay one full seed.
    #
    # @return [Integer]
    def zobrist
      @zobrist ||= Zobrist.seed(board, player, castling, en_passant)
    end

    private

    # True when +move+ looks like a UCI coordinate string ("e2e4",
    # "e1g1", "a7a8q"), so it can be handed straight to the engine.
    def uci?(move)
      move.is_a?(String) && move.match?(/\A[a-h][1-8][a-h][1-8][qrbn]?\z/)
    end

    # Convert a UCI string to SAN using the current position, for
    # {#legal_moves_san}. Promotion (if present) is passed as the letter.
    def uci_to_san(uci)
      from = uci[0, 2]
      to = uci[2, 2]
      promo = uci[4]
      PGN::Notation.san(self, from, to, promo)
    end

    # Map a castling side letter from {PGN::Move#castle} to the king's
    # from/to UCI squares for the side to move.
    CASTLE_UCI = {
      'K' => 'e1g1',
      'Q' => 'e1c1',
      'k' => 'e8g8',
      'q' => 'e8c8'
    }.freeze
    private_constant :CASTLE_UCI

    # Does the legal UCI move +uci+ match the parsed SAN +move+? A move
    # matches when destination, piece, promotion, and castling all agree,
    # and the origin square satisfies +move+'s disambiguation (if any).
    def matches_san?(uci, move)
      return uci == CASTLE_UCI[move.castle] if move.castle

      to = uci[2, 2]
      return false if move.destination != to

      from_idx = board.index_of(uci[0, 2])
      return false if board.at_index(from_idx) != move.piece

      promo = uci[4]
      return false if move.promotion&.downcase != promo

      disambiguation_matches?(move.disambiguation, from_idx)
    end

    # Whether the disambiguation string from SAN (a file, a rank, or a full
    # square) describes the origin square at +from_idx+. nil disambiguation
    # matches any origin (ambiguity is handled by the caller counting matches).
    def disambiguation_matches?(disambiguation, from_idx)
      return true if disambiguation.nil? || disambiguation.empty?

      file = Board::INDEX_TO_FILE[from_idx & 0x0F]
      rank = Board::INDEX_TO_RANK[from_idx >> 4]
      case disambiguation
      when /\A[a-h]\z/ then file == disambiguation
      when /\A[1-8]\z/ then rank == disambiguation
      else file + rank == disambiguation
      end
    end
  end
end
