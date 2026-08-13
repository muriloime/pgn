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
  end
end
