# frozen_string_literal: true

require 'pgn/pgn_parser'

module PGN
  # {PGN::Parser} is the public entry point for parsing PGN text into a list
  # of game hashes. It delegates to the stdlib Racc + StringScanner parser
  # {PGN::PgnParser}.
  class Parser
    # @param input [String] the raw PGN text (already force-encoded by the
    #   caller, e.g. via {PGN.parse}).
    # @return [Array<Hash>] one Hash per game, with keys +:tags+, +:result+,
    #   +:moves+, +:pgn+, +:comment+.
    def parse(input)
      PGN::PgnParser.new.parse(input)
    end
  end
end
