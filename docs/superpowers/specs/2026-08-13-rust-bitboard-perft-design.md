# Rust Bitboard Perft Backend (Magic Bitboards) — Design

**Goal:** Fast perft numbers, as the primary objective. A thin
legal-move Ruby API is a secondary byproduct. Ship as a *required
compiled Rust extension* distributed via **precompiled platform gems**
(`rb_sys` + `magnus` + `rake-compiler-dock`), with source-build for
local development. No pure-Ruby fallback for the shipped path.

> **Decision context:** This supersedes the older Group 4 idea of an
> optional bitboard/C backend with fallback. The chosen path is **3b**
> (precompiled platform gems). **3a** (source build inside Docker) is
> the documented interim until the prebuilt-gem CI is live.

## Scope and non-goals

- **Does NOT touch** the existing pure-Ruby 0x88 `Board` /
  `MoveCalculator` / `Notation`. The Rust engine is a separate
  bitboard engine keyed by FEN. Existing byte-identical FEN/PGN
  guarantees stay intact.
- **Does NOT replace** the in-progress `perf/attack-masks` work. That
  branch is a pure-Ruby mailbox (knight/king offset tables) perf track
  for the SAN/replay path, explicitly "no native." Magic bitboards live
  in Rust and are decoupled — related only conceptually (both precompute
  attack tables), not in code.
- **NOT a full chess library:** no evaluation, no search, no UCI, no
  Chess960, no tablebases. Perft-able move generator + make/unmake +
  legal-move filter only.
- Perft is verified against **published suites** (initial position,
  Kiwipete, positions 3–6) to known node counts — not against the Ruby
  engine, which has no legal-move API to cross-check against.

## Architecture

A Rust workspace at `ext/pgn2_native/` with two crates:

1. `pgn2-bitboard` (**lib**, no Ruby dependency): the chess engine.
   Board = 12 `u64` piece bitboards + side-to-move + castling rights +
   ep square + halfmove clock + fullmove number. Magic bitboards for
   slider attacks. make/unmake on a stack (unmake, not copy-make, to
   stay allocation-free — important for perft nps). Methods:
   `perft(depth)`, `legal_moves()`, `legal?(uci)`. **Unit-testable in
   pure Rust** (`cargo test`) against published perft values — no Ruby
   in the loop.

2. `pgn2_native` (**cdylib**): the magnus bindings, the only crate that
   touches Ruby. Exposes `PGN::Bitboard::Engine` (constructed from a FEN
   string) with:
   - `#perft(depth) -> Integer`
   - `#legal_moves -> Array<String>` (UCI: `e2e4`, `e1g1` for castling,
     `e7e8q` for promotion)
   - `#legal?(move) -> bool`

**Boundary principle:** the engine crate knows nothing about Ruby; the
binding crate is thin and is the only thing that touches magnus. This
keeps chess logic testable without Ruby and the bridge trivial/fast.

**Workspace layout (draft):**

```
ext/pgn2_native/
├── Cargo.toml           # workspace manifest
├── extconf.rb           # Ruby build entry point
├── pgn2-bitboard/
│   ├── Cargo.toml       # crate-type = ["lib"]
│   └── src/
│       ├── lib.rs
│       ├── board.rs
│       ├── moves.rs
│       ├── magics.rs
│       └── perft_tests.rs
└── pgn2_native/
    ├── Cargo.toml       # crate-type = ["cdylib"]
    └── src/
        └── lib.rs       # magnus init + class bindings
```

```toml
# ext/pgn2_native/Cargo.toml
[workspace]
members = ["pgn2-bitboard", "pgn2_native"]
resolver = "2"
```

```toml
# ext/pgn2_native/pgn2_native/Cargo.toml
[package]
name = "pgn2_native"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
magnus = "0.8"
pgn2-bitboard = { path = "../pgn2-bitboard" }
```

## Ruby API surface (minimal)

- `PGN::Bitboard::Engine.new(fen).perft(depth) -> Integer` — primary.
- `PGN::Bitboard::Engine.new(fen).legal_moves -> Array<String>` — UCI
  strings (e.g. `e2e4`, `e1g1`, `e7e8q`). Sorted lexicographically so
  the output is stable across runs. UCI is unambiguous and trivial to
  emit; SAN (disambiguation/check/checkmate) is intentionally left to
  the existing pure-Ruby `PGN::Notation`, which can convert UCI→SAN
  later if desired.
- `PGN::Bitboard::Engine.new(fen).legal?(move) -> bool` — secondary.
- A new `PGN::Bitboard` module keeps the native surface isolated from
  the existing `PGN::Position`/`PGN::Board` (which stay pure Ruby). The
  compiled library is loaded by a tiny Ruby shim such as
  `lib/pgn/bitboard.rb`:
  ```ruby
  require "pgn2_native/pgn2_native"
  ```
- **Deferred:** having `PGN::Position#perft` delegate to the native
  engine when loaded. Keep the surface isolated until the engine is
  trusted.
- Only strings and integers cross the Ruby↔Rust boundary — no Ruby
  objects — so the bridge stays trivial and fast.

## Bridge and packaging

- `ext/pgn2_native/extconf.rb`:
  ```ruby
  require "mkmf"
  require "rb_sys/mkmf"

  create_rust_makefile("pgn2_native/pgn2_native")
  ```
- `pgn2.gemspec`:
  ```ruby
  spec.extensions = ["ext/pgn2_native/extconf.rb"]
  spec.add_dependency "rb_sys", "~> 0.9.39" # build/runtime helper until
                                            # RubyGems Rust support is stable
  spec.add_development_dependency "rake-compiler", "~> 1.2"
  spec.add_development_dependency "rake-compiler-dock", "~> 1.6"
  ```
  Because the gemspec uses `git ls-files`, make sure the Rust workspace
  is checked in and includes `Cargo.lock` so source builds are
  reproducible.
- `magnus` `#[magnus::init] fn init(...)` defines the `PGN::Bitboard`
  module + `Engine` class + methods. Wrap the Rust `Board`/`Engine`
  struct as opaque `TypedData` so Ruby owns the lifetime and cannot
  accidentally share mutable state across threads.
- **Local dev build:** `bundle exec rake compile` (rake-compiler task)
  invokes `cargo build --release`. Requires rustc/cargo locally.
- **Prebuilt gems (the 3b path):** a GitHub Actions workflow using
  `rake-compiler-dock` (rb_sys-compatible) cross-compiles
  `pgn2-<ver>-<platform>.gem` for `x86_64-linux`, `aarch64-linux`,
  `x86_64-darwin`, `aarch64-darwin` (Windows optional), pushed to
  RubyGems on release. Bundler then pulls the platform gem on the
  install host — **no toolchain required for end users.**

## Deployment (chessellence / Azure)

- chessellence `Gemfile` pins `pgn2` ≥ the native version.
- With prebuilt **linux** gems published, the Docker build stage's
  `bundle install` pulls the binary — **no Rust toolchain in the
  Dockerfile at all** (the goal of choosing 3b). The final slim image
  carries only the compiled `.so`.
- If a platform binary is ever missing, the build stage falls back to a
  source build (needs cargo). Mitigate by always publishing
  `x86_64-linux` + `aarch64-linux` (the Azure targets).
- **Interim** until the prebuilt-gem CI is live: chessellence deploys via
  the 3a source-build path (rustup in the Docker build stage only). Keep
  that documented in the rollout task.

## Correctness strategy

- Pure-Rust unit tests in `pgn2-bitboard` run on every CI: perft on the
  six standard positions to published depths. Key anchors:
  - Initial position, depth 6: **119,060,324** nodes.
  - Kiwipete, depth 5: **193,690,690** nodes.
  - Positions 3–6 to their known values (full table maintained in
    `src/perft_tests.rs`).

  These published counts are the **oracle**; there is no Ruby cross-check.
- **make/unmake symmetry test:** iterate perft over every move, then
  unmake each move, and assert the resulting FEN/bitboards match the
  original exactly.
- **Incremental legality test:** compared against a separate
  pin-and-check-aware legal-move generator as soon as one is written.
- A Ruby integration spec loads the ext (skip gracefully if not compiled)
  and asserts perft on a couple of positions matches known values — this
  guards the *binding*, not the engine.

## Engine details (magic bitboards)

- 12 `u64` bitboards (one per piece type per side); `white`/`black`/
  `occupied` derived on demand. Slider attack computations treat the
  moving slider's own square as empty (i.e. occupancy excludes that
  square) so rooks/bishops/queens can attack along their ray through the
  origin.
- Precomputed knight/king attack tables; pawn attack tables; the 8 ray
  directions.
- **Slider attacks — BMI2 `pext` (implementation pivot):** the original
  design called for magic bitboards with verified precomputed magic
  numbers. Implementation instead uses the hardware `pext` instruction
  to build a perfect bit-extract index (`((occ & mask) * magic) >> shift` is
  replaced by `_pext_u64(occ & mask, mask)`), with a ray-walker fallback
  on non-BMI2 targets (e.g. aarch64). Reasons: (1) random-candidate magic
  search at `shift = 64 - bits` is effectively non-converging for a 12-bit
  rook mask (~7.4M different-class subset pairs into 4096 bins → thousands
  of collisions per trial); only specially-constructed magics work, and
  transcribing published magics is a debugging hazard; (2) `pext` is
  deterministic, search-free, instant to build, and collision-free by
  construction; (3) the deploy target (Azure x86-64 Docker) has BMI2. The
  magic-vs-reference validation tests are kept (now validating pext vs the
  ray walker) for every square × subset. The public Rust/Ruby surface is
  unchanged.
- **Move encoding:** pack each move into a small integer (`from`:6 bits,
  `to`:6 bits, `promotion`:3 bits, `capture`:1 bit, etc.) so move lists
  and the make/unmake stack are cache-friendly and allocation-free.
- **Move generation:** pseudo-legal from attack sets; legality by **make +
  king-not-in-check filter** first (correctness-first, simplest to get
  right), then optimize to pin-aware generation if needed to hit the nps
  target.
- **make/unmake:** all game-state mutations go onto a fixed-capacity
  history stack inside the engine. A single `make`/`unmake` pair must
  restore the board, side-to-move, castling rights, ep target, and
  clocks bit-for-bit.
- **Castling representation:** update the rook bitboard when a king move
  crosses the castling line; legality of castling is checked by
  verifying the king does not pass through or into check.
- Zobrist **not** needed for perft — omit for now.

## Risks and honest notes

- Slider setup was originally the trickiest part; the `pext` pivot
  (above) removes both the magic-search and the transcription hazard.
  On non-BMI2 targets the ray-walker fallback is correct but slower —
  add magic tables for aarch64 later if its perft nps matters.
- The precompiled-gem CI (`rake-compiler-dock`) is real setup work;
  budget it as its own task. Until live, deploy via 3a source-build
  (documented interim).
- The first PR brings the engine + `#perft`; `#legal_moves`/`#legal?`
  follow once perft is trusted.
- A required native extension changes the public gem contract: every
  installer now gets a binary or builds from source. This is acceptable
  per the decision, and is mitigated by prebuilt gems for common
  platforms. Users on an unusual platform without a prebuilt need a
  source build (cargo toolchain) — document this in the README.
- Threading / GC: `Engine` wraps a Rust struct containing mutable game
  state. Keep it tied to one Ruby object and do not expose
  `Ractor`-shareable wrappers until the bindings explicitly support it.

## Testing

- **Rust:** `cargo test` — perft suites, make/unmake symmetry,
  magic-table sanity.
- **Ruby:** rspec, ext-gated; CI runs `cargo test` then `rspec`
  (rspec compiles the ext first via the rake-compiler task).
- **Bench:** `bench/perft.rb` runs perft on the standard positions,
  reports nps; compare against published / chess.js baseline.

## Global constraints

- The existing pure-Ruby suite stays byte-identical and green; no
  change to the 0x88 `Board` / `Notation` / `MoveCalculator`.
- TDD on the Rust engine — the perft values *are* the tests.
- Commit per task.
