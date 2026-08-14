use crate::board::Board;
use crate::moves::Move;

impl Board {
    /// Perft (full-width move count) to `depth`. Legal moves only.
    pub fn perft(&self, depth: u32) -> u64 {
        crate::attacks::init();
        let mut b = self.clone();
        b.perft_inner(depth)
    }

    fn perft_inner(&mut self, depth: u32) -> u64 {
        if depth == 0 { return 1; }
        let moves: Vec<Move> = self.legal_moves().iter().copied().collect();
        if depth == 1 { return moves.len() as u64; }
        let mut nodes = 0u64;
        for m in moves {
            let undo = self.make(m);
            nodes += self.perft_inner(depth - 1);
            self.unmake(m, undo);
        }
        nodes
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
