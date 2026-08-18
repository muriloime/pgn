use std::cell::RefCell;

use magnus::prelude::*;
use magnus::{method, Error, Ruby};
use pgn2_bitboard::Board;

/// `PGN::Bitboard::Engine` — a magic/pext bitboard engine holding a position.
///
/// Constructed with a FEN string; `#perft(depth)` does a full-width perft.
/// The wrapped board is held in a `RefCell`; `perft` borrows immutably (it
/// clones internally for make/unmake), so no `&mut` crosses the FFI boundary.
#[derive(Default)]
#[magnus::wrap(class = "PGN::Bitboard::Engine", free_immediately)]
struct Engine(RefCell<Board>);

impl Engine {
    fn initialize(ruby: &Ruby, rb_self: &Self, fen: String) -> Result<(), Error> {
        let board = Board::from_fen(&fen)
            .map_err(|e| Error::new(ruby.exception_arg_error(), e))?;
        *rb_self.0.borrow_mut() = board;
        Ok(())
    }

    fn perft(&self, depth: u32) -> u64 {
        self.0.borrow().perft(depth)
    }

    fn legal_moves_ruby(&self) -> Vec<String> {
        let mut v: Vec<String> = self.0.borrow().legal_moves().iter().map(|m| m.to_uci()).collect();
        v.sort();
        v
    }

    fn legal_p(&self, uci: String) -> bool {
        // `chessie::Move`'s `PartialEq<str>` compares by `to_uci()`, so this
        // matches on castle/promotion notation the same way `legal_moves_ruby`
        // renders it — no separate UCI parser needed.
        self.0.borrow().legal_moves().iter().any(|m| m == &uci)
    }
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let engine = ruby
        .define_module("PGN")?
        .define_module("Bitboard")?
        .define_class("Engine", ruby.class_object())?;
    engine.define_alloc_func::<Engine>();
    engine.define_method("initialize", method!(Engine::initialize, 1))?;
    engine.define_method("perft", method!(Engine::perft, 1))?;
    engine.define_method("legal_moves", method!(Engine::legal_moves_ruby, 0))?;
    engine.define_method("legal?", method!(Engine::legal_p, 1))?;
    Ok(())
}
