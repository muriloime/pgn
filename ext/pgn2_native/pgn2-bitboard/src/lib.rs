//! Pure-Rust bitboard chess engine. No Ruby dependency.

pub mod square;
pub mod piece;
pub mod board;
pub use square::{Bitboard, Square, BitboardIter};
pub use piece::{Color, PieceKind};
pub use board::Board;
