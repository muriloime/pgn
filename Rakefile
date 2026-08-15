require 'bundler/gem_tasks'
require 'rake/extensiontask'
require 'rubocop/rake_task'

spec = Gem::Specification.load('pgn2.gemspec')
Rake::ExtensionTask.new('pgn2_native', spec) do |ext|
  ext.ext_dir = 'ext/pgn2_native'
  ext.lib_dir = 'lib/pgn2_native'

  # Cross-compile prebuilt platform gems via rake-compiler-dock. The list
  # here is the single source of truth for {release-gems.yml}; keep them in
  # sync. rb-sys's extconf picks up the Rake::ExtensionTask cross env vars.
  ext.cross_compile  = true
  ext.cross_platform = %w[
    x86_64-linux
    aarch64-linux
    x86_64-darwin
    aarch64-darwin
  ]
  ext.cross_config_options << '--enable-cross'
end

RuboCop::RakeTask.new

namespace :bench do
  desc 'Run move/board profiling and write bench/baseline_moves.txt'
  task :moves do
    sh 'bundle exec ruby bench/profile_moves.rb > bench/baseline_moves.txt'
    puts File.read('bench/baseline_moves.txt')
  end

  desc 'Run parse profiling and write bench/baseline_parse.txt'
  task :parse do
    sh 'bundle exec ruby bench/profile_parse.rb > bench/baseline_parse.txt'
    puts File.read('bench/baseline_parse.txt')
  end

  desc 'Run perft benchmark (native Rust bitboard engine)'
  task :perft do
    sh 'bundle exec ruby bench/perft.rb'
  end
end

desc 'Run all benchmarks and (re)write bench/baseline_*.txt'
task bench: ['bench:moves', 'bench:parse']

# Cross-compile prebuilt native platform gems via rake-compiler-dock.
# Produces fat-binary platform gems so end users (and the chessellence
# Docker build) need no Rust toolchain. Requires Docker locally.
namespace :native do
  desc 'Remove cross-compiled build artifacts and pkg/ (Docker build prep)'
  task :clean do
    Rake::Task['clean'].invoke
    rm_rf 'pkg' if Dir.exist?('pkg')
  end

  desc 'Cross-compile prebuilt platform gems via rake-compiler-dock'
  task :gem do
    require 'rake_compiler_dock'
    RakeCompilerDock.sh <<-SH, verbose: true
      bundle install && rake native:clean && rake cross native gem
    SH
  end
end
