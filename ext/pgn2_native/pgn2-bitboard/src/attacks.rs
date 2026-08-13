use crate::square::{Bitboard, Square};

static mut KNIGHT: [Bitboard; 64] = [Bitboard::EMPTY; 64];
static mut KING: [Bitboard; 64] = [Bitboard::EMPTY; 64];
static mut WP: [Bitboard; 64] = [Bitboard::EMPTY; 64];
static mut BP: [Bitboard; 64] = [Bitboard::EMPTY; 64];
static mut INIT: bool = false;

fn valid(f: i32, r: i32) -> bool { (0..8).contains(&f) && (0..8).contains(&r) }
fn bb(f: i32, r: i32) -> Bitboard { Bitboard::single(Square::from_algebraic(f as u8, r as u8)) }

pub fn init() {
    unsafe {
        if INIT { return; }
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
        INIT = true;
    }
}

pub fn knight(s: Square) -> Bitboard { unsafe { KNIGHT[s.0 as usize] } }
pub fn king(s: Square) -> Bitboard { unsafe { KING[s.0 as usize] } }
pub fn wpawn_att(s: Square) -> Bitboard { unsafe { WP[s.0 as usize] } }
pub fn bpawn_att(s: Square) -> Bitboard { unsafe { BP[s.0 as usize] } }

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
}
