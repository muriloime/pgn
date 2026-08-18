# frozen_string_literal: true

module PGN
  # {PGN::Attack} is the single source of truth for square-attack queries on
  # a {PGN::Board}. It factors the private attack logic that {PGN::Notation}
  # previously duplicated, so {PGN::Position} (and other consumers) can ask
  # "is this square attacked?" and "which squares attack this square?".
  #
  # Squares are 0x88 indices (see {PGN::Board}); on-board when
  # `(idx & 0x88).zero?`. `color` is 'w' or 'b'.
  module Attack
    BISHOP_DIRS = [-15, 15, -17, 17].freeze
    ROOK_DIRS = [-1, 1, -16, 16].freeze

    # The 0x88 index of the `color` king on +board+, or nil if absent.
    def self.king_idx(board, color)
      king = piece_letter('K', color)
      (0...128).each do |idx|
        next if idx.anybits?(0x88)

        return idx if board.at_index(idx) == king
      end
      nil
    end

    # Whether +target+ (a 0x88 index) is attacked by any `color` piece.
    # Checked (and short-circuited) piece type by piece type, cheapest first,
    # so a hit skips the pricier ray-walk sliders scan entirely.
    def self.attacked?(board, target, color)
      pawn_attackers(board, target, color).any? ||
        knight_attackers(board, target, color).any? ||
        king_attackers(board, target, color).any? ||
        slider_attackers(board, target, color).any?
    end

    # The algebraic squares of every `color` piece on +board+ that attacks
    # +target+ (a 0x88 index), in no particular order.
    def self.attackers(board, target, color)
      pawn_attackers(board, target, color) +
        knight_attackers(board, target, color) +
        king_attackers(board, target, color) +
        slider_attackers(board, target, color)
    end

    class << self
      private

      # 'w' -> the uppercase letter, 'b' -> the lowercase letter.
      def piece_letter(letter, color)
        color == 'w' ? letter : letter.downcase
      end

      def pawn_attackers(board, target, color)
        offs = color == 'w' ? [-15, -17] : [15, 17]
        pawn = piece_letter('P', color)
        offs.each_with_object([]) do |off, a|
          i = target + off
          a << board.square_name(i) if i.nobits?(0x88) && board.at_index(i) == pawn
        end
      end

      def knight_attackers(board, target, color)
        knight = piece_letter('N', color)
        Board::KNIGHT_ATTACKS[target].each_with_object([]) do |i, a|
          a << board.square_name(i) if board.at_index(i) == knight
        end
      end

      def king_attackers(board, target, color)
        king = piece_letter('K', color)
        Board::KING_ATTACKS[target].each_with_object([]) do |i, a|
          a << board.square_name(i) if board.at_index(i) == king
        end
      end

      def slider_attackers(board, target, color)
        bishop = piece_letter('B', color)
        rook = piece_letter('R', color)
        queen = piece_letter('Q', color)
        squares = []
        ray_attackers(board, target, BISHOP_DIRS) do |piece, sq|
          squares << sq if piece == bishop || piece == queen
        end
        ray_attackers(board, target, ROOK_DIRS) do |piece, sq|
          squares << sq if piece == rook || piece == queen
        end
        squares
      end

      # Walk each ray from +target+; yield the first piece hit on that ray
      # along with its square.
      def ray_attackers(board, target, dirs)
        dirs.each do |off|
          i = target + off
          while i.nobits?(0x88)
            piece = board.at_index(i)
            if piece
              yield(piece, board.square_name(i))
              break
            end
            i += off
          end
        end
      end
    end
  end
end
