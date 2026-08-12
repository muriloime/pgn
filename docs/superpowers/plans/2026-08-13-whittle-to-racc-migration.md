# Plan: Migrate PGN parser from whittle to Racc + StringScanner

Date: 2026-08-13
Branch: `racc-migration` (branched from `faster` after baseline commit)
Fallback: tag `pre-racc` on the pre-migration commit.

## Goal

Replace the abandoned `whittle` (0.0.8, 2011) parser with a maintained,
stdlib-only `Racc` + `StringScanner` parser that produces **byte-compatible**
`PGN::Game` objects: identical `tags`, `result`, `moves` (as `MoveText` with
`annotation`/`comment`/`variations`), `pgn` (verbatim raw text), and `comment`.
Keep every existing spec green and add many new parser tests.

## Why

- whittle is unmaintained (14 years old) and accounts for ~80% of parse
  allocations (`terminal.rb` 77k + `parser.rb` 22k of 125k per 50 games).
- A `StringScanner` (C ext) lexer replaces whittle's pure-Ruby per-token regex
  churn — the dominant cost.
- Racc is stdlib runtime (`racc/parser`), maintained; drops whittle, adds no
  runtime gem.
- Also fixes the `@@pgn`/`@@game_comment` class-variable reentrancy bug
  (state moves to parser instances) and the O(n²) `@@pgn` string building.

## Safety strategy (repo stays green at every checkpoint)

1. Keep `whittle` fully working as `PGN::WhittleParser`; `PGN.parse` uses it
   until the new parser is proven.
2. Build `PGN::RaccParser` in parallel.
3. **Golden-equivalence spec**: parse all 14 fixtures + every `parser_spec`
   example string with BOTH parsers; assert the resulting `PGN::Game` objects
   are equal (tags/result/moves/pgn/comment). Iterate the new parser until
   green. This makes the fiddly `game.pgn` verbatim-text and `comment`
   semantics **convergent, not hand-modelled**.
4. Cut over `PGN::Parser` → `PGN::RaccParser` only when golden + full suite
   pass.
5. Remove `whittle` only after the full suite is green on Racc alone.

If any task cannot be made green, revert to whittle (repo stays on
`pre-racc`-equivalent state) and report partial progress.

## Tasks

### Task 0 — Stabilize baseline

- Commit the in-tree WIP (double-quotes regex + `Encoding` arg +
  `spec_helper` cleanup + `board.rb` `@owned` COW refinement + `game.rb`
  gsub-skip + new fixtures + CHANGELOG + this plan + the existing
  efficiency plans) so the migration starts from a known, committed state.
- Tag `pre-racc`. Branch `racc-migration`. Verify `bundle exec rspec` green.

### Task 1 — Preserve whittle as `PGN::WhittleParser`

- Rename `class Parser < Whittle::Parser` → `class WhittleParser` in
  `lib/pgn/parser.rb`; keep `PGN::Parser` as a thin module/facade that
  currently delegates to `WhittleParser` (`PGN.parse` unchanged behavior).
- Add `spec/golden_equivalence_spec.rb` scaffold that iterates all fixtures
  and asserts `WhittleParser` vs `RaccParser` (RaccParser stubbed to skip
  until Task 4). For now it just documents WhittleParser output is stable.

### Task 2 — StringScanner lexer

- New `lib/pgn/lexer.rb`: `PGN::Lexer` yielding tokens `[:type, value, offset,
  line]`. Reuses the **exact** whittle regexes (string, comment with `\g<1>`
  recursion, game_termination, san_move, move_number_indication, tag_name,
  numeric_annotation_glyph) so tokenization matches; skips `wsp` and
  `%`-comments. Token precedence tuned for PGN (terminations and san_move
  before move_number so `1-0`/`0-0` tokenize correctly).
- New `spec/lexer_spec.rb`: token-level tests for every token type on
  representative inputs (including UTF-8 en-dash, inner quotes, nested
  comments, NAGs, `--`, castling `0-0`/`O-O`, promotion, check/mate).

### Task 3 — Racc grammar + generated parser

- New `lib/pgn/pgn_parser.y`: Racc grammar mirroring the whittle rules.
  `variation_list` left-recursive (preserves variation order — fixes the
  current "reverses on parse" quirk; `game_spec` compares order-independently
  so this is safe). Recursive comments handled in the lexer.
- `Rakefile`: `rake generate` runs `racc lib/pgn/pgn_parser.y -o
  lib/pgn/pgn_parser.rb`; commit the generated file (no runtime racc dep for
  users). Add `racc` as a dev dependency in the gemspec.
- New `PGN::RaccParser` (`lib/pgn/racc_parser.rb`): `parse(input)` → array of
  game hashes `{tags:, result:, moves:, pgn:, comment:}` matching the
  whittle shape. Lexer/parse state held on the instance (no class vars).
  `pgn` computed from per-game token offsets (start of first token → end of
  game_termination); converged via the golden test.

### Task 4 — Golden equivalence

- Complete `spec/golden_equivalence_spec.rb`: for each fixture and each
  parser_spec example string, assert
  `whittle_games == racc_games` where equality covers tags, result, each
  move's notation/annotation/comment/variations (recursively), pgn, comment.
- Iterate lexer token order + grammar + `pgn` slicing until 100% green.

### Task 5 — Cut over

- `PGN::Parser` → delegate to `PGN::RaccParser`. Run the **full** suite
  (parser_spec, game_spec round-trip-all-fixtures, serializer_spec,
  board/move/move_calculator/position/fen specs). All must pass.

### Task 6 — Many new explicit parser tests

- Expand `spec/parser_spec.rb` with hardcoded-expected cases (no whittle
  dependency): empty game, no-moves game, single move, comments, nested
  comments, multiline comments, variations (incl. nested), annotations,
  NAGs (`$1`, `?!`, `!?`), FEN tag, `--` move, castling `0-0`/`O-O-O`,
  promotion `=Q`, check `+`, mate `#`, double-quotes-in-tag-value, UTF-8
  special chars + `Encoding` arg, multiple games, game comment before moves,
  `empty_variation_move`, `1/2-1/2` and `*` terminations.

### Task 7 — Remove whittle

- Delete `PGN::WhittleParser` and `require 'whittle'`.
- Drop `whittle` from `pgn2.gemspec` runtime deps.
- Remove `spec/golden_equivalence_spec.rb` (its job is done) OR convert it to
  committed-snapshot expectations (keep coverage but no whittle).
- `git grep -i whittle` must be clean.

### Task 8 — Bench + verify

- Re-run `rake bench`; record parse-only and parse+replay before/after in
  `bench/IMPROVEMENTS.md` (add a "parser migration" section).
- Final: `bundle exec rspec` all green; `git grep -i whittle` clean;
  summarize deltas.
