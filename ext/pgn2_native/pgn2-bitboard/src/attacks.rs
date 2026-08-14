use crate::square::{Bitboard, Square};
use std::sync::Once;

static mut KNIGHT: [Bitboard; 64] = [Bitboard::EMPTY; 64];
static mut KING: [Bitboard; 64] = [Bitboard::EMPTY; 64];
static mut WP: [Bitboard; 64] = [Bitboard::EMPTY; 64];
static mut BP: [Bitboard; 64] = [Bitboard::EMPTY; 64];
static INIT: Once = Once::new();

fn valid(f: i32, r: i32) -> bool { (0..8).contains(&f) && (0..8).contains(&r) }
fn bb(f: i32, r: i32) -> Bitboard { Bitboard::single(Square::from_algebraic(f as u8, r as u8)) }

pub fn init() {
    INIT.call_once(|| unsafe {
        for sq in 0..64u8 {
            let s = Square(sq);
            let f = s.file() as i32; let r = s.rank() as i32;
            let mut kn = Bitboard::empty();
            for (df, dr) in [(1,2),(2,1),(2,-1),(1,-2),(-1,-2),(-2,-1),(-2,1),(-1,2)] {
                let nf = f+df; let nr = r+dr;
                if valid(nf, nr) { kn |= bb(nf, nr); }
            }
            KNIGHT[sq as usize] = kn;
            let mut kg = Bitboard::empty();
            for df in -1..=1 { for dr in -1..=1 {
                if df == 0 && dr == 0 { continue; }
                let nf = f+df; let nr = r+dr;
                if valid(nf, nr) { kg |= bb(nf, nr); }
            }}
            KING[sq as usize] = kg;
            let mut wp = Bitboard::empty();
            if valid(f-1, r+1) { wp |= bb(f-1, r+1); }
            if valid(f+1, r+1) { wp |= bb(f+1, r+1); }
            WP[sq as usize] = wp;
            let mut bp = Bitboard::empty();
            if valid(f-1, r-1) { bp |= bb(f-1, r-1); }
            if valid(f+1, r-1) { bp |= bb(f+1, r-1); }
            BP[sq as usize] = bp;
        }
        crate::magics::build_all();
    });
}

pub fn knight(s: Square) -> Bitboard { unsafe { KNIGHT[s.0 as usize] } }
pub fn king(s: Square) -> Bitboard { unsafe { KING[s.0 as usize] } }
pub fn wpawn_att(s: Square) -> Bitboard { unsafe { WP[s.0 as usize] } }
pub fn bpawn_att(s: Square) -> Bitboard { unsafe { BP[s.0 as usize] } }

const ROOK_DIRS: [(i32, i32); 4] = [(1, 0), (-1, 0), (0, 1), (0, -1)];
const BISHOP_DIRS: [(i32, i32); 4] = [(1, 1), (1, -1), (-1, 1), (-1, -1)];

pub fn rook_mask(sq: Square) -> Bitboard {
    let f = sq.file() as i32; let r = sq.rank() as i32;
    let mut out = Bitboard::empty();
    for &(df, dr) in &ROOK_DIRS {
        if df != 0 {
            // horizontal ray: edge only in the file dimension
            let mut nf = f + df;
            while nf >= 1 && nf <= 6 { out |= bb(nf, r); nf += df; }
        } else {
            // vertical ray: edge only in the rank dimension
            let mut nr = r + dr;
            while nr >= 1 && nr <= 6 { out |= bb(f, nr); nr += dr; }
        }
    }
    out
}

pub fn bishop_mask(sq: Square) -> Bitboard {
    let f = sq.file() as i32; let r = sq.rank() as i32;
    let mut out = Bitboard::empty();
    for &(df, dr) in &BISHOP_DIRS {
        let mut nf = f + df; let mut nr = r + dr;
        // diagonal: exclude edges in both dimensions
        while nf >= 1 && nf <= 6 && nr >= 1 && nr <= 6 { out |= bb(nf, nr); nf += df; nr += dr; }
    }
    out
}

fn ray_attacks(sq: Square, occ: Bitboard, dirs: &[(i32, i32)]) -> Bitboard {
    let f = sq.file() as i32; let r = sq.rank() as i32;
    let mut out = Bitboard::empty();
    for (df, dr) in dirs {
        let mut nf = f + df; let mut nr = r + dr;
        while valid(nf, nr) {
            let t = bb(nf, nr);
            out |= t;
            if !(occ & t).is_empty() { break; }
            nf += df; nr += dr;
        }
    }
    out
}

pub fn rook_attacks_ref(sq: Square, occ: Bitboard) -> Bitboard { ray_attacks(sq, occ, &ROOK_DIRS) }
pub fn bishop_attacks_ref(sq: Square, occ: Bitboard) -> Bitboard { ray_attacks(sq, occ, &BISHOP_DIRS) }
pub fn rook_attacks(sq: Square, occ: Bitboard) -> Bitboard { crate::magics::rook_attacks(sq, occ) }
pub fn bishop_attacks(sq: Square, occ: Bitboard) -> Bitboard { crate::magics::bishop_attacks(sq, occ) }

#[cfg(test)]
mod tests {
    use super::*;
    use crate::square::Square;

    #[test]
    fn knight_center_has_8_attacks() {
        init();
        let e4 = Square::from_algebraic(4, 3);
        assert_eq!(knight(e4).popcount(), 8);
    }

    #[test]
    fn knight_corner_has_2_attacks() {
        init();
        assert_eq!(knight(Square::new(0)).popcount(), 2);
    }

    #[test]
    fn king_center_8_corner_3() {
        init();
        assert_eq!(king(Square::from_algebraic(4, 3)).popcount(), 8);
        assert_eq!(king(Square::new(0)).popcount(), 3);
    }

    #[test]
    fn white_pawn_attacks_ne_and_nw() {
        init();
        let e2 = Square::from_algebraic(4, 1);
        let a = wpawn_att(e2);
        assert_eq!(a.popcount(), 2);
    }

    #[test]
    fn black_pawn_attacks_south() {
        init();
        let d7 = Square::from_algebraic(3, 6);
        assert_eq!(bpawn_att(d7).popcount(), 2);
    }

    #[test]
    fn rook_mask_d4_inner_is_10_bits() {
        init();
        let d4 = Square::from_algebraic(3, 3);
        // inner square: rank b4..g4 (minus origin d4) = 5, file d2..d7 (minus d4) = 5.
        assert_eq!(rook_mask(d4).popcount(), 10);
    }

    #[test]
    fn rook_mask_corner_is_12_bits() {
        init();
        assert_eq!(rook_mask(Square::new(0)).popcount(), 12);
    }

    #[test]
    fn rook_attacks_clear_board_full_rank_file() {
        init();
        let d4 = Square::from_algebraic(3, 3);
        let a = rook_attacks(d4, Bitboard::empty());
        assert_eq!(a.popcount(), 14); // rank(7) + file(8) - self(1) = 14
    }

    #[test]
    fn rook_attacks_blocked_by_first_piece() {
        init();
        let d4 = Square::from_algebraic(3, 3);
        let blocker = Bitboard::single(Square::from_algebraic(3, 6)); // d7, north
        let a = rook_attacks(d4, blocker);
        assert!((a & Bitboard::single(Square::from_algebraic(3, 7))).is_empty()); // d8 not attacked
        assert_eq!((a & Bitboard::single(Square::from_algebraic(3, 6))).popcount(), 1); // d7 captured
    }

    #[test]
    fn bishop_attacks_clear_board_diagonals() {
        init();
        let d4 = Square::from_algebraic(3, 3);
        assert_eq!(bishop_attacks(d4, Bitboard::empty()).popcount(), 13);
    }
}
