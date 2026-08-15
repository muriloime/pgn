# frozen_string_literal: true

module PGN
  # {PGN::EPD} translates between strings in Extended Position Description
  # and a {PGN::Position}. EPD is the FEN-like position format used by
  # {http://www.chessprogramming.org/Extended_Position_Description EPD tools}:
  # it shares FEN's first four fields (piece placement, side to move,
  # castling availability, en passant target square) and then carries a
  # trailing list of operations (`ops`) instead of the halfmove/fullmove
  # counters.
  #
  # @example
  #   PGN::EPD.new('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -')
  #   PGN::FEN.start.to_epd #=> "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -"
  #
  class EPD
    attr_accessor :board, :active, :ops
    attr_reader :castling, :en_passant

    # @param epd_string [String] an EPD string: four FEN fields followed by
    #   zero or more operation fields (kept verbatim as {#ops}).
    #
    def initialize(epd_string = nil)
      return unless epd_string

      fields = epd_string.split(' ', 5)
      self.board_string = fields[0]
      self.active = fields[1]
      self.castling = fields[2]
      self.en_passant = fields[3]
      self.ops = fields[4]
    end

    def castling=(val)
      @castling = val.nil? || val.empty? ? '-' : val
    end

    def en_passant=(val)
      @en_passant = val.nil? ? '-' : val
    end

    # @param board_fen [String] the FEN/EPD representation of the board
    #
    def board_string=(board_fen)
      squares = board_fen.gsub(/\d/) { |match| '_' * match.to_i }
                         .split('/')
                         .map(&:chars)
                         .map { |row| row.map { |e| e == '_' ? nil : e } }
                         .reverse
                         .transpose
      self.board = PGN::Board.new(squares)
    end

    # @return [String] the EPD board-string portion
    #
    def board_string
      board.fen_board_string
    end

    # @return [PGN::Position] a {PGN::Position} for this EPD. Halfmove and
    #   fullmove default to 0 and 1 (EPD does not carry them).
    #
    def to_position
      player = active == 'w' ? :white : :black
      castling_rights = castling.chars - ['-']
      ep = en_passant == '-' ? nil : en_passant

      PGN::Position.new(board, player, castling_rights, ep, 0, 1)
    end

    # @return [String] the EPD string (four fields, then +ops+ if present)
    #
    def to_s
      [board_string, active, castling, en_passant, ops].compact.reject(&:empty?).join(' ')
    end

    def inspect
      to_s
    end
  end
end
