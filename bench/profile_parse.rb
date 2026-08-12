# frozen_string_literal: true
# Measures parse and parse+replay throughput/allocations on a synthetic
# multi-game corpus. Run with:  bundle exec ruby bench/profile_parse.rb
# Captured baseline: bench/baseline_parse.txt (via rake bench:parse)

$LOAD_PATH.unshift(File.expand_path('lib', File.join(__dir__, '..')))
require 'pgn'
require 'memory_profiler'
require 'benchmark/ips'

EXAMPLES = File.join(__dir__, '..', 'examples')
IMMORTAL = File.read(File.join(EXAMPLES, 'immortal_game.pgn')).strip
N        = Integer(ENV.fetch('BENCH_N', '500'))
CORPUS   = (IMMORTAL + "\n\n") * N

puts "Corpus: #{N} copies of the immortal game"

# --- 1. Parse-only allocations ------------------------------------------------
parse_report = MemoryProfiler.report { PGN.parse(CORPUS) }
puts "\n=== 1. Parse-only allocations (#{N} games) ==="
puts "total_allocated objects: #{parse_report.total_allocated}"
puts "total_allocated bytes:   #{parse_report.total_allocated_memsize}"

# --- 2. Parse + replay allocations (real-world load) --------------------------
full_report = MemoryProfiler.report { PGN.parse(CORPUS).each(&:positions) }
puts "\n=== 2. Parse + replay allocations (#{N} games) ==="
puts "total_allocated objects: #{full_report.total_allocated}"
puts "total_allocated bytes:   #{full_report.total_allocated_memsize}"

# --- 3. Parse-only throughput -------------------------------------------------
puts "\n=== 3. Parse-only throughput (ips) ==="
Benchmark.ips do |x|
  x.config(time: 5, warmup: 1)
  x.report("parse #{N} games") { PGN.parse(CORPUS) }
end

# --- 4. Parse + replay throughput ---------------------------------------------
puts "\n=== 4. Parse + replay throughput (ips) ==="
Benchmark.ips do |x|
  x.config(time: 5, warmup: 1)
  x.report("parse+replay #{N} games") { PGN.parse(CORPUS).each(&:positions) }
end

puts "\nDone. Compare this file against bench/baseline_parse.txt after optimizations."
