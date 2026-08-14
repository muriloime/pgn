# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'pgn'

POSITIONS = {
  'startpos' => 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  'kiwipete' => 'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
  'pos3' => '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1',
  'pos5' => 'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8'
}.freeze

unless PGN::Bitboard.const_defined?(:Engine)
  warn 'PGN::Bitboard::Engine not compiled — build with `bundle exec rake compile` first.'
  exit 1
end

def monotonic
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

POSITIONS.each do |name, fen|
  e = PGN::Bitboard::Engine.new(fen)
  [4, 5].each do |d|
    nodes = e.perft(d)
    t0 = monotonic
    e.perft(d)
    t = monotonic - t0
    nps = (nodes.to_f / t).to_i
    printf("%-10s d%d  nodes=%-12d  %.3fs  %d nps\n", name, d, nodes, t, nps)
  end
end
