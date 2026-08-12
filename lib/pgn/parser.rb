require 'pgn/pgn_parser'

module PGN
  # {PGN::Parser} is the public entry point for parsing PGN text into a list
  # of game hashes. It delegates to a concrete backend parser (currently the
  # stdlib Racc + StringScanner parser {PGN::PgnParser}).
  #
  # The +backend+ class attribute is retained so callers (tests, benchmarks)
  # can substitute an alternative parser responding to +new.parse(pgn_string)+.
  class Parser
    class << self
      # The backend parser class used by {.parse}.
      # @return [Class]
      attr_accessor :backend
    end

    # Default backend is the stdlib Racc + StringScanner parser.
    self.backend = PGN::PgnParser

    # @param input [String] the raw PGN text (already force-encoded by the
    #   caller, e.g. via {PGN.parse}).
    # @return [Array<Hash>] one Hash per game, with keys +:tags+, +:result+,
    #   +:moves+, +:pgn+, +:comment+.
    def parse(input)
      self.class.backend.new.parse(input)
    end
  end
end
