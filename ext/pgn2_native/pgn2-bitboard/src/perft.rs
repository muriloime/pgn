use crate::board::Board;
use crate::moves::{Flag, MoveList};
use crate::square::Square;

impl Board {
    /// Perft (full-width legal move count) to `depth`.
    ///
    /// Fast path: pseudo-gen + make/unmake on a single working board (one clone
    /// total, not one per move) with bulk-counting at depth 1. Legality is
    /// tested by making the move and checking the own king is not in check;
    /// castling also requires the king's start/transit/destination squares to
    /// be unattacked in the pre-move position.
    pub fn perft(&self, depth: u32) -> u64 {
        crate::attacks::init();
        let mut b = self.clone();
        b.perft_rec(depth)
    }

    fn perft_rec(&mut self, depth: u32) -> u64 {
        if depth == 0 {
            return 1;
        }
        let list = self.gen_pseudo();
        let us = self.side;
        let them = us.opposite();
        let mut nodes = 0u64;
        for m in list.iter().copied() {
            if m.flag() == Flag::Castle {
                let (ksq, mid) = castle_path(us, m);
                if self.is_attacked(ksq, them)
                    || self.is_attacked(mid, them)
                    || self.is_attacked(m.to(), them)
                {
                    continue;
                }
            }
            let undo = self.make(m);
            if self.in_check(us) {
                self.unmake(m, undo);
                continue;
            }
            if depth == 1 {
                nodes += 1;
            } else {
                nodes += self.perft_rec(depth - 1);
            }
            self.unmake(m, undo);
        }
        nodes
    }
}

fn castle_path(us: crate::piece::Color, m: crate::moves::Move) -> (Square, Square) {
    let rank = if us == crate::piece::Color::White { 0u8 } else { 7u8 };
    let ksq = Square::from_algebraic(4, rank);
    match m.to() {
        s if s == Square::from_algebraic(6, rank) => (ksq, Square::from_algebraic(5, rank)),
        _ => (ksq, Square::from_algebraic(3, rank)),
    }
}

#[cfg(test)]
mod tests {
    use crate::board::Board;

    struct Case { fen: &'static str, depth: u32, nodes: u64 }

    fn run(c: Case) {
        crate::attacks::init();
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

    #[test]
    fn make_unmake_symmetry_via_perft() {
        crate::attacks::init();
        let f = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1";
        let mut b = Board::from_fen(f).unwrap();
        let before = b.clone();
        for m in b.legal_moves().iter() {
            let undo = b.make(*m);
            b.unmake(*m, undo);
            assert_eq!(b, before, "unmake diverged after move {:?}", m);
        }
    }
}
