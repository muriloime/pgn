# frozen_string_literal: true

# Load the native bitboard engine if the compiled extension is available.
# End users get the precompiled native gem (no Rust toolchain needed); if the
# extension is absent (e.g. running from a source checkout without `rake
# compile`), the load fails silently so the rest of the gem still works. Code
# that calls PGN::Bitboard::Engine will raise NameError naturally.
require "pgn2_native/pgn2_native" rescue LoadError
