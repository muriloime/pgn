require "bundler/gem_tasks"

namespace :bench do
  desc "Run move/board profiling and write bench/baseline_moves.txt"
  task :moves do
    sh "bundle exec ruby bench/profile_moves.rb > bench/baseline_moves.txt"
    puts File.read("bench/baseline_moves.txt")
  end

  desc "Run parse profiling and write bench/baseline_parse.txt"
  task :parse do
    sh "bundle exec ruby bench/profile_parse.rb > bench/baseline_parse.txt"
    puts File.read("bench/baseline_parse.txt")
  end
end

desc "Run all benchmarks and (re)write bench/baseline_*.txt"
task :bench => ["bench:moves", "bench:parse"]
