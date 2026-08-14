# Rust Integration: init safety + `Position#perft` / `#legal_moves` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land three incremental Rust-engine integrations: a thread-safety fix for `attacks::init()`, `PGN::Position#perft` delegation, and `PGN::Position#legal_moves` (UCI) gated on an absolute throughput bar.

**Architecture:** All Ruby↔Rust integration goes through a FEN round-trip (`Position#to_fen.to_s` → `PGN::Bitboard::Engine.new(fen)`). The native engine crate self-initializes its attack tables; the magnus binding becomes a thin wrapper. Task 3 ships only if a measured middlegame `#legal_moves` call completes in < 1 ms end-to-end.

**Tech Stack:** Ruby (magnus-loaded native gem), Rust (`pgn2-bitboard` lib + `pgn2_native` cdylib), RSpec, `cargo test`, `rake compile` (rake-compiler).

**Worktree:** All work happens in `/home/murilo/code/zzug/pgn/.worktrees/feat-rust-bitboard-perft` on branch `feat/rust-bitboard-perft`. Run every command from that directory.

## Global Constraints

- The shipped path is a **required compiled native extension**; no pure-Ruby fallback for `#perft` / `#legal_moves`. If `PGN::Bitboard::Engine` is undefined, those methods raise `NameError` naturally — do not add fallback code.
- **No changes to the pure-Ruby hot path** (`Position#move`, `MoveCalculator`, `Notation`, replay). New methods are additive only.
- Existing 233 specs must stay green after every task.
- After any Rust edit, rebuild with `bundle exec rake compile` before running Ruby specs (Ruby loads the `.so` at process start).
- RuboCop must stay clean: run `bundle exec rubocop <changed.rb> --force-default-config` is not needed; the repo config (`rubocop.yml`) applies. Use `bundle exec rubocop` on changed Ruby files.
- `PGN::Bitboard::Engine#legal_moves` already returns **sorted UCI** strings; `#perft` returns an Integer. Reuse these as-is.
- `PGN::Position#to_fen` returns a `PGN::FEN`; `PGN::FEN#to_s` returns the FEN string.

---

### Task 1: Make `attacks::init()` thread-safe and drop redundant binding calls

**Files:**
- Modify: `ext/pgn2_native/pgn2-bitboard/src/attacks.rs` (lines 1-8 and the `init()` body at lines 12-46)
- Modify: `ext/pgn2_native/pgn2_native/src/lib.rs` (lines 25, 30, 37)

**Interfaces:**
- Consumes: existing `crate::magics::build_all()` (already `Once`-guarded; unchanged).
- Produces: `pub fn init()` with identical signature, now `Once`-driven; behavior unchanged for all existing callers.

**Why no new test:** This is a safety/perf invariant refactor with **no behavior change**. The existing `cargo test` perft oracle suite (startpos/Kiwipete/pos3-6) and `spec/bitboard_spec.rb` are the safety net — they must stay green. The point of the task is the happens-before guarantee, verified by code inspection + a green build.

- [ ] **Step 1: Capture the pre-change green baseline**

Run:
```bash
cd /home/murilo/code/zzug/pgn/.worktrees/feat-rust-bitboard-perft
(cd ext/pgn2_native && cargo test --manifest-path Cargo.toml 2>&1 | tail -5)
bundle exec rspec spec/bitboard_spec.rb --format progress
```
Expected: cargo test passes (perft oracle), bitboard_spec passes (all green).

- [ ] **Step 2: Edit `attacks.rs` — route `init()` through `Once`**

Replace lines 3-8 of `ext/pgn2_native/pgn2-bitboard/src/attacks.rs`:

```rust
static mut KNIGHT: [Bitboard; 64] = [Bitboard::EMPTY; 64];
static mut KING: [Bitboard; 64] = [Bitboard::EMPTY; 64];
static mut WP: [Bitboard; 64] = [Bitboard::EMPTY; 64];
static mut BP: [Bitboard; 64] = [Bitboard::EMPTY; 64];
static mut INIT: bool = false;
```
with:

```rust
use std::sync::Once;

static mut KNIGHT: [Bitboard; 64] = [Bitboard::EMPTY; 64];
static mut KING: [Bitboard; 64] = [Bitboard::EMPTY; 64];
static mut WP: [Bitboard; 64] = [Bitboard::EMPTY; 64];
static mut BP: [Bitboard; 64] = [Bitboard::EMPTY; 64];
static INIT: Once = Once::new();
```

Then replace the `init()` function (lines 12-46):

```rust
pub fn init() {
    unsafe {
        if INIT { return; }
        for sq in 0..64u8 {
            let s = Square(sq);
            let f = s.file() as i32; let r = s.rank() as i32;
            let mut kn = Bitboard::empty();
            for (df, dr) in [(1,2),(2,1),(2,-1),(1,-2),(-1,-2),(-2,-1),(-2,1),(-1,2)] {
                let nf = f+df; let nr = r+dr;
                if valid(nf, nr) { kn |= bb(nf, nr); }
            }
            KNIGHT[sq as usize] = kn;
            let mut kg = Bitboard::empty();
            for df in -1..=1 { for dr in -1..=1 {
                if df == 0 && dr == 0 { continue; }
                let nf = f+df; let nr = r+dr;
                if valid(nf, nr) { kg |= bb(nf, nr); }
            }}
            KING[sq as usize] = kg;
            let mut wp = Bitboard::empty();
            if valid(f-1, r+1) { wp |= bb(f-1, r+1); }
            if valid(f+1, r+1) { wp |= bb(f+1, r+1); }
            WP[sq as usize] = wp;
            let mut bp = Bitboard::empty();
            if valid(f-1, r-1) { bp |= bb(f-1, r-1); }
            if valid(f+1, r-1) { bp |= bb(f+1, r-1); }
            BP[sq as usize] = bp;
        }
        INIT = true;
        crate::magics::build_all();
    }
}
```
with:

```rust
pub fn init() {
    INIT.call_once(|| unsafe {
        for sq in 0..64u8 {
            let s = Square(sq);
            let f = s.file() as i32; let r = s.rank() as i32;
            let mut kn = Bitboard::empty();
            for (df, dr) in [(1,2),(2,1),(2,-1),(1,-2),(-1,-2),(-2,-1),(-2,1),(-1,2)] {
                let nf = f+df; let nr = r+dr;
                if valid(nf, nr) { kn |= bb(nf, nr); }
            }
            KNIGHT[sq as usize] = kn;
            let mut kg = Bitboard::empty();
            for df in -1..=1 { for dr in -1..=1 {
                if df == 0 && dr == 0 { continue; }
                let nf = f+df; let nr = r+dr;
                if valid(nf, nr) { kg |= bb(nf, nr); }
            }}
            KING[sq as usize] = kg;
            let mut wp = Bitboard::empty();
            if valid(f-1, r+1) { wp |= bb(f-1, r+1); }
            if valid(f+1, r+1) { wp |= bb(f+1, r+1); }
            WP[sq as usize] = wp;
            let mut bp = Bitboard::empty();
            if valid(f-1, r-1) { bp |= bb(f-1, r-1); }
            if valid(f+1, r-1) { bp |= bb(f+1, r-1); }
            BP[sq as usize] = bp;
        }
        crate::magics::build_all();
    });
}
```

- [ ] **Step 3: Drop the redundant binding-level `attacks::init()` calls**

In `ext/pgn2_native/pgn2_native/src/lib.rs`, remove the `pgn2_bitboard::attacks::init();` line from each of the three methods, leaving:

```rust
    fn perft(&self, depth: u32) -> u64 {
        self.0.borrow().perft(depth)
    }

    fn legal_moves_ruby(&self) -> Vec<String> {
        let mut v: Vec<String> = self.0.borrow().legal_moves().iter().map(|m| m.to_uci()).collect();
        v.sort();
        v
    }

    fn legal_p(&self, uci: String) -> bool {
        match pgn2_bitboard::moves::uci_parse(&uci) {
            Some(parsed) => self.0.borrow().legal_moves().iter().any(|m| m.same_target(parsed)),
            None => false,
```
(Rationale: `Board::perft`, `Board::legal_moves`, and the `legality::*` paths already call `attacks::init()` themselves, so the binding calls were redundant. `Engine::initialize`/`from_fen` only sets bitboards and needs no init.)

- [ ] **Step 4: Rebuild and verify Rust tests**

Run:
```bash
cd /home/murilo/code/zzug/pgn/.worktrees/feat-rust-bitboard-perft
(cd ext/pgn2_native && cargo test --manifest-path Cargo.toml 2>&1 | tail -8)
```
Expected: all perft oracle tests pass; no new warnings beyond the pre-existing `pgn2_native (lib test) generated 1 warning`.

- [ ] **Step 5: Rebuild the native gem and verify Ruby specs**

Run:
```bash
bundle exec rake compile
bundle exec rspec spec/bitboard_spec.rb --format progress
bundle exec rspec --format progress 2>&1 | tail -5
```
Expected: bitboard_spec green; full suite still 233 examples, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add ext/pgn2_native/pgn2-bitboard/src/attacks.rs ext/pgn2_native/pgn2_native/src/lib.rs
git commit -m "perf(native): drive attacks::init through Once (thread-safe); drop redundant binding init calls"
```

---

### Task 2: `PGN::Position#perft` delegation

**Files:**
- Modify: `lib/pgn/position.rb` (add `#perft` after `#next_player`, around line 89)
- Test: `spec/position_spec.rb` (append a new top-level `RSpec.describe` block after the final `end` at line 177)

**Interfaces:**
- Consumes: `PGN::Bitboard::Engine.new(String)#perft(Integer) -> Integer`; `PGN::Position#to_fen -> PGN::FEN`; `PGN::FEN#to_s -> String`.
- Produces: `PGN::Position#perft(Integer) -> Integer`.

- [ ] **Step 1: Write the failing spec**

Append to `spec/position_spec.rb`:

```ruby
RSpec.describe PGN::Position, '#perft' do
  it 'returns 1 at depth 0 for the start position' do
    expect(PGN::Position.start.perft(0)).to eq(1)
  end

  it 'matches published startpos perft values' do
    p = PGN::Position.start
    expect(p.perft(1)).to eq(20)
    expect(p.perft(2)).to eq(400)
    expect(p.perft(3)).to eq(8_902)
    expect(p.perft(4)).to eq(197_281)
  end

  it 'matches published Kiwipete perft values' do
    fen = 'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1'
    p = PGN::FEN.new(fen).to_position
    expect(p.perft(1)).to eq(48)
    expect(p.perft(2)).to eq(2_039)
    expect(p.perft(3)).to eq(97_862)
  end

  it 'raises ArgumentError on negative depth' do
    expect { PGN::Position.start.perft(-1) }.to raise_error(ArgumentError)
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/position_spec.rb -e '#perft' --format documentation`
Expected: FAIL with `undefined method 'perft' for #<PGN::Position:...>` (NameError/NoMethodError).

- [ ] **Step 3: Implement `Position#perft`**

In `lib/pgn/position.rb`, add after the `#next_player` method (before `def inspect`):

```ruby
    # The perft node count at +depth+ from this position, computed by the
    # native bitboard engine via a FEN round-trip. Requires the compiled
    # native extension (the shipped gem); raises NameError if it is absent.
    #
    # @param depth [Integer] search depth, >= 0
    # @return [Integer]
    #
    def perft(depth)
      raise ArgumentError, 'depth must be a non-negative Integer' unless depth.is_a?(Integer) && depth >= 0

      PGN::Bitboard::Engine.new(to_fen.to_s).perft(depth)
    end
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/position_spec.rb -e '#perft' --format documentation`
Expected: PASS (4 examples green).

- [ ] **Step 5: Run the full suite and rubocop**

Run:
```bash
bundle exec rspec --format progress 2>&1 | tail -5
bundle exec rubocop lib/pgn/position.rb spec/position_spec.rb
```
Expected: 237 examples (233 + 4), 0 failures; rubocop clean.

- [ ] **Step 6: Commit**

```bash
git add lib/pgn/position.rb spec/position_spec.rb
git commit -m "feat(position): add #perft delegating to the native bitboard engine"
```

---

### Task 3: `PGN::Position#legal_moves` (UCI) — throughput-gated

**Files:**
- Create: `bench/legal_moves.rb`
- Modify: `lib/pgn/position.rb` (add `#legal_moves` after `#perft`) — **only if the gate passes**
- Test: `spec/position_spec.rb` (append a `RSpec.describe` block) — **only if the gate passes**

**Interfaces:**
- Consumes: `PGN::Bitboard::Engine.new(String)#legal_moves -> Array<String>` (sorted UCI); `PGN::Position#to_fen -> PGN::FEN`; `PGN::FEN#to_s -> String`.
- Produces: `PGN::Position#legal_moves -> Array<String>` (sorted UCI) — conditional on the gate.

**Gate:** Ship `#legal_moves` **iff** a warm middlegame `Position#legal_moves` call is **< 1 ms** end-to-end. If the gate fails, commit only the benchmark script + a recorded-results note, and stop (no `#legal_moves` method, no spec block).

- [ ] **Step 1: Write the benchmark script**

Create `bench/legal_moves.rb`:

```ruby
# frozen_string_literal: true

# Benchmark PGN::Position#legal_moves end-to-end (FEN round-trip +
# native legal-gen + Ruby string materialization) to decide whether
# shipping the method meets the < 1 ms middlegame gate.
#
# Run: bundle exec ruby bench/legal_moves.rb

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'pgn'

unless PGN::Bitboard.const_defined?(:Engine)
  warn 'PGN::Bitboard::Engine not compiled — build with `bundle exec rake compile` first.'
  exit 1
end

POSITIONS = {
  'startpos' => 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  'middlegame' => 'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4',
  'kiwipete' => 'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1'
}.freeze

def monotonic
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

POSITIONS.each_value do |fen|
  pos = PGN::FEN.new(fen).to_position
  # warmup
  100.times { pos.legal_moves }
  n = 2000
  t0 = monotonic
  n.times { pos.legal_moves }
  elapsed = monotonic - t0
  us = (elapsed / n) * 1_000_000.0
  count = pos.legal_moves.length
  printf("%-12s moves=%-3d  %.1f us/call  (%.3f ms)\n", fen[0, 12], count, us, us / 1000.0)
end
```

Note: this script calls `Position#legal_moves`, which does not exist yet. To measure the **delegate path** before committing the method, also create a temporary inline definition at the top of the script (delete after measuring):

```ruby
# temporary, for measurement only — remove before committing
PGN::Position.define_method(:legal_moves) do
  PGN::Bitboard::Engine.new(to_fen.to_s).legal_moves
end
```
(Place this block immediately after the `require 'pgn'` line, before the `unless` guard.)

- [ ] **Step 2: Run the benchmark and record results**

Run: `bundle exec ruby bench/legal_moves.rb`
Record the three lines of output. Compute the middlegame `us/call` value.

- [ ] **Step 3: Gate decision — check < 1 ms middlegame bar**

If the **middlegame** line is `< 1000.0 us/call` (< 1 ms): gate **passes** → proceed to Step 4.

If the middlegame line is `>= 1000.0 us/call`: gate **fails** → do **not** add `#legal_moves` to `lib/pgn/position.rb`. Instead:
- Remove the temporary `define_method` block from `bench/legal_moves.rb` (keep only the measuring script, which references `Position#legal_moves` — add a one-line comment at the top: `# NOTE: gate FAILED (<1ms middlegame bar not met); Position#legal_moves was NOT shipped. Numbers below are from an inline define_method measurement.`). Actually, since the script calls `pos.legal_moves`, keep the `define_method` block but mark it clearly as the measurement shim. Add the recorded numbers as a comment block at the top of the file.
- Commit the script + numbers: `git add bench/legal_moves.rb && git commit -m "bench: record Position#legal_moves throughput — gate FAILED, not shipped"`.
- **Stop.** Do not run Steps 4-8. Report the numbers to the user.

- [ ] **Step 4: (gate passed) Write the failing spec**

Remove the temporary `define_method` shim from `bench/legal_moves.rb` (it now references `Position#legal_moves`, which the next step adds for real). Append to `spec/position_spec.rb`:

```ruby
RSpec.describe PGN::Position, '#legal_moves' do
  it 'lists 20 legal moves from the start position' do
    expect(PGN::Position.start.legal_moves.length).to eq(20)
  end

  it 'returns sorted UCI strings matching the UCI format' do
    moves = PGN::Position.start.legal_moves
    expect(moves).to eq(moves.sort)
    expect(moves).to all(match(/\A[a-h][1-8][a-h][1-8][qrbn]?\z/))
  end

  it 'matches the engine direct output for the same FEN (delegation equivalence)' do
    fen = 'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1'
    pos = PGN::FEN.new(fen).to_position
    expect(pos.legal_moves).to eq(PGN::Bitboard::Engine.new(fen).legal_moves)
  end

  it 'includes a promotion UCI when one is legal' do
    # White king e1, black king h1, white pawn e7 — e7e8q must be legal.
    fen = '8/4P3/8/8/8/8/8/4K2k w - - 0 1'
    pos = PGN::FEN.new(fen).to_position
    expect(pos.legal_moves).to include('e7e8q')
  end
end
```

- [ ] **Step 5: Run the spec to verify it fails**

Run: `bundle exec rspec spec/position_spec.rb -e '#legal_moves' --format documentation`
Expected: FAIL with `undefined method 'legal_moves'`.

- [ ] **Step 6: Implement `Position#legal_moves`**

In `lib/pgn/position.rb`, add immediately after the `#perft` method added in Task 2:

```ruby
    # All legal moves from this position as sorted UCI strings
    # (e.g. "e2e4", "e1g1" for castling, "e7e8q" for promotion), computed
    # by the native bitboard engine via a FEN round-trip. Requires the
    # compiled native extension; raises NameError if it is absent.
    #
    # @return [Array<String>] sorted lexicographically
    #
    def legal_moves
      PGN::Bitboard::Engine.new(to_fen.to_s).legal_moves
    end
```

- [ ] **Step 7: Run specs + rubocop + full suite**

Run:
```bash
bundle exec rspec spec/position_spec.rb -e '#legal_moves' --format documentation
bundle exec rubocop lib/pgn/position.rb spec/position_spec.rb bench/legal_moves.rb
bundle exec rspec --format progress 2>&1 | tail -5
```
Expected: the 4 new `#legal_moves` examples pass; rubocop clean; full suite green (241 examples if both Task 2 and Task 3 specs are present).

- [ ] **Step 8: Commit**

```bash
git add lib/pgn/position.rb spec/position_spec.rb bench/legal_moves.rb
git commit -m "feat(position): add #legal_moves (UCI) delegating to the native engine + throughput bench"
```

---

## Self-Review

**Spec coverage:**
- Task 1 (attacks::init thread-safety + binding cleanup) → Task 1. ✓
- Task 2 (Position#perft delegation + published-value specs) → Task 2. ✓
- Task 3 (Position#legal_moves UCI, < 1 ms middlegame gate, pass/fail) → Task 3. ✓
- Out-of-scope items (UCI→SAN, engine caching, OnceLock table migration) explicitly excluded. ✓

**Placeholder scan:** No TBD/TODO. Every code step has full code. The gate-failure branch has an explicit stop instruction.

**Type consistency:** `#perft(Integer) -> Integer` and `#legal_moves -> Array<String>` signatures match across spec and implementation. `to_fen.to_s` bridge consistent in both. `PGN::Bitboard::Engine.new(fen).perft(depth)` / `.legal_moves` match the existing binding API verified in `bitboard_spec.rb`.
