// chessie smoke test — correctness (published perft) + legal-move API + nps bench.
use chessie::{perft, Game, MoveGenIter, Move};
use std::time::Instant;

fn is_legal(g: &Game, uci: &str) -> bool {
    let mv = match Move::from_uci(g, uci) { Ok(m) => m, Err(_) => return false };
    MoveGenIter::new(g).any(|m| m == mv)
}

struct Case {
    name: &'static str,
    fen: &'static str,
    // (depth, expected_nodes)
    checks: &'static [(usize, u64)],
}

const CASES: &[Case] = &[
    Case { name: "startpos",
        fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        checks: &[(1,20),(2,400),(3,8902),(4,197281),(5,4865609)] },
    Case { name: "kiwipete",
        fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
        checks: &[(1,48),(2,2039),(3,97862),(4,4085603)] },
    Case { name: "pos3",
        fen: "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
        checks: &[(1,14),(2,191),(3,2812),(4,43238),(5,674624)] },
    Case { name: "pos4",
        fen: "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
        checks: &[(1,6),(2,264),(3,9467),(4,422333)] },
    Case { name: "pos5",
        fen: "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
        checks: &[(1,44),(2,1486),(3,62379),(4,2103487)] },
    Case { name: "pos6",
        fen: "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
        checks: &[(1,46),(2,2079),(3,89890),(4,3894594)] },
];

fn main() {
    let mut failures = 0usize;

    println!("== correctness (published perft) ==");
    for c in CASES {
        let g = match Game::from_fen(c.fen) {
            Ok(g) => g,
            Err(e) => { println!("  [FAIL] {} FEN parse: {}", c.name, e); failures += 1; continue; }
        };
        for (depth, want) in c.checks {
            let got = perft(&g, *depth);
            let ok = got == *want;
            if !ok { failures += 1; }
            println!("  [{}] {} d{} = {} (want {}) {}",
                if ok { "ok " } else { "FAIL" }, c.name, depth, got, want,
                if ok { "" } else { "  <<< MISMATCH" });
        }
    }

    println!("\n== legal-move API ==");
    let g = Game::from_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1").unwrap();
    let mut mvs: Vec<String> = MoveGenIter::new(&g).map(|m| m.to_uci()).collect();
    mvs.sort();
    let ok = mvs.len() == 20;
    if !ok { failures += 1; }
    println!("  startpos legal_moves count = {} (want 20) {}", mvs.len(), if ok {""} else {"<<< MISMATCH"});
    // spot-check a couple UCI strings are present and sorted
    let has_e2e4 = mvs.binary_search(&"e2e4".to_string()).is_ok();
    let has_g1f3 = mvs.binary_search(&"g1f3".to_string()).is_ok();
    println!("  sorted & contains e2e4={} g1f3={}", has_e2e4, has_g1f3);
    if !has_e2e4 || !has_g1f3 { failures += 1; }

    // is_legal is not exposed by chessie 2.0.0 (commented out in source).
    // Equivalent: the move is legal iff it appears in the legal-move set.
    let legal = is_legal(&g, "e2e4");
    let illegal = is_legal(&g, "e2e5");
    println!("  is_legal(e2e4)={} (want true); is_legal(e2e5)={} (want false)", legal, illegal);
    if !legal || illegal { failures += 1; }

    println!("\n== nps bench (bulk-counting perft, copy-make) ==");
    for (name, fen, depth) in [
        ("startpos d6", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 6usize),
        ("kiwipete d5", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", 5),
        ("pos3   d6", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 6),
    ] {
        let g = Game::from_fen(fen).unwrap();
        let t = Instant::now();
        let n = perft(&g, depth);
        let secs = t.elapsed().as_secs_f64();
        let nps = (n as f64 / secs) as u64;
        println!("  {:<14} nodes={:>12}  {:>8.3}s  {:>9} nps", name, n, secs, nps);
    }

    println!("\n== result ==");
    if failures == 0 {
        println!("  ALL CHECKS PASSED");
        std::process::exit(0);
    } else {
        println!("  {} FAILURE(S)", failures);
        std::process::exit(1);
    }
}
