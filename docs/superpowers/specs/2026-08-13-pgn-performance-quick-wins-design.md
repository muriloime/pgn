# PGN2 performance quick wins — Approach A (quick, behavior-compatible micro-opts)

> "Approach A" denotes the safe, allocation-focused track. A later, larger
> design (Approach B) will cover architectural changes: piece-location indexes,
> lazy position computation, and a coordinate-only internal board
> representation.

## Goal

Make the gem faster on the combined **parse + replay** workload after the
whittle → Racc migration, with only safe, behavior-compatible micro-optimizations
(no public API changes, no serialized-output changes).

## Scope

This design covers the five highest-ROI quick wins identified in the profiles:

1. Remove per-token `PGN::Lexer::Token` allocation on the parser hot path.
2. Avoid double `MoveText` wrapping in `PGN::Game#moves=`.
3. Replace `PGN::Move` SAN regex with hand-rolled parsing.
4. Reduce small temporary allocations in `PGN::Position#move` and
   `PGN::MoveCalculator`.
5. Promote the Racc parse baseline to canonical and record new baselines in
   `bench/baseline_*.txt` after verification.

Out of scope: larger architecture changes such as piece-location indexes,
lazy position computation, or coordinate-only internal board representation.

## Context / baseline

Measured on the current checkout with `bundle exec rake bench` (Racc parser);
these are the canonical `bench/baseline_*.txt` values refreshed as the
prerequisite in item 5:

- **Parse-only:** ~125 k objects / 7.88 MB for 100 copies of the immortal game
  (= 626,037 objects / 39.4 MB for the 500-game corpus in `bench/baseline_parse.txt`).
- **Parse + replay:** ~337 k objects / 21.6 MB for the same per-100 ratio
  (= 1,683,087 objects / 108 MB for 500 games).
- **Replay only:** 2,177 objects / 142 kB for the 45-ply immortal game
  (`bench/baseline_moves.txt`).

Historical snapshots are kept in `bench/baseline_*.pre-quickwins.txt` and
`bench/baseline_parse.racc.txt` for reference. The previously committed
`baseline_parse.txt` held stale pre-migration whittle numbers and has been
overwritten by the current Racc output.

Top allocation hot spots:

- `PGN::Lexer::Token` creation (parse-only).
- `PGN::MoveText` created twice per parsed move (parser + `Game#moves=`).
- `Move#initialize` SAN regex (`Regexp` + `MatchData` objects, replay).
- Small throw-away arrays and string conversions in `MoveCalculator` and
  `Position#move`.

## Detailed changes

### 1. Lexer: parser hot path avoids `Token` objects

`lib/pgn/lexer.rb`

- Add a fast public method `next_token_pair` that returns `[type, value]`
  directly, without allocating a `PGN::Lexer::Token` Struct.
  The byte offset is **not** expensive (`@ss.pos`) and is still required, so
  the saving is the Struct allocation, not offset computation.
- **Correctness requirement:** `next_token_pair` must invoke the same
  `note_token(type, off)` and `advance_line(value)` side effects as
  `next_token`. In particular `note_token` maintains `game_starts`, which
  `PgnParser#assign_pgn!` relies on to slice each game's verbatim raw `pgn`
  text — skipping it would corrupt `Game#pgn`.
- Keep `next_token` and `tokens` unchanged (they continue to return `Token`
  objects and are used by specs/other callers).
- Implement both methods on top of a shared private scanning routine so the
  scanning logic is not duplicated.
- The single-byte literal path already returns frozen strings via
  `LITERAL_BYTES` under `# frozen_string_literal: true`; preserve that in
  `next_token_pair` (no change needed beyond routing through the shared
  routine).

`lib/pgn/pgn_parser.y`

- Change `PgnParser#next_token` to call `@lexer.next_token_pair` and return the
  resulting array directly.
- Regenerate `lib/pgn/pgn_parser.rb` from the `.y` file with Racc.
- No changes to grammar or semantics.

### 2. Game#moves=: stop re-wrapping existing MoveText objects

`lib/pgn/game.rb`

- Detect when an element is already a `PGN::MoveText` instance and reuse it
  directly instead of creating a new one.
- Still perform castling normalization (`0` → `O`) for raw strings.
- Preserve `clean_text` behavior for fresh comments only.
- **Reuse-safety invariant:** reusing the parser's `MoveText` shares one object
  between the parser's move tree and `Game#moves`. This is safe only because
  nothing mutates a `MoveText` after construction; record that invariant in a
  comment so a future mutation doesn't silently corrupt both holders.

Expected effect: roughly halves `MoveText` allocations on the parse path while
keeping serialized output identical.

### 3. Move#initialize: hand-rolled SAN parser (highest-risk item — quantify first)

`lib/pgn/move.rb`

This is the highest-risk, and likely lowest-allocation-payoff, item: the SAN
regex produces ~1 `MatchData` per ply (~2.1% of the 2,177-object replay
baseline). Before committing to a full hand-roll, **measure #3 in isolation**
and confirm the payoff; if marginal, ship #1, #2, #4 alone and defer #3.

Trivial independent sub-win (do regardless of the full hand-roll):

- In `Move#piece=`, replace `return if san.match('O-O')` (which allocates a
  `MatchData` on every `Move.new`, castling or not) with a non-allocating
  check such as `san.include?('O-O')` or `san.start_with?('O')`.

Full hand-roll (if pursued):

- Replace `move.match(SAN_REGEX)` with a manual parse over the byte/string
  representation of the SAN notation.
- Populate all existing attributes (`piece`, `destination`, `promotion`,
  `check`, `capture`, `disambiguation`, `castle`) with the same values as
  today, including the `piece=` early-return for castling.
- Keep setter methods (`piece=`, `promotion=`, `capture=`, `disambiguation=`,
  `castle=`) so external callers that assign attributes manually are unaffected.
- Use frozen constants for frequently-checked piece sets (`pawn?` lives here,
  in `move.rb` — see item 4).
- **Upfront fixtures:** add a dedicated spec pinning every attribute for a
  comprehensive set of SAN strings: `O-O`, `O-O-O`, `O-O+`, `O-O-O#`;
  pawn moves and captures incl. promotion (`e4`, `exd5`, `e8=Q`, `exd8=Q+`,
  `b1=N#`); piece moves with file/rank/full disambiguation (`Nbd2`, `R1e2`,
  `Qh4e1`); captures with check/mate; and the `--` "don't care" move. Do this
  before implementation, not only if ambiguity surfaces.

### 4. Position / MoveCalculator: fewer throw-away allocations

`lib/pgn/position.rb`

- Inline `next_player` logic in `Position#move` (or simply rewrite its body to
  `player == :white ? :black : :white`) to avoid the `(PLAYERS - [player])`
  array allocation per ply.
- Apply `castling_restrictions` only when non-empty; avoid array subtraction
  when there is nothing to remove. (Safe to return the existing `castling`
  array directly because castling arrays are replaced, never mutated.)

`lib/pgn/move_calculator.rb`

- Compute and cache destination coordinates in `initialize` instead of calling
  `board.coordinates_for(move.destination)` repeatedly (it can be invoked 2–3
  times per move across `direction_origins` / `move_origins` / `pawn_origins`).
- Inline `valid_square?` boundary checks to remove the per-call method dispatch
  (note: `(0..7)` are frozen range literals already cached by the VM, so the
  win is call overhead, not Range allocation — don't claim the latter).
- Replace run-time array/hash literals with frozen constants or `case`/`when`
  where they appear on hot paths (e.g. rook-origin lookup in
  `castling_restrictions`, the per-call hash literals `{ 'a1' => 'Q', ... }`).
- Keep semantic behavior identical (same board updates, same disambiguation,
  same `king_position` scan — Approach A deliberately defers indexing/caching
  to a later design).

`lib/pgn/move.rb` (relocated from move_calculator)

- `Move#pawn?` uses `%w[P p].include?(piece)`, allocating an array each call;
  it's invoked from `MoveCalculator#increment_halfmove?` and `pawn_origins`.
  Replace with a frozen constant or `piece == 'P' || piece == 'p'`.

## Testing & behavior preservation

- All existing specs must pass without modification (`bundle exec rspec`).
- The `bench/baseline_moves.txt` and `bench/baseline_parse.txt` files will be
  regenerated with `bundle exec rake bench` and committed if they show lower
  object/byte counts and equal or better throughput.
- Public API remains unchanged: `PGN.parse`, `Game#moves=`, `Move.new`,
  `Position#move`, etc. accept the same inputs and produce the same outputs and
  side effects.
- No changes to PGN/FEN serialization format.
- **Lexer non-regression:** because `next_token_pair` shares the scanning
  routine with `next_token`/`tokens`, the existing `tokens`/`next_token` specs
  and the `game_starts`-driven `Game#pgn` raw-text slicing output must stay
  byte-identical across the fixtures and inline inputs in
  `spec/parser_explicit_spec.rb`.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Hand-rolled SAN parser mishandles an edge case | Upfront comprehensive SAN fixture spec (castling both sides, promotion with/without check, pawn & piece captures, file/rank/full disambiguation, `--`) added before implementation; full suite must stay green. |
| `next_token_pair` drifts from `next_token` behavior | Both methods share the private scanning routine, the same `RULES` ordering, and the same `note_token`/`advance_line` side effects (incl. `game_starts`). |
| `Game#moves=` no longer applies castling normalization | Continue normalizing raw strings; only skip work when input is already `MoveText`. |
| Performance wins smaller than expected | Measure before/after with the committed baseline harness. |

## Acceptance criteria

1. `bundle exec rspec` passes (0 failures).
2. `lib/pgn/pgn_parser.rb` is regenerated and in sync with `.y`
   (`git diff --stat` should reflect the generation, and CI racc-sync check
   passes).
3. `bundle exec rake bench` shows lower allocated objects/bytes than the
   **post-Racc** committed baselines (`baseline_moves.txt` and
   `baseline_parse.txt`, the latter promoted from `baseline_parse.racc.txt`
   per item 5). Comparing against the old whittle `baseline_parse.txt` would
   not be a meaningful gate.
4. IPS numbers are equal or higher than current baselines.
5. Baseline files are updated and committed as part of the change set.
6. Lexer non-regression: `tokens`/`next_token` spec output and `Game#pgn`
   raw-text slicing are byte-identical to the pre-change checkout.

## Estimated impact

Per-item expectations (to be confirmed by measurement, not assumed in
aggregate):

- **Items 1, 2, 4 (low-risk):** the largest reliable wins. Parse-side `Token`
  elimination (#1) and halved `MoveText` allocation (#2) should show up directly
  in parse-only object counts; `next_player`/`pawn?`/`castling_restrictions`
  (#4) trim a handful of objects per ply.
- **Item 3 (SAN hand-roll):** ~1 `MatchData` per ply (~2.1% of the 2,177-object
  replay baseline) plus the `piece=` guard fix — modest, and the bulk of the
  estimate does **not** come from this item.
- **Replay allocations are dominated by `Position.new` + `Board#dup` +
  `MoveCalculator` arrays**, which Approach A only trims at the edges; the big
  replay win is deferred to Approach B.

Conservative aggregate guess once #1/#2/#4 land: parse-only allocations down
~10–15%, replay allocations down in the single-digit-percent range (lower than
a naive reading of these micro-opts might suggest). Actual numbers will come
from the baseline run; revise this section with measured per-item deltas.
