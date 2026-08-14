require 'English'
lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'pgn/version'

Gem::Specification.new do |spec|
  spec.name          = 'pgn2'
  spec.version       = PGN::VERSION
  spec.authors       = ['Stacey Touset', 'Murilo Vasconcelos']
  spec.email         = ['stacey@touset.org', 'muriloime@gmail.com']
  spec.description   = 'A PGN parser and FEN generator for Ruby'
  spec.summary       = 'A PGN parser for Ruby'
  spec.homepage      = 'https://github.com/muriloime/pgn'
  spec.licenses      = ['MIT', 'MPL-2.0']
  spec.required_ruby_version = '>= 3.0'

  spec.metadata = {
    'homepage_uri' => 'https://github.com/muriloime/pgn',
    'source_code_uri' => 'https://github.com/muriloime/pgn',
    'bug_tracker_uri' => 'https://github.com/muriloime/pgn/issues',
    'changelog_uri' => 'https://github.com/muriloime/pgn/blob/main/CHANGELOG.md',
    'rubygems_mfa_required' => 'true'
  }

  spec.files         = `git ls-files`.split($INPUT_RECORD_SEPARATOR)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.extensions = ['ext/pgn2_native/extconf.rb']
  spec.add_dependency 'rb_sys', '~> 0.9.39'
  spec.add_development_dependency 'rake-compiler', '~> 1.2'
  spec.add_development_dependency 'rake-compiler-dock', '~> 1.6'

  spec.add_development_dependency 'benchmark-ips'
  spec.add_development_dependency 'bundler', '~> 2.3'
  spec.add_development_dependency 'bundler-audit'
  spec.add_development_dependency 'memory_profiler'
  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'racc'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rubocop', '~> 1.60'
end
