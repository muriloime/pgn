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
    INDEX_TO_FILE = FILE_TO_INDEX.map(&:reverse).to_h

    RANK_TO_INDEX = ('1'..'8').each_with_index.to_h
    INDEX_TO_RANK = RANK_TO_INDEX.map(&:reverse).to_h

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

    attr_accessor :squares

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
    # String squares are parsed with getbyte arithmetic (a=0x61, '1'=0x31)
    # so the common string lookup allocates nothing.
    def at(arg0, arg1 = nil)
      return squares[arg0][arg1] unless arg1.nil?
      squares[arg0.getbyte(0) - 97][arg0.getbyte(1) - 49]
    end

    # @param changes [Hash<String, <String, nil>>] changes to make to the board
    # @return [self]
    # @example
    #   board.change!({"e2" => nil, "e4" => "P"})
    #
    def change!(changes)
      changes.each do |square, piece|
        update(square, piece)
      end
      self
    end

    # @param square [String] the square in algebraic notation
    # @param piece [String, nil] the piece to put on the square
    # @return [self]
    # @example
    #   board.update("e4", "P")
    #
    # Copy-on-write: clone only the column being mutated so unchanged
    # columns stay shared with any board this one was duped from.
    def update(square, piece)
      file = square.getbyte(0) - 97
      rank = square.getbyte(1) - 49
      squares[file] = squares[file].dup
      squares[file][rank] = piece
      self
    end

    # @param position [String] the square in algebraic notation
    # @return [Array<Integer>] the coordinates of the square
    # @example
    #   board.coordinates_for("e4") #=> [4, 3]
    #
    # @param position [String] the square in algebraic notation
    # @return [Array<Integer>] the coordinates of the square
    # @example
    #   board.coordinates_for("e4") #=> [4, 3]
    #
    def coordinates_for(position)
      [position.getbyte(0) - 97, position.getbyte(1) - 49]
    end

    # @param coordinates [Array<Integer>] the coordinates of the square
    # @return [String] the square in algebraic notation
    # @example
    #   board.position_for([4, 3]) #=> "e4"
    #
    def position_for(coordinates)
      file, rank = coordinates
      file_chr = INDEX_TO_FILE[file]
      rank_chr = INDEX_TO_RANK[rank]
      [file_chr, rank_chr].join('')
    end

    # @return [String] the board in human readable format with unicode
    #   pieces
    #
    def inspect
      squares.transpose.reverse.map do |row|
        row.map { |chr| UNICODE_PIECES[chr] }.join(' ')
      end.join("\n")
    end

    # @return [PGN::Board] a copy of self. The outer array is copied; the
    # 8 column arrays are shared and cloned lazily by #update on first
    # mutation (copy-on-write).
    #
    def dup
      PGN::Board.new(squares.dup)
    end
  end
end
