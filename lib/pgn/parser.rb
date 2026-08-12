require 'pgn/whittle_parser'

module PGN
  # {PGN::Parser} is the public entry point for parsing PGN text into a list
  # of {PGN::Game} objects. It delegates to a concrete backend parser.
  #
  # During the migration from the abandoned +whittle+ gem to a stdlib
  # +Racc+ + StringScanner parser, the backend is switchable here:
  # {PGN::WhittleParser} (legacy) or {PGN::RaccParser} (target).
  #
  class Parser
    # The backend parser class used by {.parse}.
    #
    # @return [Class] a parser responding to +new.parse(pgn_string)+ that
    #   returns an Array of game Hashes with keys +:tags+, +:result+,
    #   +:moves+, +:pgn+, +:comment+.
    class << self
      attr_accessor :backend
    end

    # Default backend is the stdlib Racc + StringScanner parser.
    self.backend = PGN::PgnParser

    # @param input [String] the raw PGN text (already force-encoded by the
    #   caller, e.g. via {PGN.parse}).
    # @return [Array<Hash>] one Hash per game.
    def parse(input)
      self.class.backend.new.parse(input)
    end
  end
end
