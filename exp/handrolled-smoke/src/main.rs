use pgn2_bitboard::Board;
use std::time::Instant;

fn main() {
    println!("== hand-rolled pgn2-bitboard nps bench (unmake, make+check legality) ==");
    for (name, fen, depth) in [
        ("startpos d6", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 6u32),
        ("kiwipete d5", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", 5),
        ("pos3   d6", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 6),
    ] {
        let g = Board::from_fen(fen).unwrap();
        let t = Instant::now();
        let n = g.perft(depth);
        let secs = t.elapsed().as_secs_f64();
        let nps = (n as f64 / secs) as u64;
        println!("  {:<14} nodes={:>12}  {:>8.3}s  {:>9} nps", name, n, secs, nps);
    }
}
