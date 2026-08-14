# Chessie Backend Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hand-rolled `pgn2-bitboard` chess engine on `main`
with a thin adapter over the `chessie` crate (MPL-2.0), keeping the
`pgn2_native` magnus binding and the Ruby `PGN::Bitboard::Engine`
surface byte-for-byte identical and ~4–6× faster.

**Architecture:** `pgn2-bitboard` becomes a ~3-file adapter crate
(`board.rs`, `moves.rs`, `perft.rs` tests) that wraps `chessie::Game` and
exposes exactly the public API the `pgn2_native` binding already
consumes (`Board::from_fen`/`perft`/`legal_moves`, `moves::uci_parse`,
`Move::to_uci`/`same_target`, `MoveList`). The five hand-rolled
chess-logic modules (`square`, `piece`, `attacks`, `magics`, the old
`moves`/`legality`/`perft` impls) are deleted. The `pgn2_native`
binding crate is **not modified** — it keeps importing
`pgn2_bitboard::Board` and `pgn2_bitboard::moves::uci_parse`. The Ruby
surface (`PGN::Bitboard::Engine#perft`/`#legal_moves`/`#legal?`,
`PGN::Position#perft`/`#legal_moves` delegations, `bench/perft.rb`) is
unchanged. License compliance is handled by a `NOTICE`/license
declaration addition.

**Tech Stack:** Rust 2021, `chessie` 2.0 (MPL-2.0, pure-Rust, no C deps),
`magnus` 0.8, `rb_sys`, RSpec, `cargo test` (perft oracle).

## Global Constraints

- The `pgn2_native` binding crate source (`ext/pgn2_native/pgn2_native/src/lib.rs`)
  is **not modified** — the adapter must preserve its consumed API
  verbatim: `pgn2_bitboard::Board` (with `Board::from_fen(&str) -> Result<Board, String>`,
  `Board::perft(&self, depth: u32) -> u64`, `Board::legal_moves(&self) -> MoveList`,
  and `#[derive]` of at least `Default`), `pgn2_bitboard::moves::uci_parse(&str) -> Option<Move>`,
  and `Move` (with `Move::to_uci(self) -> String`, `Move::same_target(self, Move) -> bool`,
  `Move: Copy`).
- The pure-Ruby suite and the byte-identical FEN/PGN guarantees stay intact;
  no change to `lib/pgn/board.rb`, `notation.rb`, `move_calculator.rb`,
  `position.rb` delegations, or `bench/perft.rb`.
- The published perft values remain the oracle; `spec/bitboard_spec.rb`
  and `ext/.../pgn2-bitboard/src/perft.rs` both stay green unchanged.
- `chessie` is MPL-2.0; the gem stays MIT, but MPL attribution is added
  (Task 2). The gem's own source is not relicensed.
- Commit per task. `Cargo.lock` is committed (gemspec uses `git ls-files`).
- Only strings and integers cross the Ruby↔Rust boundary (unchanged).

---

## File Structure

**Deleted** (hand-rolled chess logic, replaced by `chessie`):
- `ext/pgn2_native/pgn2-bitboard/src/square.rs`
- `ext/pgn2_native/pgn2-bitboard/src/piece.rs`
- `ext/pgn2_native/pgn2-bitboard/src/attacks.rs`
- `ext/pgn2_native/pgn2-bitboard/src/magics.rs`

**Rewritten** (adapter):
- `ext/pgn2_native/pgn2-bitboard/src/lib.rs` — re-exports only.
- `ext/pgn2_native/pgn2-bitboard/src/board.rs` — `Board { game: chessie::Game }`
  + `from_fen`/`perft`/`legal_moves`.
- `ext/pgn2_native/pgn2-bitboard/src/moves.rs` — `Move`/`MoveList` adapter +
  `uci_parse`.
- `ext/pgn2_native/pgn2-bitboard/src/perft.rs` — perft oracle tests only
  (no engine impl, no `attacks::init`).

**Modified:**
- `ext/pgn2_native/pgn2-bitboard/Cargo.toml` — add `chessie = "2.0"`.
- `ext/pgn2_native/Cargo.lock` — regenerated (chessie + chessie_types + anyhow + arrayvec).
- `ext/pgn2_native/Cargo.toml` — update the stale `[profile.test]` comment.
- `pgn2.gemspec` — declare MPL-2.0 alongside MIT.
- `NOTICE.md` (new) — chessie MPL-2.0 attribution + source pointer.
- `docs/superpowers/specs/2026-08-13-rust-bitboard-perft-design.md`,
  `README.md`, `CHANGELOG.md` — reflect chessie backend.
- `lib/pgn/bitboard.rb`, `.github/workflows/native.yml` — comment cleanup.

**Unchanged (verified, not edited):**
- `ext/pgn2_native/pgn2_native/src/lib.rs` (binding), `pgn2_native/Cargo.toml`,
  `lib/pgn/position.rb`, `bench/perft.rb`, `spec/bitboard_spec.rb`,
  `.github/workflows/release-gems.yml`.

---

## Task 1: Replace `pgn2-bitboard` with a `chessie`-backed adapter

The migration core. One cohesive change — the adapter's pieces can't
be independently rejected (Board/Move/legal_moves are one contract). The
existing perft oracle (`perft.rs`) and `spec/bitboard_spec.rb` are the
regression guards; they stay green.

**Files:**
- Create: `ext/pgn2_native/pgn2-bitboard/src/lib.rs` (rewrite)
- Create: `ext/pgn2_native/pgn2-bitboard/src/board.rs` (rewrite)
- Create: `ext/pgn2_native/pgn2-bitboard/src/moves.rs` (rewrite)
- Create: `ext/pgn2_native/pgn2-bitboard/src/perft.rs` (rewrite, tests only)
- Delete: `square.rs`, `piece.rs`, `attacks.rs`, `magics.rs`
- Modify: `ext/pgn2_native/pgn2-bitboard/Cargo.toml`
- Regenerate: `ext/pgn2_native/Cargo.lock`

**Interfaces:**
- Consumes: `chessie 2.0` — `chessie::Game` (`Game::from_fen(&str) -> Result<Game>`,
  `Game::perft(&self, usize) -> u64`, `Game: Clone + Copy + PartialEq + Eq + Default`),
  `chessie::MoveGenIter` (`MoveGenIter::new(&Game) -> impl Iterator<Item = chessie::Move>`),
  `chessie::Move` (`Move::from(&self) -> Square`, `Move::to(&self) -> Square`,
  `Move::promotion(&self) -> Option<PieceKind>`), `chessie::Square` (`Square::index(&self) -> usize`),
  `chessie::PieceKind` (`{Pawn, Knight, Bishop, Rook, Queen, King}`).
- Produces (preserved verbatim for the binding): `Board` (`from_fen`, `perft`, `legal_moves`,
  `Default`), `Move` (`to_uci`, `same_target`, `Copy`), `MoveList(pub Vec<Move>)` with `iter()`,
  `moves::uci_parse(&str) -> Option<Move>`.

- [ ] **Step 1: Add the `chessie` dependency**

`ext/pgn2_native/pgn2-bitboard/Cargo.toml`:
```toml
[package]
name = "pgn2-bitboard"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["lib"]

[dependencies]
chessie = "2.0"
```

- [ ] **Step 2: Rewrite `lib.rs` to re-export only the adapter**

`ext/pgn2_native/pgn2-bitboard/src/lib.rs`:
```rust
//! Thin adapter over the `chessie` crate exposing the small surface the
//! `pgn2_native` magnus binding consumes. No chess logic lives here —
//! `chessie` is the engine. Kept as a separate crate so the perft oracle
//! stays testable in pure Rust (`cargo test -p pgn2-bitboard`) with no
//! Ruby in the loop.

pub mod board;
pub mod moves;
pub mod perft;

pub use board::Board;
pub use moves::{Move, MoveList};
```

- [ ] **Step 3: Write the `Board` adapter**

`ext/pgn2_native/pgn2-bitboard/src/board.rs`:
```rust
use crate::moves::{Move, MoveList};

/// A chess position backed by `chessie::Game`. Holds no chess logic of
/// its own; every operation delegates. `Copy` because `chessie::Game`
/// is `Copy`; `Default` because the magnus `Engine` wraps it in a
/// `RefCell` and `#[derive(Default)]`s it.
#[derive(Clone, Copy, PartialEq, Eq, Default)]
pub struct Board {
    game: chessie::Game,
}

impl Board {
    pub fn from_fen(fen: &str) -> Result<Board, String> {
        chessie::Game::from_fen(fen)
            .map(|game| Board { game })
            .map_err(|e| e.to_string())
    }

    pub fn perft(&self, depth: u32) -> u64 {
        self.game.perft(depth as usize)
    }

    pub fn legal_moves(&self) -> MoveList {
        use chessie::MoveGenIter;
        let moves: Vec<Move> = MoveGenIter::new(&self.game)
            .map(Move::from_chessie)
            .collect();
        MoveList(moves)
    }
}
```

> `chessie::Game` derives `Clone, Copy, PartialEq, Eq` (verified in
> `chessie-2.0.0/src/game.rs:28`) but **not** `Debug`, so `Board` does
> not derive `Debug` either — nothing the binding or the oracle uses
> requires `Board: Debug`.

- [ ] **Step 4: Write the `Move` / `MoveList` adapter + `uci_parse`**

`ext/pgn2_native/pgn2-bitboard/src/moves.rs`:
```rust
/// Adapter move carrying exactly what `to_uci` and `same_target` need:
/// from-square, to-square, and optional promotion kind. No flag bits,
/// so a position-free `uci_parse` can produce a comparable token — this
/// preserves the existing `same_target` semantics (match on
/// from + to + promo only), so `legal?("e1g1")` finds the castle and
/// `legal?("e7e8q")` finds that exact promotion.
#[derive(Clone, Copy, PartialEq, Eq)]
pub struct Move {
    from: u8, // 0..=63, index = rank * 8 + file
    to: u8,
    promo: Option<Promo>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Promo { Knight, Bishop, Rook, Queen }

impl Move {
    /// Build an adapter `Move` from a `chessie::Move` (a legal move).
    pub(crate) fn from_chessie(m: chessie::Move) -> Self {
        Move {
            from: m.from().index() as u8,
            to: m.to().index() as u8,
            promo: m.promotion().map(|kind| match kind {
                chessie::PieceKind::Knight => Promo::Knight,
                chessie::PieceKind::Bishop => Promo::Bishop,
                chessie::PieceKind::Rook => Promo::Rook,
                chessie::PieceKind::Queen => Promo::Queen,
                // Pawns/Kings never appear as a promotion kind.
                _ => unreachable!("non-promotion PieceKind in Move::promotion"),
            }),
        }
    }

    /// UCI string: `"e2e4"`, `"e1g1"` (castle, king from→to),
    /// `"e7e8q"` (promotion). Equal to `chessie::Move::to_uci` for
    /// every legal move (castle and en-passant both reduce to from+to
    /// in UCI), so the sorted-UCI output is unchanged.
    pub fn to_uci(self) -> String {
        let mut s = String::with_capacity(5);
        s.push_str(&sq_name(self.from));
        s.push_str(&sq_name(self.to));
        if let Some(p) = self.promo {
            s.push(match p {
                Promo::Knight => 'n',
                Promo::Bishop => 'b',
                Promo::Rook => 'r',
                Promo::Queen => 'q',
            });
        }
        s
    }

    /// Match on from + to + promo (the pre-existing semantics).
    pub fn same_target(self, other: Move) -> bool {
        self.from == other.from && self.to == other.to && self.promo == other.promo
    }
}

/// Thin wrapper around `Vec<Move>`; the binding calls `.iter()` on it.
pub struct MoveList(pub Vec<Move>);
impl MoveList {
    pub fn iter(&self) -> std::slice::Iter<'_, Move> {
        self.0.iter()
    }
}

/// Parse a UCI string into a `Move` token **without** a position.
/// Only `to_uci`/`same_target` consume the result, so from + to + promo
/// is all that is needed. Returns `None` on any malformed input.
pub fn uci_parse(s: &str) -> Option<Move> {
    let b = s.as_bytes();
    if b.len() < 4 { return None; }
    let from = parse_sq(&b[0..2])?;
    let to = parse_sq(&b[2..4])?;
    let promo = if b.len() >= 5 {
        Some(match b[4] {
            b'n' => Promo::Knight,
            b'b' => Promo::Bishop,
            b'r' => Promo::Rook,
            b'q' => Promo::Queen,
            _ => return None,
        })
    } else { None };
    Some(Move { from, to, promo })
}

fn parse_sq(t: &[u8]) -> Option<u8> {
    let f = t[0].checked_sub(b'a')?;
    let r = t[1].checked_sub(b'1')?;
    if f > 7 || r > 7 { return None; }
    Some(r * 8 + f)
}

fn sq_name(idx: u8) -> String {
    let file = (b'a' + (idx & 7)) as char;
    let rank = (b'1' + (idx >> 3)) as char;
    let mut s = String::with_capacity(2);
    s.push(file);
    s.push(rank);
    s
}
```

- [ ] **Step 5: Rewrite `perft.rs` as the oracle tests (no engine impl)**

`ext/pgn2_native/pgn2-bitboard/src/perft.rs`:
```rust
//! Perft oracle — the published node counts are the test. The chess
//! logic lives in `chessie`; this file only exercises the adapter's
//! `Board::from_fen` + `Board::perft` end-to-end in pure Rust (no Ruby).

#[cfg(test)]
mod tests {
    use crate::board::Board;

    struct Case { fen: &'static str, depth: u32, nodes: u64 }

    fn run(c: Case) {
        let b = Board::from_fen(c.fen).unwrap();
        assert_eq!(b.perft(c.depth), c.nodes, "fen={} depth={}", c.fen, c.depth);
    }

    #[test]
    fn perft_startpos() {
        let f = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
        run(Case { fen: f, depth: 1, nodes: 20 });
        run(Case { fen: f, depth: 2, nodes: 400 });
        run(Case { fen: f, depth: 3, nodes: 8902 });
        run(Case { fen: f, depth: 4, nodes: 197281 });
        run(Case { fen: f, depth: 5, nodes: 4865609 });
    }

    #[test]
    fn perft_kiwipete() {
        let f = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1";
        run(Case { fen: f, depth: 1, nodes: 48 });
        run(Case { fen: f, depth: 2, nodes: 2039 });
        run(Case { fen: f, depth: 3, nodes: 97862 });
        run(Case { fen: f, depth: 4, nodes: 4085603 });
    }

    #[test]
    fn perft_pos3() {
        let f = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1";
        run(Case { fen: f, depth: 1, nodes: 14 });
        run(Case { fen: f, depth: 4, nodes: 43238 });
        run(Case { fen: f, depth: 5, nodes: 674624 });
    }

    #[test]
    fn perft_pos4() {
        let f = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1";
        run(Case { fen: f, depth: 1, nodes: 6 });
        run(Case { fen: f, depth: 3, nodes: 9467 });
        run(Case { fen: f, depth: 4, nodes: 422333 });
    }

    #[test]
    fn perft_pos5() {
        let f = "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8";
        run(Case { fen: f, depth: 3, nodes: 62379 });
        run(Case { fen: f, depth: 4, nodes: 2103487 });
    }

    #[test]
    fn perft_pos6() {
        let f = "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10";
        run(Case { fen: f, depth: 3, nodes: 89890 });
        run(Case { fen: f, depth: 4, nodes: 3894594 });
    }

    #[test]
    #[ignore] // slow; run with `cargo test -- --ignored`
    fn perft_deep() {
        let s = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
        run(Case { fen: s, depth: 6, nodes: 119060324 });
        let k = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1";
        run(Case { fen: k, depth: 5, nodes: 193690690 });
    }

    // The old `make_unmake_symmetry_via_perft` test is intentionally
    // removed: it exercised the hand-rolled make/unmake internals, which
    // no longer exist. chessie's own test suite covers its make/unmake.
}
```

- [ ] **Step 6: Delete the hand-rolled chess-logic modules**

```bash
cd ext/pgn2_native/pgn2-bitboard
git rm src/square.rs src/piece.rs src/attacks.rs src/magics.rs
```

- [ ] **Step 7: Regenerate `Cargo.lock` and run the perft oracle (pure Rust)**

```bash
cd ext/pgn2_native
cargo update -p pgn2-bitboard
cargo test -p pgn2-bitboard
```
Expected: PASS — `perft_startpos`, `perft_kiwipete`, `perft_pos3`,
`perft_pos4`, `perft_pos5`, `perft_pos6` all green. (These are the same
canonical counts chessie was verified against in the `exp/chessie-smoke`
run; pos5 d3 = 62379 is the repo's own canonical value.)
`perft_deep` is `#[ignore]`; optionally `cargo test -p pgn2-bitboard -- --ignored`.

- [ ] **Step 8: Build the whole workspace (binding compiles unchanged)**

```bash
cd ext/pgn2_native
cargo build
```
Expected: the `pgn2_native` cdylib compiles with **no edits** to
`pgn2_native/src/lib.rs` — it still imports `pgn2_bitboard::Board` and
`pgn2_bitboard::moves::uci_parse`, both preserved by the adapter.

- [ ] **Step 9: Compile the extension and run the full Ruby suite**

```bash
bundle exec rake compile
bundle exec rspec
```
Expected: all green, including `spec/bitboard_spec.rb` (perft values,
ArgumentError on bad FEN, sorted UCI legal_moves incl. `e2e4`/`g1f3`/`d2d4`,
`legal?` true/false, promotions `a7a8q/r/b/n`, castling `e1g1`/`e1c1`).

- [ ] **Step 10: Commit**

```bash
git add ext/pgn2_native/pgn2-bitboard/src ext/pgn2_native/pgn2-bitboard/Cargo.toml ext/pgn2_native/Cargo.lock
git commit -m "refactor(native): replace hand-rolled bitboard engine with chessie adapter

pgn2-bitboard becomes a ~3-file adapter over the chessie 2.0 crate
(MPL-2.0): Board wraps chessie::Game; perft/legal_moves delegate;
Move/MoveList/uci_parse preserve the exact API the pgn2_native magnus
binding consumes, so the binding source is unchanged. Deletes
square/piece/attacks/magics and the old moves/legality/perft impls.

Verified: cargo test -p pgn2-bitboard (perft oracle, all 6 positions)
+ cargo build (workspace) + rake compile + rspec (spec/bitboard_spec.rb)
all green. Head-to-head on znver5/BMI2: ~4.4-6.1x faster than the
hand-rolled engine (startpos d6 21.6->95.7 Mnps; kiwipete d5
23.2->142.6 Mnps; pos3 d6 18.8->90.7 Mnps)."
```

---

## Task 2: MPL-2.0 license compliance

`chessie` (and `chessie_types`) are MPL-2.0. The gem stays MIT; this
task only adds the required attribution and declares the aggregated
component. No source is relicensed.

**Files:**
- Create: `NOTICE.md`
- Modify: `pgn2.gemspec`

**Interfaces:** none.

- [ ] **Step 1: Add the attribution notice**

`NOTICE.md`:
```markdown
# Third-Party Notices

This gem bundles a compiled Rust extension (`pgn2_native`) that links
the `chessie` crate.

## chessie

- Source: https://crates.io/crates/chessie
- Repository: https://github.com/duck2/chessie
- Version: 2.0.x (see `ext/pgn2_native/Cargo.lock` for the exact pinned
  version)
- License: Mozilla Public License 2.0 (MPL-2.0)

`chessie` and its dependency `chessie_types` are MPL-2.0. They are used
unmodified. The MPL-2.0 license is file-level copyleft: it applies to
`chessie`'s own source files only and does not change the license of
this gem's code (MIT). Per MPL-2.0 §3.3, the source of the MPL-licensed
files is available at the repository URL above (and is reproducibly
pinned in `ext/pgn2_native/Cargo.lock`).

pgn2's own code remains MIT-licensed; see `LICENSE.txt`.
```

- [ ] **Step 2: Declare the aggregated license in the gemspec**

In `pgn2.gemspec`, replace the single `spec.license = 'MIT'` line with a
plural declaration covering the bundled component:

```ruby
  spec.licenses = ['MIT', 'MPL-2.0']
```

> RubyGems accepts `spec.licenses` (plural) for aggregated works. The
> gem's own code is MIT; the bundled `chessie` component is MPL-2.0
> (documented in `NOTICE.md`). If a single-string license is required by
> an older toolchain, keep `spec.license = 'MIT'` and rely on
> `NOTICE.md` for the MPL declaration — but prefer the plural form.

- [ ] **Step 3: Verify the gemspec still loads and `bundle install` is clean**

```bash
bundle exec ruby -e "puts Gem::Specification.load('pgn2.gemspec').licenses.inspect"
```
Expected: prints `["MIT", "MPL-2.0"]`. Then:

```bash
bundle install
bundle exec rake compile
bundle exec rspec
```
Expected: all green (no behavioral change from Task 1).

- [ ] **Step 4: Commit**

```bash
git add NOTICE.md pgn2.gemspec
git commit -m "docs(license): add MPL-2.0 notice for bundled chessie; declare aggregated license

chessie/chessie_types are MPL-2.0 (file-level copyleft). The gem stays
MIT; NOTICE.md credits chessie and points to its source (pinned in
Cargo.lock per MPL-2.0 §3.3). gemspec declares both licenses."
```

---

## Task 3: Update design spec, README, and CHANGELOG

The design doc and README describe the hand-rolled magic/pext engine;
that is now superseded by the chessie adapter. This task records the
change honestly without rewriting every stale line — a status banner +
targeted section updates + a CHANGELOG entry.

**Files:**
- Modify: `docs/superpowers/specs/2026-08-13-rust-bitboard-perft-design.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

**Interfaces:** none.

- [ ] **Step 1: Prepend a status banner to the design spec**

At the very top of `docs/superpowers/specs/2026-08-13-rust-bitboard-perft-design.md`,
above the `**Goal:**` line, insert:

```markdown
> **Status (2026-08-14):** The hand-rolled magic/pext engine described
> below has been replaced by a thin adapter over the `chessie` crate
> (MPL-2.0). See `docs/superpowers/plans/2026-08-14-chessie-migration.md`.
> The "Engine details (magic bitboards)" section is retained as the
> historical design rationale for the since-removed hand-rolled engine;
> the shipped engine is now `chessie` via the `pgn2-bitboard` adapter.
> The Ruby API surface, FEN-keyed boundary, and global constraints
> below are unchanged.
```

- [ ] **Step 2: Update the Architecture section's crate descriptions**

In `docs/superpowers/specs/2026-08-13-rust-bitboard-perft-design.md`, in
the `## Architecture` numbered list, replace the `pgn2-bitboard` item
(item 1) with:

```markdown
1. `pgn2-bitboard` (**lib**, no Ruby dependency): a thin adapter over
   the `chessie` crate (MPL-2.0). `Board` wraps `chessie::Game`; `perft`
   and `legal_moves` delegate; `Move`/`MoveList`/`uci_parse` expose the
   small surface the binding consumes. No chess logic lives in this
   crate — `chessie` is the engine. **Unit-testable in pure Rust**
   (`cargo test`) against published perft values — no Ruby in the loop.
```
Leave item 2 (`pgn2_native`) and the boundary principle unchanged.

- [ ] **Step 3: Add a CHANGELOG entry**

In `CHANGELOG.md`, under the next-unreleased section at the top, add:

```markdown
### Changed (native)

- The native bitboard engine is now a thin adapter over the `chessie`
  crate (MPL-2.0) instead of a hand-rolled magic/pext engine. The Ruby
  `PGN::Bitboard::Engine` surface (`#perft`, `#legal_moves`, `#legal?`)
  and `PGN::Position#perft`/`#legal_moves` delegations are unchanged.
  ~4–6× faster perft on x86-64/BMI2 (e.g. Kiwipete d5: ~23 → ~143 Mnps).
- The gem now bundles an MPL-2.0 component (`chessie`); the gem's own
  code remains MIT. See `NOTICE.md`. `pgn2.gemspec` declares both
  licenses.
```

- [ ] **Step 4: Update the README's native-engine description**

In `README.md`, find the native-engine section (the one added in commit
`1940baa` "ships with the gem, not 'optional'") and replace any phrase
describing the engine as "magic bitboard"/"pext"/"hand-rolled" with
"`chessie`-backed bitboard engine (MPL-2.0)". Add one line: "The engine
is the `chessie` crate; see `NOTICE.md` for license attribution."

> If the README has no engine-internals paragraph, just ensure it does
> not claim "magic bitboards" or "pext"; the public API description
> stays valid.

- [ ] **Step 5: Verify docs render and the suite still passes**

```bash
bundle exec rake compile && bundle exec rspec
```
Expected: green (docs-only change; no code touched).

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/specs/2026-08-13-rust-bitboard-perft-design.md README.md CHANGELOG.md
git commit -m "docs: record chessie backend migration (spec banner, README, CHANGELOG)"
```

---

## Task 4: Clean up stale references and verify CI

Comments and a workspace-manifest note still describe the removed
hand-rolled engine ("magic-bitboard search", "optional"). This task
fixes the stale strings and runs the full verification matrix the CI
uses, so the tree is release-ready.

**Files:**
- Modify: `ext/pgn2_native/Cargo.toml`
- Modify: `lib/pgn/bitboard.rb`
- Modify: `.github/workflows/native.yml`

**Interfaces:** none.

- [ ] **Step 1: Fix the workspace manifest's stale comment**

In `ext/pgn2_native/Cargo.toml`, replace the comment above
`[profile.test]`:

```toml
# The perft oracle does real work; optimize tests so `cargo test` runs
# in release-like time instead of minutes.
[profile.test]
opt-level = 2
```
(The old comment referenced "magic-bitboard search", which no longer
exists.)

- [ ] **Step 2: Fix the Ruby shim's stale comment**

In `lib/pgn/bitboard.rb`, change the header comment
"Load the native bitboard engine" / any "magic/pext" wording to
"Load the `chessie`-backed native bitboard engine". Do not change the
`require` line or the `rescue` behavior.

- [ ] **Step 3: Fix the CI workflow's stale framing**

In `.github/workflows/native.yml`, change the top comment block and the
job name/comment that say "optional Rust bitboard perft backend" /
"pure-Rust engine's `cargo test`" to reflect that the backend is
required and `chessie`-backed, e.g.:

```yaml
# Builds and tests the required Rust bitboard perft backend (a thin
# adapter over the `chessie` crate): runs the perft oracle via
# `cargo test`, compiles the native extension via `rake compile`, and
# runs the full RSpec suite (which loads the ext).
```
Do not change the step commands (`cargo test --manifest-path ...`,
`bundle exec rake compile`, `bundle exec rspec`) — only the comments.

- [ ] **Step 4: Run the full CI-equivalent verification matrix**

```bash
cargo test --manifest-path ext/pgn2_native/Cargo.toml
bundle exec rake compile
bundle exec rspec
bundle exec rubocop
```
Expected: `cargo test` green (perft oracle); `rake compile` builds the
cdylib; `rspec` all green; `rubocop` clean (no Ruby code changed, so no
new offenses).

- [ ] **Step 5: Sanity-check the cross-compile path is unaffected**

`chessie` is pure Rust (`chessie_types`, `anyhow`, `arrayvec` — no C
deps), so `rake-compiler-dock` cross-compilation in
`.github/workflows/release-gems.yml` is unaffected. Confirm no
workspace/Cargo.toml change re-introduces a C dependency:

```bash
cd ext/pgn2_native && cargo tree | grep -iE "\[build-dependencies\]|cc |cmake |libc " | head
```
Expected: empty (no C/link build-deps introduced).

- [ ] **Step 6: Commit**

```bash
git add ext/pgn2_native/Cargo.toml lib/pgn/bitboard.rb .github/workflows/native.yml
git commit -m "chore(native): drop stale magic/pext references in comments; verify CI matrix

Workspace manifest, Ruby shim, and native.yml comments now describe the
chessie-backed (required) backend instead of the removed hand-rolled
magic/pext engine. chessie is pure Rust, so cross-compile via
rake-compiler-dock is unaffected."
```

---

## Self-Review

**1. Spec coverage.** The migration decision (accept MPL-2.0, adopt
chessie) is fully covered: Task 1 = the adapter (the engine swap),
Task 2 = the MPL-2.0 obligation the decision accepted, Task 3 = docs
honesty, Task 4 = release-readiness. The binding crate and Ruby surface
are explicitly unchanged (Global Constraints + each task's "unchanged"
list). The perft oracle (`perft.rs`) and `spec/bitboard_spec.rb` are
the regression guards and are referenced in Task 1's verification.

**2. Placeholder scan.** No TBD/TODO/"implement later". Every code step
contains full file contents. The two conditional phrasings ("If the
README has no engine-internals paragraph…", "If a single-string license
is required…") give concrete fallbacks, not placeholders.

**3. Type consistency.** `Board` (`from_fen`, `perft(&self, u32)`,
`legal_moves(&self) -> MoveList`, `Default`) — matches the binding's
`Board::from_fen(&fen)`, `self.0.borrow().perft(depth)`,
`self.0.borrow().legal_moves()`, and `RefCell<Board>` `Default`. `Move`
(`to_uci(self)`, `same_target(self, Move)`, `Copy`) — matches the
binding's `m.to_uci()` and `m.same_target(parsed)` called on `&Move`
from `MoveList::iter()` (works because `Move: Copy`). `MoveList(pub
Vec<Move>)` with `iter()` — matches the binding's
`legal_moves().iter()`. `moves::uci_parse(&str) -> Option<Move>` —
matches `pgn2_bitboard::moves::uci_parse(&uci)`. Adapter `Move` uses
`from`/`to`/`promo` (not the old `pub u16` field); the binding never
touches `.0`, so the representation change is safe.
