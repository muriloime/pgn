# Changelog

## Unreleased

### Added
- Parser now accepts tag values containing unescaped double-quotes (e.g.
  `[Event "IRT BLITZ "Sub Zonal""]`), a form found in real-world PGN files.
  Previously the parser raised on such input.
- New fixtures `spec/pgn_files/doublequotes.pgn` and
  `spec/pgn_files/specialcharacters.pgn`, plus tests for parsing tag values
  with inner quotes and for the `Encoding` argument of `PGN.parse`.

### Changed
- `spec/spec_helper.rb`: removed the deprecated
  `treat_symbols_as_metadata_keys_with_true_values` config (drops an RSpec
  deprecation warning).

### Credits
- The double-quotes parsing fix and the new fixtures were contributed by
  Alexis Vargas (https://github.com/lexisvar), ported from the `pgn3` fork.
