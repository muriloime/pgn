/// A board square, 0..=63. Index = rank * 8 + file. Rank 0 is rank 1.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Square(pub u8);

impl Square {
    pub const fn new(idx: u8) -> Self { Square(idx) }

    pub const fn from_algebraic(file: u8, rank: u8) -> Self {
        Square(rank * 8 + file)
    }

    pub const fn file(self) -> u8 { self.0 & 7 }
    pub const fn rank(self) -> u8 { self.0 >> 3 }
}

/// A 64-bit bitboard.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub struct Bitboard(pub u64);

impl Bitboard {
    pub const EMPTY: Bitboard = Bitboard(0);

    pub const fn empty() -> Self { Bitboard::EMPTY }
    pub const fn single(sq: Square) -> Self { Bitboard(1u64 << sq.0) }

    pub const fn is_empty(self) -> bool { self.0 == 0 }
    pub fn popcount(self) -> u32 { self.0.count_ones() }

    pub fn iter(self) -> BitboardIter {
        BitboardIter(self.0)
    }
}

impl std::ops::BitAnd for Bitboard {
    type Output = Bitboard;
    fn bitand(self, rhs: Bitboard) -> Bitboard { Bitboard(self.0 & rhs.0) }
}
impl std::ops::BitOr for Bitboard {
    type Output = Bitboard;
    fn bitor(self, rhs: Bitboard) -> Bitboard { Bitboard(self.0 | rhs.0) }
}
impl std::ops::Not for Bitboard {
    type Output = Bitboard;
    fn not(self) -> Bitboard { Bitboard(!self.0) }
}
impl std::ops::BitAndAssign for Bitboard {
    fn bitand_assign(&mut self, rhs: Bitboard) { self.0 &= rhs.0; }
}
impl std::ops::BitOrAssign for Bitboard {
    fn bitor_assign(&mut self, rhs: Bitboard) { self.0 |= rhs.0; }
}

pub struct BitboardIter(u64);
impl Iterator for BitboardIter {
    type Item = Square;
    fn next(&mut self) -> Option<Square> {
        if self.0 == 0 { return None; }
        let idx = self.0.trailing_zeros() as u8;
        self.0 &= self.0.wrapping_sub(1);
        Some(Square(idx))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn single_bitboard_has_one_bit() {
        let bb = Bitboard::single(Square::new(4)); // e1
        assert_eq!(bb.0, 1 << 4);
        assert_eq!(bb.popcount(), 1);
    }

    #[test]
    fn empty_is_zero() {
        assert!(Bitboard::empty().is_empty());
        assert_eq!(Bitboard::empty().popcount(), 0);
    }

    #[test]
    fn iter_visits_set_bits_in_order() {
        let bb = Bitboard::single(Square::new(0)) | Bitboard::single(Square::new(63));
        let bits: Vec<u8> = bb.iter().map(|s| s.0).collect();
        assert_eq!(bits, vec![0, 63]);
    }

    #[test]
    fn algebraic_round_trips() {
        let e4 = Square::from_algebraic(4, 3); // file e=4, rank 4 -> rank index 3
        assert_eq!(e4.0, 4 + 3 * 8);
        assert_eq!((e4.file(), e4.rank()), (4, 3));
    }
}
