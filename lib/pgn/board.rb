# frozen_string_literal: true

module PGN
  # {PGN::Board} represents the squares of a chess board and the pieces on
  # each square. It is responsible for translating between a human readable
  # format (white queen's rook on the bottom left) and the obvious
  # internal representation (white queen's rook is position [0,0]). It
  # takes care of converting square names (e4) to actual locations, and
  # can convert to unicode chess pieces for display purposes.
  #
  # @!attribute squares
  #   @return [Array<Array<String>>] the pieces on the board
  #

  class Board
    # The starting, internal representation of a chess board
    #
    START = [
      ['R', 'P', nil, nil, nil, nil, 'p', 'r'],
      ['N', 'P', nil, nil, nil, nil, 'p', 'n'],
      ['B', 'P', nil, nil, nil, nil, 'p', 'b'],
      ['Q', 'P', nil, nil, nil, nil, 'p', 'q'],
      ['K', 'P', nil, nil, nil, nil, 'p', 'k'],
      ['B', 'P', nil, nil, nil, nil, 'p', 'b'],
      ['N', 'P', nil, nil, nil, nil, 'p', 'n'],
      ['R', 'P', nil, nil, nil, nil, 'p', 'r']
    ].freeze

    FILE_TO_INDEX = ('a'..'h').each_with_index.to_h
    INDEX_TO_FILE = FILE_TO_INDEX.invert

    RANK_TO_INDEX = ('1'..'8').each_with_index.to_h
    INDEX_TO_RANK = RANK_TO_INDEX.invert

    # algebraic to unicode piece lookup
    #
    UNICODE_PIECES = {
      'k' => "\u{265A}",
      'q' => "\u{265B}",
      'r' => "\u{265C}",
      'b' => "\u{265D}",
      'n' => "\u{265E}",
      'p' => "\u{265F}",
      'K' => "\u{2654}",
      'Q' => "\u{2655}",
      'R' => "\u{2656}",
      'B' => "\u{2657}",
      'N' => "\u{2658}",
      'P' => "\u{2659}",
      nil => '_'
    }.freeze

    # 0x88 board representation (see chess.js / the classic 0x88 move-generation
    # algorithm). A square is addressed by a single integer index
    # `rank * 16 + file`; the extra files/ranks make off-board detection a
    # single bitmask test -- `(idx & 0x88) != 0` -- which is faster than the
    # four-integer comparison a 0..7 bounds check needs, and lets ray
    # stepping be a single integer add. The public `squares` 8x8 API is built
    # from this array on demand (it is off the replay hot path), and the
    # MoveCalculator hot path works entirely in integer indices.
    #
    #   file = idx & 0x0F   (0..7)
    #   rank = idx >> 4      (0..7)

    # @return [PGN::Board] a board in the starting position
    #
    def self.start
      PGN::Board.new(START)
    end

    # @param squares [<Array<Array<String>>>] the squares of the board
    # @example
    #   PGN::Board.new(
    #     [
    #       ["R", "P", nil, nil, nil, nil, "p", "r"],
    #       ["N", "P", nil, nil, nil, nil, "p", "n"],
    #       ["B", "P", nil, nil, nil, nil, "p", "b"],
    #       ["Q", "P", nil, nil, nil, nil, "p", "q"],
    #       ["K", "P", nil, nil, nil, nil, "p", "k"],
    #       ["B", "P", nil, nil, nil, nil, "p", "b"],
    #       ["N", "P", nil, nil, nil, nil, "p", "n"],
    #       ["R", "P", nil, nil, nil, nil, "p", "r"],
    #     ]
    #   )
    #
    def initialize(squares)
      self.squares = squares
    end

    # @return [Array<Array<String>>] the board as a file-major 8x8 array
    #   (squares[file][rank]). Built on demand from the 0x88 array; equality
    #   with the START constant and other boards is preserved.
    #
    def squares
      (0..7).map { |f| (0..7).map { |r| @cells[(r * 16) + f] } }
    end

    def squares=(squares)
      @cells = Array.new(128)
      8.times do |f|
        8.times do |r|
          @cells[(r * 16) + f] = squares[f][r]
        end
      end
    end

    # @overload at(str)
    #   Looks up a piece based on the string representation of a square (e4)
    #   @param str [String] the square in algebraic notation
    # @overload at(file, rank)
    #   Looks up a piece based on zero-indexed coordinates (4, 3)
    #   @param file [Integer] the file the piece is on
    #   @param rank [Integer] the rank the piece is on
    # @return [String, nil] the piece on the square, or nil if it is
    #   empty
    # @example
    #   board.at(4,3)  #=> "P"
    #   board.at("e4") #=> "P"
    #
    def at(arg0, arg1 = nil)
      return at_index(index_for(arg0, arg1)) unless arg1.nil?

      at_index(index_of(arg0))
    end

    # @param changes [Hash<String, <String, nil>>] changes to make to the board
    # @return [self]
    # @example
    #   board.change!({"e2" => nil, "e4" => "P"})
    #
    def change!(changes)
      changes.each { |square, piece| update(square, piece) }
      self
    end

    # @param square [String] the square in algebraic notation
    # @param piece [String, nil] the piece to put on the square
    # @return [self]
    # @example
    #   board.update("e4", "P")
    #
    def update(square, piece)
      update_index(index_of(square), piece)
    end

    # @param position [String] the square in algebraic notation
    # @return [Array<Integer>] the coordinates of the square
    # @example
    #   board.coordinates_for("e4") #=> [4, 3]
    #
    def coordinates_for(position)
      [file_of(position), rank_of(position)]
    end

    # @param coordinates [Array<Integer>] the coordinates of the square
    # @return [String] the square in algebraic notation
    # @example
    #   board.position_for([4, 3]) #=> "e4"
    #
    def position_for(coordinates)
      file, rank = coordinates
      INDEX_TO_FILE[file] + INDEX_TO_RANK[rank]
    end

    # @return [String] the board in human readable format with unicode
    #   pieces
    #
    def inspect
      squares.transpose.reverse.map do |row|
        row.map { |chr| UNICODE_PIECES[chr] }.join(' ')
      end.join("\n")
    end

    # @return [PGN::Board] a copy of self. Copies the 128-cell 0x88 array;
    #   mutations to the copy do not affect the original.
    #
    def dup
      copy = PGN::Board.allocate
      copy.instance_variable_set(:@cells, @cells.dup)
      copy
    end

    # -- 0x88 hot-path API (integer indices) ---------------------------------

    # The 0x88 index of an algebraic square name.
    #
    # @param square [String] e.g. "e4"
    # @return [Integer] idx = rank * 16 + file
    #
    def index_of(square)
      (rank_of(square) * 16) + file_of(square)
    end

    # The 0x88 index of zero-indexed file/rank coordinates.
    #
    # @return [Integer] idx = rank * 16 + file
    #
    def index_for(file, rank)
      (rank * 16) + file
    end

    # Looks up a piece by 0x88 index. The caller is responsible for having
    # already verified the index is on-board (`(idx & 0x88).zero?`); reading
    # an off-board index simply returns nil.
    #
    # @param idx [Integer] a 0x88 square index
    # @return [String, nil] the piece on that square
    #
    def at_index(idx)
      @cells[idx]
    end

    # Places a piece on a 0x88 index. Returns self.
    #
    # @param idx [Integer] a 0x88 square index
    # @param piece [String, nil]
    # @return [self]
    #
    def update_index(idx, piece)
      @cells[idx] = piece
      self
    end

    # Applies a batch of integer-indexed changes. The replay hot path uses
    # this so it never allocates square-name strings or `[file, rank]`
    # coordinate arrays.
    #
    # @param changes [Hash<Integer, <String, nil>>]
    # @return [self]
    #
    def apply!(changes)
      changes.each { |idx, piece| @cells[idx] = piece }
      self
    end

    # Whether a 0x88 index is on the board (see the class doc for the
    # bitmask this tests).
    #
    # @param idx [Integer] a 0x88 square index
    # @return [Boolean]
    #
    def on_board?(idx)
      (idx & 0x88).zero? # rubocop:disable Style/BitwisePredicate
    end

    # The algebraic square name of a 0x88 index.
    #
    # @param idx [Integer] a 0x88 square index
    # @return [String] e.g. "e4"
    #
    def square_name(idx)
      INDEX_TO_FILE[idx & 0x0F] + INDEX_TO_RANK[idx >> 4]
    end

    private

    def file_of(square)
      square.getbyte(0) - 97
    end

    def rank_of(square)
      square.getbyte(1) - 49
    end
  end
end
