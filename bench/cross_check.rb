# frozen_string_literal: true
# Cross-check the native Rust engine against Stockfish (independent oracle):
# correctness (perft node counts) and timing (nps). Requires `stockfish`.
require 'open3'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'pgn'

unless PGN::Bitboard.const_defined?(:Engine)
  warn 'PGN::Bitboard::Engine not compiled — run `bundle exec rake compile` first.'
  exit 1
end

POSITIONS = {
  'startpos' => 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  'kiwipete' => 'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
  'pos3'     => '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1',
  'pos4'     => 'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1',
  'pos5'     => 'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8',
  'pos6'     => 'r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10'
}

def monotonic
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

def stockfish_perft(fen, depth)
  cmd = "position fen #{fen}\ngo perft #{depth}\nquit\n"
  out, _ = Open3.capture2('stockfish', stdin_data: cmd)
  m = out.match(/Nodes searched:\s+(\d+)/)
  m && m[1].to_i
end

puts "name       depth  native           stockfish        match   native_nps   sf_nps"
puts '-' * 80
all_match = true
POSITIONS.each do |name, fen|
  e = PGN::Bitboard::Engine.new(fen)
  depths = name == 'startpos' ? [5, 6] : [4, 5]
  depths.each do |d|
    nodes = e.perft(d)
    t0 = monotonic
    e.perft(d)
    t = monotonic - t0
    native_nps = (nodes.to_f / t).to_i

    s0 = monotonic
    sf_nodes = stockfish_perft(fen, d)
    st = monotonic - s0
    sf_nps = (sf_nodes.to_f / st).to_i

    ok = (nodes == sf_nodes)
    all_match = false unless ok
    printf("%-10s  d%d   %-13d   %-13d   %s   %-11d  %d\n",
           name, d, nodes, sf_nodes, ok ? 'OK' : 'DIFF', native_nps, sf_nps)
  end
end

puts '-' * 80
puts all_match ? 'ALL POSITIONS MATCH STOCKFISH ✅' : 'MISMATCH DETECTED ❌'
exit(all_match ? 0 : 1)
