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
        let moves: Vec<Move> = self
            .game
            .get_legal_moves()
            .into_iter()
            .map(Move::from_chessie)
            .collect();
        MoveList(moves)
    }
}
