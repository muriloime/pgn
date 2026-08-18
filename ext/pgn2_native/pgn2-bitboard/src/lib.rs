//! Thin adapter over the `chessie` crate exposing the small surface the
//! `pgn2_native` magnus binding consumes. No chess logic lives here —
//! `chessie` is the engine. Kept as a separate crate so the perft oracle
//! stays testable in pure Rust (`cargo test -p pgn2-bitboard`) with no
//! Ruby in the loop.

pub mod board;
pub mod perft;

pub use board::Board;
