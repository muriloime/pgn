# frozen_string_literal: true

module PGN
  # {PGN::MoveCalculator} is responsible for computing all of the ways that a
  # specific move changes the current position. This includes which squares on
  # the board need to be updated, new castling restrictions, the en passant
  # square and whether to update fullmove and halfmove counters.
  #
  # Squares are addressed as 0x88 integer indices (see {PGN::Board}); this
  # keeps the replay hot path free of `[file, rank]` coordinate arrays and
  # square-name string allocations. The public {#origin} reader still returns
  # an algebraic square string for API compatibility.
  #
  # @!attribute board
  #   @return [PGN::Board] the current board
  #
  # @!attribute move
  #   @return [PGN::Move] the current move
  #
  class MoveCalculator
    # 0x88 ray-step offsets for sliding pieces. A step is a single integer
    # add; off-board is `(idx & 0x88) != 0`, which also catches file wraparound.
    #
    SLIDE = {
      'b' => [-15, 15, -17, 17],
      'r' => [-1, 1, -16, 16],
      'q' => [-1, 1, -16, 16, -15, 15, -17, 17]
    }.freeze

    # 0x88 single-step offsets for knight and king.
    #
    STEP = {
      'k' => SLIDE['q'],
      'n' => [33, 31, -31, -33, 18, 14, -14, -18]
    }.freeze

    # Possible pawn origins, expressed as offsets from the destination square
    # (pawn moves are computed backwards from where the pawn landed).
    #
    PAWN_OFFSETS = {
      'P' => { capture: [-17, -15], normal: [-16], double: [-32] },
      'p' => { capture: [15, 17], normal: [16], double: [32] }
    }.freeze

    # Corner-square 0x88 indices, used for castling-restriction bookkeeping
    # (a rook leaving or being captured on a corner drops the matching right).
    #
    A1 = 0
    H1 = 7
    A8 = 112
    H8 = 119

    # King/rook landing squares for castling, named for readability in
    # {CASTLING} below.
    #
    C1 = 2
    D1 = 3
    E1 = 4
    F1 = 5
    G1 = 6
    C8 = 114
    D8 = 115
    E8 = 116
    F8 = 117
    G8 = 118

    # The squares to update for each castling move, keyed by 0x88 index.
    #
    CASTLING = {
      'Q' => { A1 => nil, C1 => 'K', D1 => 'R', E1 => nil },
      'K' => { E1 => nil, F1 => 'R', G1 => 'K', H1 => nil },
      'q' => { A8 => nil, C8 => 'k', D8 => 'r', E8 => nil },
      'k' => { E8 => nil, F8 => 'r', G8 => 'k', H8 => nil }
    }.freeze

    # rook-origin (0x88 index) -> castling restriction it drops.
    #
    ROOK_RESTRICTIONS = { A1 => 'Q', H1 => 'K', A8 => 'q', H8 => 'k' }.freeze

    # Castling-move characters by side, for the "castling occurs" restriction.
    # Frozen so {Array#include?} does not allocate per call.
    #
    WHITE_CASTLE = %w[K Q].freeze
    BLACK_CASTLE = %w[k q].freeze

    attr_reader :board, :move

    # @param board [PGN::Board] the current board
    # @param move [PGN::Move] the current move
    #
    def initialize(board, move)
      @board = board
      @move  = move
      @origin_idx = compute_origin
    end

    # @return [String, nil] the origin square in algebraic notation, for API
    #   compatibility. Internally the calculator works with the 0x88 index
    #   (see {#origin_idx}); this reader materialises the string on demand.
    #
    def origin
      return nil if @origin_idx.nil?

      board.square_name(@origin_idx)
    end

    # @return [PGN::Board] the board after the move is made
    #
    def result_board
      new_board = board.dup
      new_board.apply!(changes)

      new_board
    end

    # @return [Array<String>] which castling moves are no longer available
    #
    def castling_restrictions
      restrict = []

      case move.piece
      when 'K'
        restrict << 'K' << 'Q'
      when 'k'
        restrict << 'k' << 'q'
      when 'R', 'r'
        restrict << ROOK_RESTRICTIONS[@origin_idx]
      end

      # when castling occurs
      if WHITE_CASTLE.include?(move.castle)
        restrict << 'K' << 'Q'
      elsif BLACK_CASTLE.include?(move.castle)
        restrict << 'k' << 'q'
      end

      # when a rook is taken
      dest = dest_idx
      restrict << 'Q' if dest == A1
      restrict << 'q' if dest == A8
      restrict << 'K' if dest == H1
      restrict << 'k' if dest == H8

      restrict.empty? ? restrict : restrict.compact.uniq
    end

    # @return [Boolean] whether to increment the halfmove clock
    #
    def increment_halfmove?
      !(move.capture || move.pawn?)
    end

    # @return [Boolean] whether to increment the fullmove counter
    #
    def increment_fullmove?
      move.black?
    end

    # @return [String, nil] the en passant square if applicable
    #
    def en_passant_square
      return nil if move.castle
      return nil unless move.pawn? && ((origin_rank - dest_rank).abs == 2)

      Board::INDEX_TO_FILE[origin_file] + (move.white? ? '3' : '6')
    end

    private

    # The integer-indexed changes to apply to the board. Keys are 0x88
    # indices, so no square-name strings are allocated on the hot path.
    #
    def changes
      changes = {}
      changes.merge!(CASTLING[move.castle]) if move.castle
      changes[@origin_idx] = nil
      changes[dest_idx] = move.piece
      changes[en_passant_capture] = nil
      changes[dest_idx] = move.promotion if move.promotion

      changes.reject! { |idx, _| idx.nil? }

      changes
    end

    # Using the current position and move, figure out where the piece
    # came from (as a 0x88 index).
    #
    def compute_origin
      return nil if move.castle

      possibilities = case move.piece
                      when 'B', 'R', 'Q', 'b', 'r', 'q' then direction_origins
                      when 'K', 'N', 'k', 'n' then move_origins
                      when 'P', 'p' then pawn_origins
                      else # don't care move, used in variations
                        return nil
                      end

      possibilities = disambiguate(possibilities) if possibilities.length > 1

      possibilities.first
    end

    # From the destination square, walk each slider direction until the first
    # occupied square. If that piece is the moving piece, the square it sits
    # on is a possible origin.
    #
    def direction_origins
      offsets = SLIDE[move.piece.downcase]
      dest    = dest_idx

      possibilities = []
      offsets.each do |off|
        square = first_piece(dest, off)
        possibilities << square if piece_at(square) == move.piece
      end

      possibilities
    end

    # From the destination square, apply each single-step offset. If the
    # target square is on the board and holds the moving piece, it is a
    # possible origin.
    #
    def move_origins(offsets = STEP[move.piece.downcase])
      dest = dest_idx

      possibilities = []
      offsets.each do |off|
        target = dest + off
        next unless board.on_board?(target)

        possibilities << target if board.at_index(target) == move.piece
      end

      possibilities
    end

    # Computes the possible pawn origins based on the destination square
    # and whether or not the move is a capture.
    #
    def pawn_origins
      double = (dest_rank == 3 && move.white?) || (dest_rank == 4 && move.black?)

      pawn_moves = PAWN_OFFSETS[move.piece]
      offsets = move.capture ? pawn_moves[:capture] : pawn_moves[:normal]
      offsets += pawn_moves[:double] if double

      move_origins(offsets)
    end

    def disambiguate(possibilities)
      possibilities = disambiguate_san(possibilities)
      possibilities = disambiguate_pawns(possibilities)            if possibilities.length > 1
      possibilities = disambiguate_discovered_check(possibilities) if possibilities.length > 1

      possibilities
    end

    # Try to disambiguate based on the standard algebraic notation.
    #
    def disambiguate_san(possibilities)
      return possibilities unless move.disambiguation

      possibilities.select do |idx|
        board.square_name(idx).match(move.disambiguation)
      end
    end

    # A pawn can't move two spaces if there is a pawn in front of it. A
    # double-push origin sits on rank 2 (white) or 7 (black); reject those
    # candidates when more than one pawn could have reached the destination.
    #
    def disambiguate_pawns(possibilities)
      return possibilities unless move.piece.match?(/p/i) && !move.capture

      possibilities.reject { |idx| (idx >> 4) == 1 || (idx >> 4) == 6 }
    end

    # A piece can't move if it would result in a discovered check.
    #
    def disambiguate_discovered_check(possibilities)
      king_idx = king_position

      SLIDE.each do |attacking_piece, offsets|
        attacking_piece = attacking_piece.upcase if move.black?

        offsets.each do |off|
          square = first_piece(king_idx, off)
          next unless piece_at(square) == move.piece && possibilities.include?(square)

          next_square = first_piece(square, off)
          possibilities.reject! { |p| p == square } if piece_at(next_square) == attacking_piece
        end
      end

      possibilities
    end

    # Walks from `idx` in the 0x88 direction `off` until it reaches the edge
    # of the board or the first occupied square. Returns that square's 0x88
    # index, or nil if no piece was encountered before the edge.
    #
    def first_piece(idx, off)
      idx += off
      while board.on_board?(idx)
        square = board.at_index(idx)
        return idx if square

        idx += off
      end
      nil
    end

    # Reads the piece at a 0x88 index, returning nil for an off-board (nil)
    # index. Keeps {#disambiguate_discovered_check} within the configured
    # complexity limits.
    #
    def piece_at(idx)
      idx && board.at_index(idx)
    end

    # If the move is a capture and there is no piece on the destination
    # square, it must be an en passant capture. The captured pawn sits on the
    # destination file and the moving pawn's origin rank.
    #
    def en_passant_capture
      return nil if move.castle
      return nil unless move.capture && board.at_index(dest_idx).nil?

      board.index_for(dest_idx & 0x0F, origin_rank)
    end

    def king_position
      king = move.white? ? 'K' : 'k'

      0.upto(7) do |rank|
        0.upto(7) do |file|
          idx = board.index_for(file, rank)
          return idx if board.at_index(idx) == king
        end
      end

      nil
    end

    # -- 0x88 index helpers --------------------------------------------------

    def dest_idx
      @dest_idx ||= move.destination && board.index_of(move.destination)
    end

    def origin_file
      @origin_idx & 0x0F
    end

    def origin_rank
      @origin_idx >> 4
    end

    def dest_rank
      dest_idx >> 4
    end
  end
end
