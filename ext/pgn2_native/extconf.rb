require "mkmf"
require "rb_sys/mkmf"

# The ext lives in a Cargo workspace whose root manifest is virtual, so
# tell cargo which member to build.
create_rust_makefile("pgn2_native/pgn2_native") do |builder|
  builder.extra_cargo_args = ["--package", "pgn2_native"]
end
