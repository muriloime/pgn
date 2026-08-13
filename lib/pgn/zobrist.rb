# frozen_string_literal: true

module PGN
  # Zobrist hashing keys for incremental position hashing. All keys are
  # fixed 64-bit pseudo-random Integers generated once at load time from a
  # frozen seed so hashes are stable for the life of the process.
  #
  # Indexing is by 0x88 square index (0..127); off-board indices are
  # allocated but never read.
  module Zobrist
    SEED = 0x1234_5678_9abc_def1

    # Deterministic pseudo-random generator so hashes are stable per
    # process and across machines (no Kernel#rand).
    def self.gen
      @gen ||= Random.new(SEED)
    end
    private_class_method :gen

    def self.rand64
      gen.rand(1 << 64)
    end
    private_class_method :rand64

    PIECES = %w[P N B R Q K p n b r q k].freeze

    table = {}
    PIECES.each do |piece|
      table[piece] = Array.new(128) { rand64 }
    end
    TABLE = table.freeze

    SIDE = rand64
    CASTLING = { 'K' => rand64, 'Q' => rand64, 'k' => rand64, 'q' => rand64 }.freeze
    EP_FILE = Array.new(8) { rand64 }.freeze

    def self.table
      TABLE
    end

    def self.side
      SIDE
    end

    def self.castling
      CASTLING
    end

    def self.ep_file
      EP_FILE
    end

    # @param board [PGN::Board]
    # @param player [Symbol] :white or :black
    # @param castling [Array<String>] e.g. %w[K Q k q]
    # @param en_passant [String, nil] e.g. "e3" or nil
    # @return [Integer] the Zobrist hash of the position
    def self.seed(board, player, castling, en_passant)
      h = 0
      0.upto(7) do |rank|
        0.upto(7) do |file|
          idx = (rank * 16) + file
          piece = board.at_index(idx)
          h ^= TABLE[piece][idx] if piece
        end
      end
      h ^= SIDE if player == :black
      castling.to_a.each { |right| h ^= CASTLING[right] if CASTLING.key?(right) }
      h ^= EP_FILE[en_passant.getbyte(0) - 97] if en_passant && !en_passant.empty?
      h
    end

    # Derive the hash for the position after a move by XOR-ing only the
    # state that changed: side to move, removed castling rights, the old/new
    # en-passant file, and the piece(s) on every touched square.
    #
    # @param position [PGN::Position] the pre-move position
    # @param calculator [PGN::MoveCalculator] (carries the move)
    # @param new_board [PGN::Board]
    # @param new_castling [Array<String>]
    # @param new_ep [String, nil]
    # @return [Integer]
    def self.update(position, calculator, new_board, new_castling, new_ep)
      h = position.zobrist ^ SIDE

      (position.castling - new_castling).each do |right|
        h ^= CASTLING[right] if CASTLING.key?(right)
      end

      h ^= ep_file_key(position.en_passant)
      h ^= ep_file_key(new_ep)

      each_changed_index(calculator).each do |idx|
        h ^= piece_key(position.board.at_index(idx), idx)
        h ^= piece_key(new_board.at_index(idx), idx)
      end

      h
    end

    def self.ep_file_key(en_passant)
      return 0 if en_passant.nil? || en_passant.empty?

      EP_FILE[en_passant.getbyte(0) - 97]
    end
    private_class_method :ep_file_key

    def self.piece_key(piece, idx)
      return 0 if piece.nil?

      TABLE[piece][idx]
    end
    private_class_method :piece_key

    # Yields each 0x88 index whose piece may have changed during the move.
    # For castling this comes from MoveCalculator::CASTLING; for normal
    # moves it is origin, destination, and the en-passant-captured pawn.
    # Nil indices (e.g. the "--" no-op move has no origin/destination) are
    # skipped.
    def self.each_changed_index(calculator)
      move = calculator.move
      if move.castle
        MoveCalculator::CASTLING[move.castle].each_key.to_a
      else
        idxs = []
        origin = calculator.instance_variable_get(:@origin_idx)
        idxs << origin if origin
        dest = calculator.send(:dest_idx)
        idxs << dest if dest
        if (ep = calculator.send(:en_passant_capture))
          idxs << ep
        end
        idxs
      end
    end
    private_class_method :each_changed_index
  end
end
