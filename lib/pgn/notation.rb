# frozen_string_literal: true

module PGN
  # {PGN::Notation} generates Standard Algebraic Notation (SAN) for a single
  # move described in coordinate form -- an origin square, a destination
  # square, and an optional promotion piece -- given the {PGN::Position}
  # *before* the move is played.
  #
  # Unlike {PGN::Move}, which *parses* an existing SAN string, {PGN::Notation}
  # *builds* SAN from coordinates. This requires the kind of legality analysis
  # the rest of the gem does not perform: attack detection, "does this move
  # leave the mover's king in check", disambiguation among same-type pieces
  # that can legally reach the destination, and check (+) / checkmate (#)
  # suffix detection (the latter needing full legal-move generation for the
  # side to move).
  #
  # The board is addressed with the same 0x88 integer indices the rest of the
  # gem uses (see {PGN::Board}); an index is on-board when
  # `(idx & 0x88).zero?`.
  #
  # @example
  #   PGN::Notation.san(PGN::Position.start, 'g1', 'f3') #=> "Nf3"
  #   PGN::Notation.san_from_fen(PGN::FEN::INITIAL, 'e2', 'e4') #=> "e4"
  #
  class Notation
    # 0x88 single-step offsets for a knight (symmetric, so they double as
    # attack deltas).
    KNIGHT_OFFS = [33, 31, -31, -33, 18, 14, -14, -18].freeze
    # 0x88 single-step offsets for a king (symmetric).
    KING_OFFS = [-1, 1, -16, 16, -15, 15, -17, 17].freeze
    BISHOP_DIRS = [-15, 15, -17, 17].freeze
    ROOK_DIRS = [-1, 1, -16, 16].freeze

    # Build SAN for a coordinate move from a {PGN::Position}.
    #
    # @param position [PGN::Position] the position *before* the move
    # @param from [String] origin square in algebraic notation ("e2")
    # @param to [String] destination square in algebraic notation ("e4")
    # @param promotion [String, nil] promotion piece letter ("q"/"Q"/"n"...);
    #   case-insensitive; SAN always emits an uppercase letter
    # @return [String] the move in SAN, e.g. "Nf3", "exd5", "O-O", "Ra8#"
    #
    def self.san(position, from, to, promotion = nil)
      new(position).san(from, to, promotion)
    end

    # Convenience: build SAN directly from a FEN string.
    #
    # @param fen [String] the FEN of the position *before* the move
    # @param (see .san)
    # @return [String] the move in SAN
    #
    def self.san_from_fen(fen, from, to, promotion = nil)
      san(PGN::FEN.new(fen).to_position, from, to, promotion)
    end

    def initialize(position)
      @position = position
      @board = position.board
      @player = position.player
      @mover = (@player == :white ? 'w' : 'b')
      @enemy = (@player == :white ? 'b' : 'w')
    end

    # @param (see .san)
    # @return [String]
    def san(from, to, promotion = nil)
      from_idx = @board.index_of(from)
      to_idx = @board.index_of(to)
      piece = @board.at_index(from_idx)
      raise ArgumentError, "no piece on #{from}" if piece.nil?

      promotion = promotion.upcase if promotion

      castling = piece.upcase == 'K' && ((from_idx & 0x0F) - (to_idx & 0x0F)).abs == 2
      capture = castling ? false : capture?(piece, from_idx, to_idx)

      body =
        if castling
          to_idx < from_idx ? 'O-O-O' : 'O-O'
        elsif piece.upcase == 'P'
          pawn_body(from_idx, to_idx, capture, promotion)
        else
          piece_body(piece, from_idx, to_idx, capture)
        end

      body + suffix(from_idx, to_idx, piece, promotion, castling)
    end

    private

    # -- body construction -------------------------------------------------

    def pawn_body(from_idx, to_idx, capture, promotion)
      dest = @board.position_for([to_idx & 0x0F, to_idx >> 4])
      promo = promotion ? "=#{promotion}" : ''
      if capture
        "#{Board::INDEX_TO_FILE[from_idx & 0x0F]}x#{dest}#{promo}"
      else
        "#{dest}#{promo}"
      end
    end

    def piece_body(piece, from_idx, to_idx, capture)
      disamb = disambiguation(piece, from_idx, to_idx)
      dest = @board.position_for([to_idx & 0x0F, to_idx >> 4])
      parts = [piece.upcase, disamb]
      parts << 'x' if capture
      parts << dest
      parts.join
    end

    # Disambiguate a non-pawn, non-castling move among same-type pieces that
    # can *legally* reach the destination. Returns '' when none can.
    def disambiguation(piece, from_idx, to_idx)
      others = same_type_legals(piece, from_idx, to_idx)
      return '' if others.empty?

      from_file = from_idx & 0x0F
      from_rank = from_idx >> 4
      file_clash = others.any? { |o| (o & 0x0F) == from_file }
      rank_clash = others.any? { |o| (o >> 4) == from_rank }

      if !file_clash
        Board::INDEX_TO_FILE[from_file]
      elsif !rank_clash
        Board::INDEX_TO_RANK[from_rank]
      else
        Board::INDEX_TO_FILE[from_file] + Board::INDEX_TO_RANK[from_rank]
      end
    end

    # Other squares holding `piece` whose move to `to_idx` is legal.
    def same_type_legals(piece, from_idx, to_idx)
      (0...128).each_with_object([]) do |idx, acc|
        next if (idx & 0x88) != 0
        next if idx == from_idx
        next unless @board.at_index(idx) == piece

        acc << idx if reaches?(piece, idx, to_idx) && legal_after?(idx, to_idx, piece)
      end
    end

    # -- check / checkmate suffix -----------------------------------------

    def suffix(from_idx, to_idx, piece, promotion, castling)
      nb = apply_move(from_idx, to_idx, piece, promotion, castling)
      opp_king = king_idx(nb, @enemy)
      return '' unless opp_king && attacked?(nb, opp_king, @mover)

      result_pos = PGN::Position.new(
        nb,
        @player == :white ? :black : :white,
        [],
        new_ep_square(piece, from_idx, to_idx),
        0,
        @position.fullmove
      )
      any_legal_move?(result_pos) ? '+' : '#'
    end

    # -- move application -------------------------------------------------

    def apply_move(from_idx, to_idx, piece, promotion, castling)
      nb = @board.dup
      return castle!(nb, from_idx, to_idx, piece) if castling

      ep = ep_capture_square(piece, from_idx, to_idx)
      nb.update_index(ep, nil) if ep
      nb.update_index(from_idx, nil)
      nb.update_index(to_idx, promotion ? promoted(promotion) : piece)
      nb
    end

    def castle!(board, from_idx, to_idx, piece)
      rank = from_idx >> 4
      rook = piece.upcase == 'K' ? 'R' : 'r'
      board.update_index(from_idx, nil)
      board.update_index(to_idx, piece)
      if to_idx < from_idx # queenside
        board.update_index(rank * 16, nil)
        board.update_index((rank * 16) + 3, rook)
      else # kingside
        board.update_index((rank * 16) + 7, nil)
        board.update_index((rank * 16) + 5, rook)
      end
      board
    end

    def promoted(promotion)
      @player == :white ? promotion.upcase : promotion.downcase
    end

    # En-passant captured-pawn square (or nil): a pawn moving diagonally to
    # an empty destination must be capturing en passant.
    def ep_capture_square(piece, from_idx, to_idx)
      return nil unless piece.upcase == 'P'
      return nil if (from_idx & 0x0F) == (to_idx & 0x0F)

      @board.at_index(to_idx).nil? ? ((from_idx >> 4) * 16) + (to_idx & 0x0F) : nil
    end

    # The en-passant target square left behind by a double pawn push, for the
    # resulting position (so an escaping ep capture is considered for mate).
    def new_ep_square(piece, from_idx, to_idx)
      return nil unless piece.upcase == 'P'
      return nil if ((from_idx >> 4) - (to_idx >> 4)).abs != 2

      mid = ((from_idx >> 4) + (to_idx >> 4)) / 2
      Board::INDEX_TO_FILE[from_idx & 0x0F] + Board::INDEX_TO_RANK[mid]
    end

    # -- legality ---------------------------------------------------------

    # Is `piece` from `from_idx` to `to_idx` legal (own king safe after)?
    def legal_after?(from_idx, to_idx, piece)
      nb = @board.dup
      ep = ep_capture_square(piece, from_idx, to_idx)
      nb.update_index(ep, nil) if ep
      nb.update_index(from_idx, nil)
      nb.update_index(to_idx, piece)
      king = king_idx(nb, @mover)
      king && !attacked?(nb, king, @enemy)
    end

    # Does `piece` at `from_idx` pseudo-legally reach `to_idx` on the board?
    # (Sliders honor blockers; the destination may be empty or enemy-occupied.)
    def reaches?(piece, from_idx, to_idx)
      return false if from_idx == to_idx

      case piece.upcase
      when 'N'
        Board::KNIGHT_ATTACKS[from_idx].include?(to_idx)
      when 'K'
        Board::KING_ATTACKS[from_idx].include?(to_idx)
      when 'B', 'R', 'Q'
        slider_reaches?(piece.upcase, from_idx, to_idx)
      else
        false
      end
    end

    def slider_reaches?(piece_up, from_idx, to_idx)
      slider_dirs(piece_up).any? do |off|
        i = from_idx + off
        while (i & 0x88).zero?
          return true if i == to_idx
          break if @board.at_index(i)

          i += off
        end
        false
      end
    end

    # Capture detection for the *played* move (used in the SAN body).
    def capture?(piece, from_idx, to_idx)
      if piece.upcase == 'P'
        (from_idx & 0x0F) != (to_idx & 0x0F) # any diagonal pawn move captures
      else
        target = @board.at_index(to_idx)
        target && !own?(target, @mover)
      end
    end

    def own?(piece, color)
      color == 'w' ? piece == piece.upcase : piece == piece.downcase
    end

    # Slider ray directions for a piece letter ('B'/'R'/'Q').
    def slider_dirs(piece_up)
      case piece_up
      when 'B' then BISHOP_DIRS
      when 'R' then ROOK_DIRS
      else BISHOP_DIRS + ROOK_DIRS
      end
    end

    # -- attack / legality helpers ----------------------------------------

    def king_idx(board, color)
      king = color == 'w' ? 'K' : 'k'
      (0...128).each do |idx|
        next if (idx & 0x88) != 0

        return idx if board.at_index(idx) == king
      end
      nil
    end

    # Is `target` attacked by `color`-colored pieces on `board`?
    def attacked?(board, target, color)
      pawn_attacked?(board, target, color) ||
        knight_attacked?(board, target, color) ||
        king_attacked?(board, target, color) ||
        slider_attacked?(board, target, color)
    end

    def pawn_attacked?(board, target, color)
      offs = color == 'w' ? [-15, -17] : [15, 17]
      pawn = color == 'w' ? 'P' : 'p'
      offs.any? do |off|
        i = target + off
        (i & 0x88).zero? && board.at_index(i) == pawn
      end
    end

    def knight_attacked?(board, target, color)
      knight = color == 'w' ? 'N' : 'n'
      Board::KNIGHT_ATTACKS[target].any? { |i| board.at_index(i) == knight }
    end

    def king_attacked?(board, target, color)
      king = color == 'w' ? 'K' : 'k'
      Board::KING_ATTACKS[target].any? { |i| board.at_index(i) == king }
    end

    def slider_attacked?(board, target, color)
      bishop = color == 'w' ? 'B' : 'b'
      rook = color == 'w' ? 'R' : 'r'
      queen = color == 'w' ? 'Q' : 'q'
      ray_hit?(board, target, BISHOP_DIRS) { |p| p == bishop || p == queen } ||
        ray_hit?(board, target, ROOK_DIRS) { |p| p == rook || p == queen }
    end

    def ray_hit?(board, target, dirs)
      dirs.each do |off|
        i = target + off
        while (i & 0x88).zero?
          piece = board.at_index(i)
          if piece
            return true if yield(piece)
            break
          end
          i += off
        end
      end
      false
    end

    # -- legal-move generation (for checkmate detection) ------------------

    def any_legal_move?(position)
      board = position.board
      color = position.player == :white ? 'w' : 'b'
      ep_idx = ep_target_idx(position, board)

      (0...128).any? do |idx|
        next if (idx & 0x88) != 0

        piece = board.at_index(idx)
        piece && own?(piece, color) && move_from?(board, idx, piece, color, ep_idx)
      end
    end

    def ep_target_idx(position, board)
      ep = position.en_passant
      return nil if ep.nil? || ep == '-' || ep.empty?

      board.index_of(ep)
    end

    # Yields true if `piece` at `idx` has any legal move (escapes check).
    def move_from?(board, idx, piece, color, ep_idx)
      up = piece.upcase
      case up
      when 'N' then leaper_moves?(board, idx, piece, color, Board::KNIGHT_ATTACKS[idx])
      when 'K' then leaper_moves?(board, idx, piece, color, Board::KING_ATTACKS[idx])
      when 'B', 'R', 'Q'
        slider_moves?(board, idx, piece, color, slider_dirs(up))
      when 'P'
        pawn_moves?(board, idx, piece, color, ep_idx)
      else
        false
      end
    end

    def leaper_moves?(board, idx, piece, color, targets)
      targets.any? do |t|
        landable?(board, t, color) && safe?(board, idx, t, piece, nil)
      end
    end

    def slider_moves?(board, idx, piece, color, dirs)
      dirs.any? do |off|
        t = idx + off
        while (t & 0x88).zero?
          tp = board.at_index(t)
          if tp.nil?
            return true if safe?(board, idx, t, piece, nil)
          else
            return true if !own?(tp, color) && safe?(board, idx, t, piece, nil)
            break
          end
          t += off
        end
        false
      end
    end

    def pawn_moves?(board, idx, piece, color, ep_idx)
      pawn_pushes?(board, idx, piece, color) ||
        pawn_captures?(board, idx, piece, color, ep_idx)
    end

    def pawn_pushes?(board, idx, piece, color)
      dir = color == 'w' ? 16 : -16
      start_rank = color == 'w' ? 1 : 6
      promo_rank = color == 'w' ? 7 : 0

      t = idx + dir
      return false unless (t & 0x88).zero? && board.at_index(t).nil?

      promo = (t >> 4 == promo_rank) ? 'Q' : nil
      return true if safe?(board, idx, t, piece, promo)

      t2 = idx + (dir * 2)
      (idx >> 4) == start_rank && board.at_index(t2).nil? && safe?(board, idx, t2, piece, nil)
    end

    def pawn_captures?(board, idx, piece, color, ep_idx) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      promo_rank = color == 'w' ? 7 : 0
      caps = color == 'w' ? [15, 17] : [-15, -17]
      caps.any? do |off|
        t = idx + off
        next false unless (t & 0x88).zero?

        tp = board.at_index(t)
        promo = (t >> 4 == promo_rank) ? 'Q' : nil
        if tp && !own?(tp, color)
          safe?(board, idx, t, piece, promo)
        elsif tp.nil? && t == ep_idx
          safe?(board, idx, t, piece, nil)
        else
          false
        end
      end
    end

    def landable?(board, target, color)
      tp = board.at_index(target)
      tp.nil? || !own?(tp, color)
    end

    # Apply a pseudo-move (with ep + promotion) on a copy and test own-king
    # safety. The moving side is derived from `piece`'s case.
    def safe?(board, from_idx, to_idx, piece, promotion)
      nb = board.dup
      if piece.upcase == 'P' && (from_idx & 0x0F) != (to_idx & 0x0F) && board.at_index(to_idx).nil?
        nb.update_index(((from_idx >> 4) * 16) + (to_idx & 0x0F), nil) # ep capture
      end
      nb.update_index(from_idx, nil)
      nb.update_index(to_idx, place_piece(piece, promotion))
      color = own?(piece, 'w') ? 'w' : 'b'
      king = king_idx(nb, color)
      king && !attacked?(nb, king, color == 'w' ? 'b' : 'w')
    end

    # The piece letter to place on the destination after a pseudo-move.
    def place_piece(piece, promotion)
      return piece unless promotion

      white = piece == piece.upcase
      white ? promotion.upcase : promotion.downcase
    end
  end
end
