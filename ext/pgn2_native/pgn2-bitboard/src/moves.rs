use crate::piece::PieceKind;
use crate::square::Square;

/// 16-bit move encoding: `to:6 | from:6 | special:4`.
///
/// `special` packs flag + promotion into one 4-bit field:
///   0 Normal, 1 DoublePawn, 2 EnPassant, 3 Castle,
///   4 PromoN, 5 PromoB, 6 PromoR, 7 PromoQ.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Flag { Normal, DoublePawn, EnPassant, Castle, Promotion }

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Move(pub u16);

impl Move {
    const TO: u16 = 0b111111;
    const FROM: u16 = 0b111111 << 6;
    const SPECIAL: u16 = 0b1111 << 12;

    const NORMAL: u16 = 0;
    const DOUBLE: u16 = 1;
    const EP: u16 = 2;
    const CASTLE: u16 = 3;
    // promo kinds encoded as 4 + (PieceKind.index() - 1): N=4 B=5 R=6 Q=7

    pub const fn new(from: Square, to: Square, flag: Flag) -> Move {
        let s: u16 = match flag {
            Flag::Normal => Self::NORMAL,
            Flag::DoublePawn => Self::DOUBLE,
            Flag::EnPassant => Self::EP,
            Flag::Castle => Self::CASTLE,
            Flag::Promotion => 4, // default queen-less; use `promotion` for a real promo
        };
        Move((to.0 as u16) | ((from.0 as u16) << 6) | (s << 12))
    }

    pub const fn promotion(from: Square, to: Square, kind: PieceKind) -> Move {
        let s: u16 = (kind as u16) + 3; // N=4 B=5 R=6 Q=7
        Move((to.0 as u16) | ((from.0 as u16) << 6) | (s << 12))
    }

    pub fn from(self) -> Square { Square(((self.0 & Self::FROM) >> 6) as u8) }
    pub fn to(self) -> Square { Square((self.0 & Self::TO) as u8) }
    pub fn special(self) -> u16 { (self.0 & Self::SPECIAL) >> 12 }

    pub fn flag(self) -> Flag {
        match self.special() {
            1 => Flag::DoublePawn,
            2 => Flag::EnPassant,
            3 => Flag::Castle,
            4..=7 => Flag::Promotion,
            _ => Flag::Normal,
        }
    }

    pub fn promo(self) -> Option<PieceKind> {
        let s = self.special();
        if s >= 4 { Some(PieceKind::ALL[(s - 3) as usize]) } else { None }
    }

    pub fn is_promotion(self) -> bool { self.special() >= 4 }
    pub fn is_double_pawn(self) -> bool { self.special() == Self::DOUBLE }
    pub fn is_en_passant(self) -> bool { self.special() == Self::EP }
    pub fn is_castle(self) -> bool { self.special() == Self::CASTLE }
}

/// A growable list of moves, kept separate from `Vec` so the binding layer can
/// iterate it without depending on Rust collection internals.
#[derive(Default)]
pub struct MoveList(pub Vec<Move>);
impl MoveList {
    pub fn new() -> Self { Self::default() }
    pub fn push(&mut self, m: Move) { self.0.push(m) }
    pub fn len(&self) -> usize { self.0.len() }
    pub fn iter(&self) -> std::slice::Iter<'_, Move> { self.0.iter() }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::piece::PieceKind;
    use crate::square::Square;

    #[test]
    fn normal_move_round_trips() {
        let m = Move::new(Square::new(12), Square::new(28), Flag::Normal);
        assert_eq!(m.from(), Square(12));
        assert_eq!(m.to(), Square(28));
        assert_eq!(m.flag(), Flag::Normal);
        assert_eq!(m.promo(), None);
        assert!(!m.is_promotion());
    }

    #[test]
    fn promotion_encodes_kind() {
        for (kind, want_special) in [
            (PieceKind::Knight, 4u16), (PieceKind::Bishop, 5),
            (PieceKind::Rook, 6), (PieceKind::Queen, 7),
        ] {
            let m = Move::promotion(Square::new(52), Square::new(60), kind);
            assert_eq!(m.from(), Square(52));
            assert_eq!(m.to(), Square(60));
            assert_eq!(m.promo(), Some(kind));
            assert_eq!(m.flag(), Flag::Promotion);
            assert!(m.is_promotion());
            assert_eq!(m.special(), want_special);
        }
    }

    #[test]
    fn castle_double_ep_flags_round_trip() {
        let c = Move::new(Square::new(4), Square::new(6), Flag::Castle);
        assert_eq!(c.flag(), Flag::Castle);
        assert!(c.is_castle());
        assert!(!c.is_en_passant());

        let d = Move::new(Square::new(8), Square::new(24), Flag::DoublePawn);
        assert_eq!(d.flag(), Flag::DoublePawn);
        assert!(d.is_double_pawn());

        let e = Move::new(Square::new(32), Square::new(41), Flag::EnPassant);
        assert_eq!(e.flag(), Flag::EnPassant);
        assert!(e.is_en_passant());
    }

    #[test]
    fn move_list_pushes() {
        let mut list = MoveList::new();
        assert_eq!(list.len(), 0);
        list.push(Move::new(Square::new(0), Square::new(1), Flag::Normal));
        list.push(Move::new(Square::new(2), Square::new(3), Flag::Normal));
        assert_eq!(list.len(), 2);
        assert_eq!(list.iter().count(), 2);
    }
}
