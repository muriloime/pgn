# Efficiency Optimizations — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce allocations and increase throughput of the move-application and parsing hot paths, **proving** each win with a before/after diff of the committed baseline (`bench/baseline_*.txt` vs `bench/baseline_*.pre-optimization.txt`), while keeping all 129 existing characterization specs green.

**Architecture:** Five behavior-preserving optimizations, ordered safest-first so each ships independently. (1) `Board#at(str)` / `#coordinates_for` use `getbyte` arithmetic instead of `chars.to_a` + hash lookups → eliminates the 6 allocations/string-lookup. (2) `MoveCalculator#king_position` early-exits instead of scanning all 64 squares. (3) `Move#initialize` assigns named groups with explicit setter calls instead of `match.names.each { send }` → drops the per-move `names` array + dynamic dispatch. (4) `FEN#board_string` builds the string in a single pass instead of map→map→join→gsub. (5) **Headline:** `Board` becomes column-level **copy-on-write** — `dup` is shallow (shares the 8 column arrays) and `update` clones only the column it mutates — so a move copies 2 columns instead of all 8, and a game's position history structurally shares unchanged columns (bonus memory reduction).

**Tech Stack:** Ruby 4.0.5, RSpec 3.13, the existing `pgn2` gem, the `bench/` harness + `benchmark-ips` / `memory_profiler` added in the previous plan.

## Global Constraints

- **Behavior-preserving above all.** After every task, `bundle exec rspec` must be green. Before Task 5 the suite has **129 examples**; Task 5 adds 2 new round-trip examples, so the new green count is **131** (verify the actual count on the first Task 5 run). A "faster but wrong" change is rejected. The characterization specs from the previous plan are the gate.
- **Public API is frozen.** Method names, signatures, return values, `FEN#to_s` output, `Board#inspect` output, and `Game#to_pgn` output must be byte-identical. Only internal allocation/throughput may change.
- **No parser (`lib/pgn/parser.rb`) changes in this plan.** The whittle parser is out of scope (see "Deferred work" below).
- **No weakening of existing `spec/` assertions.** Tests verify behavior; if an existing spec fails, the *implementation* is wrong (or an optimization has a bug), not the test. Task 5 is allowed to add new assertions because `FEN#board_string` needs regression coverage; do not change existing assertions.
- **Prove it.** Every task that claims an allocation/throughput win must show the `bench/` number moving in the right direction before committing. The committed `bench/baseline_moves.txt` / `bench/baseline_parse.txt` are the BEFORE; Task 1 preserves them; Task 7 refreshes them to AFTER and records the deltas in `bench/IMPROVEMENTS.md`.
- One concern per commit. Each task is a single focused commit.

## Why these, and predicted impact (for the implementer)

| Task | Change | Predicted effect on baseline |
|---|---|---|
| 2 | `at(str)` / `coordinates_for` getbyte | §3 `Board#at(str) x1000`: 6000 → ~0 objects |
| 3 | `king_position` early-exit | Removes O(64) full scan; small (disambiguation only) |
| 4 | `Move#initialize` explicit setters | Parse §1: ~1.25M → ~1.05M objects (drops the per-move `names` array, ~16%) |
| 5 | `FEN#board_string` single-pass | Micro; fewer intermediate arrays/strings in `to_fen` |
| 6 | `Board` column-level COW | §2 `Board#dup x45`: 451 → ~90 objects; §1 replay: 5124 → ~2500 objects; **plus** structural sharing across a game's position history (memory) |

---

## File Structure

- **Modify:** `lib/pgn/board.rb` — `at`, `coordinates_for`, `update`, `change!`, `dup` (Tasks 2 & 6).
- **Modify:** `lib/pgn/move_calculator.rb` — `king_position` (Task 3).
- **Modify:** `lib/pgn/move.rb` — `initialize` (Task 4).
- **Modify:** `lib/pgn/fen.rb` — `board_string` (Task 5).
- **Modify:** `spec/fen_spec.rb` — add a `board_string` round-trip block (Task 5).
- **Create:** `bench/baseline_moves.pre-optimization.txt`, `bench/baseline_parse.pre-optimization.txt` — frozen BEFORE snapshots (Task 1).
- **Modify:** `bench/baseline_moves.txt`, `bench/baseline_parse.txt` — refreshed to AFTER (Task 7).
- **Create:** `bench/IMPROVEMENTS.md` — before/after delta summary (Task 7).

---

## Task 1: Preserve the pre-optimization baseline

**Files:**
- Create: `bench/baseline_moves.pre-optimization.txt`
- Create: `bench/baseline_parse.pre-optimization.txt`

**Interfaces:**
- Produces: immutable BEFORE snapshots so Task 7 can diff AFTER vs BEFORE and so any task can sanity-check a metric dropped.

- [ ] **Step 1: Copy the current committed baselines to `.pre-optimization` snapshots.**

```bash
cp bench/baseline_moves.txt bench/baseline_moves.pre-optimization.txt
cp bench/baseline_parse.txt bench/baseline_parse.pre-optimization.txt
```

- [ ] **Step 2: Verify the snapshots match the committed baselines.**

Run: `diff bench/baseline_moves.txt bench/baseline_moves.pre-optimization.txt && diff bench/baseline_parse.txt bench/baseline_parse.pre-optimization.txt && echo preserved`
Expected: prints `preserved` (no differences).

- [ ] **Step 3: Commit.**

```bash
git add bench/baseline_moves.pre-optimization.txt bench/baseline_parse.pre-optimization.txt
git commit -m "bench: preserve pre-optimization baseline snapshots"
```

---

## Task 2: `Board#at(str)` / `#coordinates_for` — getbyte, zero-allocation string lookup

**Files:**
- Modify: `lib/pgn/board.rb`

**Interfaces:**
- Consumes: none new.
- Produces: `Board#at(str)` and `Board#coordinates_for(str)` allocate ~0 objects (down from ~6/call). `at(file, rank)` integer overload unchanged.

- [ ] **Step 1: Replace `at` and `coordinates_for` in `lib/pgn/board.rb`.** The current `at` dispatches on `args.length` and `coordinates_for` does `position.chars.to_a` + two hash lookups. Replace both methods with:

```ruby
    # @overload at(str)
    #   Looks up a piece based on the string representation of a square (e4)
    #   @param str [String] the square in algebraic notation
    # @overload at(file, rank)
    #   Looks up a piece based on zero-indexed coordinates (4, 3)
    #   @param file [Integer] the file the piece is on
    #   @param rank [Integer] the rank the piece is on
    # @return [String, nil] the piece on the square, or nil if it is
    #   empty
    # @example
    #   board.at(4,3)  #=> "P"
    #   board.at("e4") #=> "P"
    #
    # String squares are parsed with getbyte arithmetic (a=0x61, '1'=0x31)
    # so the common string lookup allocates nothing.
    def at(arg0, arg1 = nil)
      return squares[arg0][arg1] unless arg1.nil?
      squares[arg0.getbyte(0) - 97][arg0.getbyte(1) - 49]
    end
```

and

```ruby
    # @param position [String] the square in algebraic notation
    # @return [Array<Integer>] the coordinates of the square
    # @example
    #   board.coordinates_for("e4") #=> [4, 3]
    #
    def coordinates_for(position)
      [position.getbyte(0) - 97, position.getbyte(1) - 49]
    end
```

Leave `FILE_TO_INDEX` / `RANK_TO_INDEX` (still used by `position_for`) and `INDEX_TO_FILE` / `INDEX_TO_RANK` untouched.

- [ ] **Step 2: Run the Board + full suite, verify green.**

Run: `bundle exec rspec spec/board_spec.rb && bundle exec rspec`
Expected: 129 examples, 0 failures.

- [ ] **Step 3: Prove the allocation drop.**

Run: `bundle exec ruby bench/profile_moves.rb`
Expected: section 3 (`Board#at(str) x1000`) `total_allocated objects` is **0** (was 6000 in `bench/baseline_moves.pre-optimization.txt`).

- [ ] **Step 4: Commit.**

```bash
git add lib/pgn/board.rb
git commit -m "perf: zero-allocation Board#at(str)/coordinates_for via getbyte"
```

---

## Task 3: `MoveCalculator#king_position` — early exit

**Files:**
- Modify: `lib/pgn/move_calculator.rb`

**Interfaces:**
- Produces: `king_position` returns the first matching square (no longer scans all 64) and allocates only the one `[file, rank]` it returns.

- [ ] **Step 1: Replace `king_position` in `lib/pgn/move_calculator.rb`.** The current method loops all 64 squares assigning on each match. Replace it with an early-returning scan:

```ruby
    def king_position
      king = move.white? ? 'K' : 'k'

      0.upto(7) do |file|
        0.upto(7) do |rank|
          return [file, rank] if board.at(file, rank) == king
        end
      end

      nil
    end
```

- [ ] **Step 2: Run the calculator + full suite, verify green.**

Run: `bundle exec rspec spec/move_calculator_spec.rb && bundle exec rspec`
Expected: 129 examples, 0 failures. (The `resolves by discovered check (Ne2 ...)` case is the one that exercises `king_position` via `disambiguate_discovered_check`.)

- [ ] **Step 3: Commit.**

```bash
git add lib/pgn/move_calculator.rb
git commit -m "perf: early-exit MoveCalculator#king_position"
```

Note: `king_position` is only reached on moves needing discovered-check disambiguation (rare), so the replay baseline will not move much here. A full king-square cache on `Board` was considered and **deferred** — the ROI is low and the maintenance cost (tracking the king across `update`/`dup`/`FEN#board_string=`) is not justified given the early-exit already removes the worst case. If a future disambiguation-heavy workload shows it matters, add a cache then.

---

## Task 4: `Move#initialize` — explicit setters instead of `send` loop

**Files:**
- Modify: `lib/pgn/move.rb`

**Interfaces:**
- Produces: `Move#initialize` no longer allocates `match.names` (an Array of 8 Strings) per move and no longer does `respond_to?` + dynamic `send` per group.

- [ ] **Step 1: Replace the assignment loop in `Move#initialize`.** The current body ends with:

```ruby
      match.names.each do |name|
        send("#{name}=", match[name]) if respond_to?(name)
      end
```

Replace that loop with explicit calls to the seven real setters, in the same order the regex defines the groups (`piece`, `destination`, `promotion`, `check`, `capture`, `disambiguation`, `castle`). The `normal` group has no setter and is intentionally omitted (it was already skipped by `respond_to?`):

```ruby
      self.piece          = match[:piece]
      self.destination    = match[:destination]
      self.promotion      = match[:promotion]
      self.check          = match[:check]
      self.capture        = match[:capture]
      self.disambiguation = match[:disambiguation]
      self.castle         = match[:castle]
```

The custom setters already handle `nil` / `''` exactly as before (`piece=` returns early for castling via `san.match('O-O')`; `disambiguation=` maps `''`→`nil`; `capture=` maps `nil`→`false`; `castle=`/`promotion=` are no-ops on `nil`). No setter reads another attribute, so the order is behavior-equivalent to the original loop.

- [ ] **Step 2: Run the Move + parser + full suite, verify green.**

Run: `bundle exec rspec spec/move_spec.rb spec/parser_spec.rb && bundle exec rspec`
Expected: 129 examples, 0 failures.

- [ ] **Step 3: Prove the parse allocation drop.**

Run: `BENCH_N=50 bundle exec ruby bench/profile_parse.rb`
Expected: section 1 (`Parse-only allocations`) `total_allocated objects` is **lower** than the same run against the pre-optimization code. To get the reference number, stash the change first:

```bash
git stash
BENCH_N=50 bundle exec ruby bench/profile_parse.rb   # note the §1 total_allocated objects
git stash pop
BENCH_N=50 bundle exec ruby bench/profile_parse.rb   # must be smaller
```

- [ ] **Step 4: Commit.**

```bash
git add lib/pgn/move.rb
git commit -m "perf: explicit setters in Move#initialize (drop per-move names array)"
```

---

## Task 5: `FEN#board_string` — single-pass serialization

**Files:**
- Modify: `lib/pgn/fen.rb`
- Modify: `spec/fen_spec.rb` (append a new `describe` block)

**Interfaces:**
- Produces: `FEN#board_string` returns the identical string as before, built in one pass with run-length counting of empty squares (no `_` placeholder, no `gsub`).

- [ ] **Step 1: Add a round-trip guard to `spec/fen_spec.rb`** (the existing `fen_spec` checks FEN attributes via accessors, not `to_s`, so `board_string` is under-tested). Append at the end of the file, inside the outer `describe PGN::FEN do`:

```ruby

  describe "board_string round-trip" do
    fens = [
      PGN::FEN::INITIAL,
      "r1bqkb1r/pp1p1ppp/2n1pn2/8/3NP3/2N5/PPP2PPP/R1BQKB1R w KQkq - 3 6",
      "8/8/8/8/8/8/8/8 w - - 0 1",
      "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1",
      "4k3/4P3/8/8/8/8/8/4K3 w - - 0 1",
      "rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3",
    ]

    it "round-trips every fixture through FEN#to_s" do
      fens.each do |fen|
        expect(PGN::FEN.new(fen).to_s).to eq(fen), fen
      end
    end

    it "round-trips the board portion through FEN#to_position.to_fen" do
      fens.each do |fen|
        original  = PGN::FEN.new(fen)
        roundtrip = original.to_position.to_fen
        expect(roundtrip.board_string).to eq(original.board_string), fen
      end
    end
  end
```

The second test asserts only `board_string`, not a full-FEN `to_s` round-trip, because `FEN#to_position` has a pre-existing en-passant-target bug that is out of scope for this efficiency plan. This test still exercises the new `board_string` implementation through `to_fen`.

If the closing `end` of the outer `describe` is the last line, insert this block **before** that final `end` (use `read` to confirm the structure first).

- [ ] **Step 2: Run the new spec against the CURRENT `board_string` and verify it passes** (this proves the fixtures are valid before changing the method).

Run: `bundle exec rspec spec/fen_spec.rb`
Expected: PASS (the current map→gsub implementation produces these strings).

- [ ] **Step 3: Replace `board_string` in `lib/pgn/fen.rb`.** The current method maps `nil`→`"_"`, joins, then `gsub(/_+/)` to counts. Replace it with a single-pass builder:

```ruby
    def board_string
      rows = self.board.squares.transpose.reverse
      rows.map do |row|
        s = +""
        run = 0
        row.each do |e|
          if e.nil?
            run += 1
          else
            s << run.to_s if run > 0
            run = 0
            s << e
          end
        end
        s << run.to_s if run > 0
        s
      end.join("/")
    end
```

- [ ] **Step 4: Run fen + full suite, verify green.**

Run: `bundle exec rspec spec/fen_spec.rb && bundle exec rspec`
Expected: **131 examples, 0 failures** (the 129 existing specs plus the 2 new round-trip examples). The `PGN::Position.start.to_fen.to_s == PGN::FEN::INITIAL` case (from `position_spec`) is the key byte-identity check.

- [ ] **Step 5: Commit.**

```bash
git add lib/pgn/fen.rb spec/fen_spec.rb
git commit -m "perf: single-pass FEN#board_string; add round-trip spec"
```

---

## Task 6: `Board` column-level copy-on-write (headline)

**Files:**
- Modify: `lib/pgn/board.rb`

**Interfaces:**
- Produces: `Board#dup` returns a board sharing the 8 column arrays with the original (shallow); `Board#update` clones only the column it mutates. `change!` is unchanged in shape (delegates to `update`). `at`, `coordinates_for`, `inspect`, `position_for`, `START`, and the constants are unchanged.
- Constraint: relies on `PGN::Board.new` storing the passed `squares` array by reference (current implementation does; it does not clone inner columns).

This is the biggest win **and** the riskiest change, so it ships last with the full 32-test `move_calculator_spec` + 12-test `board_spec` as the gate. Because positions are never mutated after creation, sharing unchanged columns across a move history is safe and also cuts peak memory for `Game#positions`.

- [ ] **Step 1: Confirm no code mutates a board's inner arrays directly (outside `Board`).** A direct `squares[f][r] =` would now corrupt a shared column. Check:

Run: `grep -rn "squares\[" lib spec | grep -v "lib/pgn/board.rb"`
Expected: only reads (`squares.transpose`, `squares[file][rank]` on the RHS of an equality / in `at`), no `squares[..][..] =` assignments outside `board.rb`. If any direct mutation exists, stop and route it through `update`.

- [ ] **Step 2: Replace `dup`, `update`, and `change!` in `lib/pgn/board.rb`.** The current methods are:

```ruby
    def change!(changes)
      changes.each do |square, piece|
        update(square, piece)
      end
      self
    end
    def update(square, piece)
      coords = coordinates_for(square)
      squares[coords[0]][coords[1]] = piece
      self
    end
    def dup
      PGN::Board.new(squares.map(&:dup))
    end
```

Replace with copy-on-write versions (`update` parses the square inline with `getbyte` so the hot path allocates no coordinate array, and clones only the column it touches):

```ruby
    def change!(changes)
      changes.each do |square, piece|
        update(square, piece)
      end
      self
    end

    # Copy-on-write: clone only the column being mutated so unchanged
    # columns stay shared with any board this one was duped from.
    def update(square, piece)
      file = square.getbyte(0) - 97
      rank = square.getbyte(1) - 49
      squares[file] = squares[file].dup
      squares[file][rank] = piece
      self
    end

    # Shallow dup: the outer array is copied, the 8 column arrays are
    # shared. Columns are cloned lazily by #update on first mutation.
    def dup
      PGN::Board.new(squares.dup)
    end
```

- [ ] **Step 3: Run the board + calculator + full suite, verify green.**

Run: `bundle exec rspec spec/board_spec.rb spec/move_calculator_spec.rb && bundle exec rspec`
Expected: 129 examples, 0 failures. Pay attention to the `#dup` independence examples and every castling/en-passant/disambiguation calculator case (these exercise `result_board` → `dup` + `change!`).

- [ ] **Step 4: Prove the allocation drop on the headline metrics.**

Run: `bundle exec ruby bench/profile_moves.rb`
Expected vs `bench/baseline_moves.pre-optimization.txt`:
- §2 `Board#dup x45` `total_allocated objects`: 451 → ~90 (shallow dup = 1 board + 1 outer array per dup).
- §1 `Replay allocations (45 plies)` `total_allocated objects`: 5124 → notably lower (per-ply board cost drops from ~10 allocs to ~4).

- [ ] **Step 5: Commit.**

```bash
git add lib/pgn/board.rb
git commit -m "perf: column-level copy-on-write Board (dup shares columns, update clones one)"
```

---

## Task 7: Re-capture the AFTER baseline, record deltas, final verification

**Files:**
- Modify: `bench/baseline_moves.txt`
- Modify: `bench/baseline_parse.txt`
- Create: `bench/IMPROVEMENTS.md`

**Interfaces:**
- Produces: refreshed `bench/baseline_*.txt` reflecting the optimized code, and `bench/IMPROVEMENTS.md` recording before→after deltas for the headline metrics.

- [ ] **Step 1: Refresh the committed baselines (N=500, the same as the BEFORE).**

Run: `bundle exec rake bench`
Expected: `bench/baseline_moves.txt` and `bench/baseline_parse.txt` are rewritten with the AFTER numbers; both print all four sections.

- [ ] **Step 2: Extract the headline numbers from BEFORE and AFTER.**

```bash
echo "== moves ==" 
echo "BEFORE:"; grep "total_allocated" bench/baseline_moves.pre-optimization.txt
echo "AFTER:";  grep "total_allocated" bench/baseline_moves.txt
echo "== parse =="
echo "BEFORE:"; grep "total_allocated" bench/baseline_parse.pre-optimization.txt
echo "AFTER:";  grep "total_allocated" bench/baseline_parse.txt
```

- [ ] **Step 3: Generate `bench/IMPROVEMENTS.md` from the actual baseline numbers.**

The numbers from Step 2 are written into the doc automatically; there are no hand-filled placeholders.

```bash
bundle exec ruby -e '
def values(path, kind)
  File.read(path).scan(/total_allocated #{kind}:\s+(\d+)/).flatten
end

mb_obj = values("bench/baseline_moves.pre-optimization.txt", "objects")
mb_byt = values("bench/baseline_moves.pre-optimization.txt", "bytes")
ma_obj = values("bench/baseline_moves.txt", "objects")
ma_byt = values("bench/baseline_moves.txt", "bytes")

pb_obj = values("bench/baseline_parse.pre-optimization.txt", "objects")
pb_byt = values("bench/baseline_parse.pre-optimization.txt", "bytes")
pa_obj = values("bench/baseline_parse.txt", "objects")
pa_byt = values("bench/baseline_parse.txt", "bytes")

def row(label, before, after)
  b = before.to_i
  a = after.to_i
  delta = b - a
  sign = case delta <=> 0
         when 1  then "-"
         when -1 then "+"
         else ""
         end
  "| #{label} | #{before} | #{after} | #{sign}#{delta.abs} |"
end

File.write("bench/IMPROVEMENTS.md", <<~MD)
# Efficiency improvements — before/after

Captured by `rake bench` on the same machine. "BEFORE" = `bench/*.pre-optimization.txt`
(pre-optimization snapshot). "AFTER" = `bench/baseline_*.txt`.

## bench/profile_moves.rb (immortal game, 45 plies)

| Metric | BEFORE | AFTER | Δ |
|---|---|---|---|
#{row("Replay allocations (objects)", mb_obj[0], ma_obj[0])}
#{row("Replay allocations (bytes)",  mb_byt[0], ma_byt[0])}
#{row("Board#dup x45 (objects)",     mb_obj[1], ma_obj[1])}
#{row("Board#dup x45 (bytes)",       mb_byt[1], ma_byt[1])}
#{row("Board#at(str) x1000 (objects)", mb_obj[2], ma_obj[2])}
#{row("Board#at(str) x1000 (bytes)",  mb_byt[2], ma_byt[2])}

## bench/profile_parse.rb (500 immortal games)

| Metric | BEFORE | AFTER | Δ |
|---|---|---|---|
#{row("Parse-only allocations (objects)",   pb_obj[0], pa_obj[0])}
#{row("Parse-only allocations (bytes)",       pb_byt[0], pa_byt[0])}
#{row("Parse + replay allocations (objects)",  pb_obj[1], pa_obj[1])}
#{row("Parse + replay allocations (bytes)",    pb_byt[1], pa_byt[1])}

## Changes applied

1. `Board#at(str)` / `coordinates_for` — getbyte arithmetic (zero-alloc string lookup).
2. `MoveCalculator#king_position` — early exit.
3. `Move#initialize` — explicit setters (no per-move `names` array).
4. `FEN#board_string` — single-pass serialization.
5. `Board` — column-level copy-on-write (`dup` shares columns, `update` clones one).

All existing characterization specs remain green; public output (FEN, PGN) is byte-identical.
MD
'
```

Then verify the generated file exists and contains no `<fill>` strings:

Run: `ls bench/IMPROVEMENTS.md && grep -c '<fill>' bench/IMPROVEMENTS.md`
Expected: file exists; grep count is `0`.

- [ ] **Step 4: Final full-suite + baseline-stability verification.**

Run: `bundle exec rspec`
Expected: **131 examples, 0 failures**.

Run: `bundle exec rake bench` a second time.
Expected: completes without error; the AFTER `total_allocated` lines are identical to the first AFTER run (allocations are deterministic), confirming the committed baseline is stable.

- [ ] **Step 5: Commit.**

```bash
git add bench/baseline_moves.txt bench/baseline_parse.txt bench/IMPROVEMENTS.md
git commit -m "bench: refresh after-optimization baseline; record before/after deltas"
```

---

## Deferred work (not in this plan)

**Parser class-variable state (`@@pgn`, `@@game_comment` in `lib/pgn/parser.rb`).** This is a **correctness / reentrancy** issue, not an efficiency one: the whittle parser stashes per-game state in class variables, so it is not thread-safe and a leftover `@@game_comment` can leak between games across separate `PGN.parse` calls in the same process. It is intentionally **excluded from this plan** because:

- it is not an efficiency improvement (it would not move any `bench/` number), and this plan's scope is efficiency;
- it touches the fragile whittle grammar, where a half-baked fix risks breaking all 14 PGN fixtures' round-trips; and
- a correct fix (per-parse instance state instead of class state) needs its own design + its own plan, written against the parser spec.

Recommendation: write a separate `docs/superpowers/plans/<date>-parser-instance-state.md` for it. The efficiency wins in this plan are independent of it and ship regardless.

---

## Self-Review

**1. Goal coverage.** The goal is "reduce allocations, prove each win." Mapping:
- `at(str)` win → Task 2 (§3 metric). ✔
- `king_position` win → Task 3 (early-exit; metric is minor, honestly noted). ✔
- `Move#initialize` win → Task 4 (parse §1 metric). ✔
- `FEN#board_string` win → Task 5 (micro, spec-guarded). ✔
- `Board` COW win → Task 6 (§1, §2 metrics — the headline). ✔
- Proof via before/after diff → Task 1 (preserve BEFORE) + Task 7 (AFTER + `IMPROVEMENTS.md`). ✔

**2. Placeholder scan.** Removed all hand-filled placeholders. Task 7 Step 3 now generates `bench/IMPROVEMENTS.md` from the actual baseline files with a small Ruby script, so no `<fill>`, "TBD", or "implement later" remains in the plan. ✔

**3. Type / name consistency.**
- `Board#at(arg0, arg1 = nil)` handles both `at("e4")` (arg1 nil → getbyte) and `at(4, 3)` (arg1 non-nil → `squares[4][3]`); the integer-overload test `board.at(4, 3)` and `board.at(0, 0)` use non-nil arg1 (rank 0 is `0`, not `nil`), so the `unless arg1.nil?` branch is correct. ✔
- `Board#update` inlines `getbyte` consistent with Task 2's `coordinates_for` arithmetic (`a`=97, `'1'`=49). ✔
- `Board#dup` (`PGN::Board.new(squares.dup)`) returns a `PGN::Board`, matching the `#dup` spec's `be_a(PGN::Board)`. ✔
- `Move#initialize` explicit setter list matches the seven setters that exist in `move.rb` (`piece=`, `destination=`, `promotion=`, `check=`, `capture=`, `disambiguation=`, `castle=`); `normal` has no setter and is omitted, matching the original `respond_to?` skip. ✔
- `FEN#board_string` output is consumed by `to_s` and the Task 5 / position_spec round-trip checks, which assert byte-identity. ✔
- Task 1's `cp` preserves files that exist from the previous plan (`bench/baseline_moves.txt`, `bench/baseline_parse.txt`). ✔

**4. Risk ordering.** Tasks 2–5 are isolated, low-risk, and each ships a green suite independently. Task 6 (COW) is highest-risk and ships last, gated by the 32-test calculator suite + 12-test board suite; if it had to be reverted, Tasks 2–5's wins would remain committed. ✔

**5. Example-count & placeholder consistency.** The original Global Constraints claimed 129 specs green after every task, but Task 5 deliberately adds 2 new round-trip examples. The constraint and expected counts in Task 5 and Task 7 have been updated to 131 green examples. Task 7 Step 3 now generates `bench/IMPROVEMENTS.md` from actual numbers, eliminating all `<fill>` placeholders. ✔

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-12-efficiency-optimizations.md`.

Two execution options:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration.
   - **REQUIRED SUB-SKILL:** Use `superpowers:subagent-driven-development`.
2. **Inline Execution** — execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints for review.

Which approach?
