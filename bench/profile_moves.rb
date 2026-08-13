# frozen_string_literal: true
# Measures per-move allocation and replay throughput for the move pipeline.
# Run with:  bundle exec ruby bench/profile_moves.rb
# Captured baseline: bench/baseline_moves.txt (via rake bench:moves)

$LOAD_PATH.unshift(File.expand_path('lib', File.join(__dir__, '..')))
require 'pgn'
require 'memory_profiler'
require 'benchmark/ips'

EXAMPLES = File.join(__dir__, '..', 'examples')
IMMORTAL = File.read(File.join(EXAMPLES, 'immortal_game.pgn'))
GAME     = PGN.parse(IMMORTAL).freeze
SAN      = GAME.first.moves.map(&:notation).freeze
PLY      = SAN.length

puts "Workload: immortal game, #{PLY} plies"

# --- 1. Replay allocations (move application only, no parse) -----------------
replay_report = MemoryProfiler.report do
  pos = GAME.first.starting_position
  SAN.each { |m| pos = pos.move(m) }
end

puts "\n=== 1. Replay allocations (#{PLY} plies, no parse) ==="
puts "total_allocated objects: #{replay_report.total_allocated}"
puts "total_allocated bytes:   #{replay_report.total_allocated_memsize}"

# --- 2. Board#dup share (the flat-board optimization target) ------------------
dup_report = MemoryProfiler.report { PLY.times { GAME.first.starting_position.board.dup } }

puts "\n=== 2. Board#dup x#{PLY} (target of flat-board COW) ==="
puts "total_allocated objects: #{dup_report.total_allocated}"
puts "total_allocated bytes:   #{dup_report.total_allocated_memsize}"

# --- 3. Board#at(str) share (the at(str) optimization target) ---------------
start_board = GAME.first.starting_position.board
at_report = MemoryProfiler.report { 1000.times { start_board.at('e4') } }

puts "\n=== 3. Board#at(str) x1000 (target of coord-arithmetic at) ==="
puts "total_allocated objects: #{at_report.total_allocated}"
puts "total_allocated bytes:   #{at_report.total_allocated_memsize}"

# --- 4. Replay throughput (fresh game each iter to defeat memoization) ------
puts "\n=== 4. Replay throughput (ips, excluding parse) ==="
Benchmark.ips do |x|
  x.config(time: 5, warmup: 1)
  x.report('replay immortal') do
    PGN::Game.new(SAN, GAME.first.tags, GAME.first.result).positions
  end
end

# --- 5. FEN generation (target of the direct-0x88 FEN builder) -------------
positions = GAME.first.positions

fen_report = MemoryProfiler.report do
  positions.each { |p| p.to_fen.to_s }
end

puts "\n=== 5. FEN generation x#{positions.length} (target of direct-0x88 FEN) ==="
puts "total_allocated objects: #{fen_report.total_allocated}"
puts "total_allocated bytes:   #{fen_report.total_allocated_memsize}"

puts "\n=== 6. FEN throughput (ips) ==="
Benchmark.ips do |x|
  x.config(time: 5, warmup: 1)
  x.report('fen immortal') do
    positions.each { |p| p.to_fen.to_s }
  end
end

puts "\nDone. Compare this file against bench/baseline_moves.txt after optimizations."
