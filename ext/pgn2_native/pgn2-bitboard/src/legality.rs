use crate::attacks;
use crate::board::Board;
use crate::moves::{Flag, Move, MoveList};
use crate::piece::{Color, PieceKind};
use crate::square::Square;

impl Board {
    /// Is `sq` attacked by any piece of color `by`?
    pub fn is_attacked(&self, sq: Square, by: Color) -> bool {
        attacks::init();
        let occ = self.occupied();
        // Pawns: a square is attacked by a white pawn iff a white pawn sits on
        // the black-pawn attack set of that square (one rank down, diagonal).
        let pawn_att = if by == Color::White { attacks::bpawn_att(sq) } else { attacks::wpawn_att(sq) };
        if !(self.piece_bb(by, PieceKind::Pawn) & pawn_att).is_empty() { return true; }
        if !(self.piece_bb(by, PieceKind::Knight) & attacks::knight(sq)).is_empty() { return true; }
        if !(self.piece_bb(by, PieceKind::King) & attacks::king(sq)).is_empty() { return true; }
        let diag = self.piece_bb(by, PieceKind::Bishop) | self.piece_bb(by, PieceKind::Queen);
        if !(diag & attacks::bishop_attacks(sq, occ)).is_empty() { return true; }
        let orth = self.piece_bb(by, PieceKind::Rook) | self.piece_bb(by, PieceKind::Queen);
        if !(orth & attacks::rook_attacks(sq, occ)).is_empty() { return true; }
        false
    }

    pub fn king_sq(&self, c: Color) -> Square {
        self.piece_bb(c, PieceKind::King).iter().next().expect("no king")
    }

    pub fn in_check(&self, c: Color) -> bool {
        self.is_attacked(self.king_sq(c), c.opposite())
    }

    /// Pseudo-legal moves filtered to legal ones via make/unmake on a single
    /// working copy (one clone total, not one per pseudo-move). Castling
    /// requires the king's start, transit, and destination squares to be
    /// unattacked in the pre-move position.
    pub fn legal_moves(&self) -> MoveList {
        attacks::init();
        let us = self.side;
        let them = us.opposite();
        let mut b = self.clone();
        let mut out = MoveList::new();
        for m in self.gen_pseudo().iter().copied() {
            if m.flag() == Flag::Castle {
                let (ksq, mid) = castle_path(us, m);
                if self.is_attacked(ksq, them)
                    || self.is_attacked(mid, them)
                    || self.is_attacked(m.to(), them)
                {
                    continue;
                }
            }
            let undo = b.make(m);
            if !b.in_check(us) {
                out.push(m);
            }
            b.unmake(m, undo);
        }
        out
    }
}

/// (king_start, transit_square) for a castling move; the king's destination is
/// checked separately via make + in_check.
fn castle_path(us: Color, m: Move) -> (Square, Square) {
    use crate::square::Square;
    let rank = if us == Color::White { 0u8 } else { 7u8 };
    let ksq = Square::from_algebraic(4, rank);
    match m.to() {
        s if s == Square::from_algebraic(6, rank) => (ksq, Square::from_algebraic(5, rank)),
        _ => (ksq, Square::from_algebraic(3, rank)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::board::Board;
    use crate::moves::Flag;
    use crate::square::Square;

    #[test]
    fn startpos_legal_moves_20() {
        crate::attacks::init();
        let b = Board::from_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1").unwrap();
        assert_eq!(b.legal_moves().len(), 20);
    }

    #[test]
    fn castle_through_check_blocked() {
        crate::attacks::init();
        // black rook on g8 controls the g-file; white O-O (king e1->g1) is blocked.
        let b = Board::from_fen("6r1/8/8/8/8/8/8/R3K2k w Q - 0 1").unwrap();
        let legal = b.legal_moves();
        let castle_moves: Vec<_> = legal.iter().filter(|m| m.flag() == Flag::Castle).collect();
        assert!(castle_moves.iter().all(|m| m.to() != Square::from_algebraic(6, 0)),
            "O-O through/into g-file must be illegal: {castle_moves:?}");
    }

    #[test]
    fn in_check_detects_rook_check() {
        crate::attacks::init();
        // black rook e8 checks white king e1 (open e-file).
        let b = Board::from_fen("4r3/8/8/8/8/8/8/4K2k w - - 0 1").unwrap();
        assert!(b.in_check(Color::White));
    }
}
