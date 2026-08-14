# frozen_string_literal: true

# Benchmark PGN::Position#legal_moves end-to-end (FEN round-trip +
# native legal-gen + Ruby string materialization) to decide whether
# shipping the method meets the < 1 ms middlegame gate.
#
# Run: bundle exec ruby bench/legal_moves.rb

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'pgn'

unless PGN::Bitboard.const_defined?(:Engine)
  warn 'PGN::Bitboard::Engine not compiled — build with `bundle exec rake compile` first.'
  exit 1
end

POSITIONS = {
  'startpos' => 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  'middlegame' => 'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4',
  'kiwipete' => 'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1'
}.freeze

def monotonic
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

POSITIONS.each do |name, fen|
  pos = PGN::FEN.new(fen).to_position
  # warmup
  100.times { pos.legal_moves }
  n = 2000
  t0 = monotonic
  n.times { pos.legal_moves }
  elapsed = monotonic - t0
  us = (elapsed / n) * 1_000_000.0
  count = pos.legal_moves.length
  printf("%-12s moves=%-3d  %.1f us/call  (%.3f ms)\n", name, count, us, us / 1000.0)
end
