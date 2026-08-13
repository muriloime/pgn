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

# --- 7. Last-position-only: lazy each_position vs eager positions ---------
# Both paths build a fresh PGN::Game so the Game construction cost cancels;
# the difference is building the full positions array (eager) vs not (lazy).
lazy_report = MemoryProfiler.report do
  game = PGN::Game.new(SAN, GAME.first.tags, GAME.first.result)
  last = nil
  game.each_position { |p| last = p }
  last
end

eager_report = MemoryProfiler.report do
  PGN::Game.new(SAN, GAME.first.tags, GAME.first.result).positions.last
end

puts "\n=== 7. Last-position-only (#{PLY} plies): lazy vs eager ==="
puts "lazy  total_allocated objects: #{lazy_report.total_allocated}"
puts "lazy  total_allocated bytes:   #{lazy_report.total_allocated_memsize}"
puts "eager total_allocated objects: #{eager_report.total_allocated}"
puts "eager total_allocated bytes:   #{eager_report.total_allocated_memsize}"

# --- 8. SAN generation (Notation.san reconstruction from coords) -----------
# Precompute one (position, from, to, promotion) tuple per ply outside the
# measured block, so only Notation.san (reaches?/attacked?/disambiguation)
# is measured — the path the knight/king attack masks target.
san_inputs = []
begin
  pos = GAME.first.starting_position
  SAN.each do |m|
    mv = PGN::Move.new(m, pos.player)
    calc = PGN::MoveCalculator.new(pos.board, mv)
    san_inputs << [pos, calc.origin, mv.destination, mv.promotion]
    pos = pos.move(m)
  end
end

san_report = MemoryProfiler.report do
  san_inputs.each { |pos, from, to, promo| PGN::Notation.san(pos, from, to, promo) }
end

puts "\n=== 8. SAN generation x#{san_inputs.length} (target of attack masks) ==="
puts "total_allocated objects: #{san_report.total_allocated}"
puts "total_allocated bytes:   #{san_report.total_allocated_memsize}"

puts "\n=== 8b. SAN throughput (ips) ==="
Benchmark.ips do |x|
  x.config(time: 5, warmup: 1)
  x.report('san immortal') do
    san_inputs.each { |pos, from, to, promo| PGN::Notation.san(pos, from, to, promo) }
  end
end

# --- 9. Retained memory: lazy each_position vs eager positions ------------
# Objects allocated during the report that are STILL ALIVE at its end.
# Both reports keep the Game alive in an outer var so the difference is
# purely what the API memoizes: lazy streams without memoizing the array;
# eager memoizes the full positions array on the Game.
lazy_game = nil
lazy_retained = MemoryProfiler.report do
  lazy_game = PGN::Game.new(SAN, GAME.first.tags, GAME.first.result)
  lazy_game.each_position { |_| } # stream; do NOT memoize the array
end

eager_game = nil
eager_retained = MemoryProfiler.report do
  eager_game = PGN::Game.new(SAN, GAME.first.tags, GAME.first.result)
  eager_game.positions # memoize the full array on the Game
end

puts "\n=== 9. Retained memory (#{PLY} plies): lazy vs eager ==="
puts "lazy  total_retained objects: #{lazy_retained.total_retained}"
puts "lazy  total_retained bytes:   #{lazy_retained.total_retained_memsize}"
puts "eager total_retained objects: #{eager_retained.total_retained}"
puts "eager total_retained bytes:   #{eager_retained.total_retained_memsize}"

puts "\nDone. Compare this file against bench/baseline_moves.txt after optimizations."
