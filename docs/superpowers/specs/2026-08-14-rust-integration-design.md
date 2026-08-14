# Rust Integration: `attacks::init` thread-safety + `Position#perft` / `#legal_moves` delegation — Design

**Goal:** Land three incremental integrations of the new Rust bitboard
engine into the Ruby surface, in increasing risk order:

1. Make `attacks::init()` thread-safe and idempotent (correctness fix),
   and drop the now-redundant per-method `attacks::init()` calls in the
   magnus binding.
2. Add `PGN::Position#perft(depth) -> Integer` delegating to
   `PGN::Bitboard::Engine`.
3. Add `PGN::Position#legal_moves -> Array<String>` (UCI) delegating to
   the engine — **gated on an absolute-throughput bar** (see below).

This extends the existing `2026-08-13-rust-bitboard-perft-design.md`
backend; it does not revise it.

## Non-goals

- **No change to the pure-Ruby hot path.** `Position#move` / replay /
  `MoveCalculator` / `Notation` stay byte-identical. `Position#perft`
  and `#legal_moves` are *new* methods; they do not alter existing ones.
- **No UCI→SAN conversion in this round.** SAN stays the existing
  pure-Ruby `PGN::Notation`'s job. `#legal_moves` returns raw UCI. A
  future round may compose `Notation.san(position, from, to, promo)` over
  the UCI list; explicitly out of scope here.
- **No pure-Ruby `legal_moves` fallback/comparator.** Per the chosen
  gate, we measure absolute throughput only; no Ruby baseline is built.
- **No `attacks::init`-removal across the whole crate.** The defensive
  `attacks::init()` calls inside `pgn2-bitboard` (board/moves/perft/
  legality) stay — they are cheap (atomic no-op after first) and keep
  `cargo test` self-initializing. Only the *binding* (`pgn2_native`)
  drops its redundant calls.

## Task 1 — `attacks::init()` thread-safety

### Problem

`ext/pgn2_native/pgn2-bitboard/src/attacks.rs` holds four attack tables
and a guard:

```rust
static mut KNIGHT: [Bitboard; 64] = [Bitboard::EMPTY; 64];
static mut KING:   [Bitboard; 64] = [Bitboard::EMPTY; 64];
static mut WP:     [Bitboard; 64] = [Bitboard::EMPTY; 64];
static mut BP:     [Bitboard; 64] = [Bitboard::EMPTY; 64];
static mut INIT: bool = false;

pub fn init() {
    unsafe {
        if INIT { return; }
        /* fill tables */
        INIT = true;
        crate::magics::build_all();
    }
}
```

`INIT` is a plain `bool` flipped inside `unsafe` with **no
synchronization** — a data race (UB), and there is no happens-before
guaranteeing later `unsafe` reads of the tables see the filled values.
Under MRI the GIL masks this in practice, but it is a real defect and
trips stricter tooling. (`magics.rs` is already correct: its `build_all`
uses `Once`, so reads after `call_once` are happens-before-safe.)

### Fix

Drive `init()` through `std::sync::Once` so initialization is a single
synchronized event and all subsequent reads are safe:

```rust
static INIT: Once = Once::new();

pub fn init() {
    INIT.call_once(|| unsafe {
        // fill KNIGHT/KING/WP/BP (kept as `static mut`, written once here)
        crate::magics::build_all();
    });
}
```

The `static mut` table arrays stay (they are written exactly once inside
`call_once` and read after; `Once` establishes the happens-before). This
is the minimal, correct change. Switching the arrays themselves to
`OnceLock<[Bitboard; 64]>` is a larger cleanup explicitly deferred — it
is not needed for correctness and would touch every accessor.

`init()` remains idempotent and cheap: after first call it is one atomic
load. The scattered `attacks::init()` calls inside `pgn2-bitboard` are
therefore harmless and stay (keeps `cargo test` self-initializing).

### Binding cleanup

`pgn2_native/src/lib.rs` calls `attacks::init()` at the top of `perft`,
`legal_moves_ruby`, and `legal_p`. These are **redundant**: every crate
function they delegate to (`Board::perft`, `legal_moves`, `legality::*`)
already calls `attacks::init()` itself. Remove the three binding-level
calls. (`Engine::initialize`/`from_fen` needs no init — it only sets
bitboards.)

### Testing

Existing `cargo test` perft oracle suite + Ruby `bitboard_spec.rb` must
stay green. No new tests required for task 1 (behavior unchanged); the
point is the safety/cheapness invariant, verified by inspection.

## Task 2 — `PGN::Position#perft`

### API

```ruby
# Returns the perft node count at +depth+ from this position.
# Delegates to the native bitboard engine via a FEN round-trip.
# @param depth [Integer] >= 0
# @return [Integer]
def perft(depth) -> Integer
```

### Implementation

```ruby
def perft(depth)
  raise ArgumentError, "depth must be >= 0" unless depth.is_a?(Integer) && depth >= 0
  PGN::Bitboard::Engine.new(to_fen.to_s).perft(depth)
end
```

- Bridge is a **FEN round-trip**: `Position#to_fen` → `PGN::FEN#to_s`
  → `Engine.new(fen)` → `#perft`. Only a String + Integer cross the
  boundary (per the backend's boundary principle).
- **Native availability:** the shipped gem is a precompiled native gem
  (no fallback). `lib/pgn/bitboard.rb` loads the `.so` and rescues to
  `LoadError` silently so the rest of the gem still loads. If the
  extension is absent, `PGN::Bitboard` is undefined and `#perft` raises
  `NameError` naturally — acceptable and consistent with the existing
  `Engine` behavior. No new gating code; rely on `defined?`/NameError.

### Testing

New `spec/position_spec.rb` cases:
- `Position.start.perft(0) == 1`, `perft(1) == 20`, `perft(2) == 400`,
  `perft(3) == 8902`, `perft(4) == 197281` (published startpos values).
- Kiwipete FEN → `perft(1) == 48`, `perft(2) == 2039`, `perft(3) == 97862`.
- These double as cross-checks that the FEN round-trip is lossless for
  perft-relevant state (placement/side/castling/ep).

## Task 3 — `PGN::Position#legal_moves` (UCI), throughput-gated

### API

```ruby
# All legal moves from this position as sorted UCI strings
# (e.g. "e2e4", "e1g1" for castling, "e7e8q" for promotion).
# Delegates to the native bitboard engine via a FEN round-trip.
# @return [Array<String>] sorted lexicographically
def legal_moves -> Array<String>
```

### Implementation

```ruby
def legal_moves
  PGN::Bitboard::Engine.new(to_fen.to_s).legal_moves
end
```

Same FEN round-trip bridge as task 2. Output is the engine's already-sorted
UCI list; no Ruby post-processing.

### Performance gate (decides whether task 3 ships)

Per the chosen decision, **absolute throughput bar**, no Ruby baseline:

- Benchmark `Position#legal_moves` end-to-end (FEN build + `Engine.new`
  + native legal-gen + Ruby string materialization) on three positions:
  startpos, a middlegame position, and Kiwipete.
- **Ship iff** the middlegame case completes in **< 1 ms** end-to-end
  (single call, warm). This makes the API practical: a user enumerating
  legal moves per position pays under a millisecond, dominated by the
  FEN round-trip and object construction, not by move generation.
- If the middlegame case is **≥ 1 ms**, do **not** ship `#legal_moves`;
  record the measured numbers and the breakdown (FEN build vs `Engine.new`
  vs native gen vs string materialization) in the plan/changelog, and
  stop. The gate is pass/fail; there is no partial ship.
- The benchmark script lives at `bench/legal_moves.rb` and is run with
  `bundle exec ruby bench/legal_moves.rb`; results committed to
  `bench/` alongside the existing perft baselines.

### Testing (only if it ships)

New `spec/position_spec.rb` cases:
- `Position.start.legal_moves.length == 20`.
- After `Position.start.move("e4")`, the resulting `#legal_moves` equals
  the engine's direct output for that FEN (delegation equivalence).
- Spot-check a position with a promotion and one with castling, asserting
  the UCI strings present (`e7e8q`, `e1g1`).

## Risks

- **FEN round-trip cost** is the dominant per-call cost for both new
  methods. For `#perft` this is irrelevant (perft dwarfs it). For
  `#legal_moves` it is *the* gate — if it blows the 1 ms bar, we don't
  ship. No silent perf regression is possible: both methods are net-new.
- **`attacks::init` race fix** is a one-line-ish change with no behavior
  change; risk is a build break from `Once` import, caught by `cargo
  test`.
- **No regression to existing 233 specs**: all changes are additive
  (new methods) or internal (init safety). Verified by running the full
  suite after each task.

## Out of scope / future

- UCI→SAN via `PGN::Notation` over the `#legal_moves` list.
- `Engine` reuse / caching across calls (a `Position`-held engine) to
  amortize the FEN round-trip — only worth it if `#legal_moves` blows
  the gate and we choose to optimize rather than drop.
- Migrating `attacks.rs` table arrays to `OnceLock` (cleaner than
  `static mut`, but not required for the race fix).
