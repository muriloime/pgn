use crate::piece::PieceKind;
use crate::square::Square;
use crate::attacks;
use crate::board::Board;
use crate::piece::Color;

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

    use crate::board::Board;

    #[test]
    fn startpos_has_20_pseudo_moves() {
        crate::attacks::init();
        let b = Board::from_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1").unwrap();
        assert_eq!(b.gen_pseudo().len(), 20);
    }

    #[test]
    fn kiwipete_has_48_pseudo_moves() {
        crate::attacks::init();
        let b = Board::from_fen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1").unwrap();
        assert_eq!(b.gen_pseudo().len(), 48);
    }
}

impl Board {
    pub fn gen_pseudo(&self) -> MoveList {
        attacks::init();
        let mut list = MoveList::new();
        let us = self.side;
        let occ = self.occupied();
        let own = if us == Color::White { self.white() } else { self.black() };
        let enemy = if us == Color::White { self.black() } else { self.white() };

        for from in self.piece_bb(us, PieceKind::Pawn).iter() {
            gen_pawn(self, us, from, occ, enemy, &mut list);
        }
        for from in self.piece_bb(us, PieceKind::Knight).iter() {
            for to in (attacks::knight(from) & !own).iter() {
                list.push(Move::new(from, to, Flag::Normal));
            }
        }
        for from in self.piece_bb(us, PieceKind::Bishop).iter() {
            for to in (attacks::bishop_attacks(from, occ) & !own).iter() {
                list.push(Move::new(from, to, Flag::Normal));
            }
        }
        for from in self.piece_bb(us, PieceKind::Rook).iter() {
            for to in (attacks::rook_attacks(from, occ) & !own).iter() {
                list.push(Move::new(from, to, Flag::Normal));
            }
        }
        for from in self.piece_bb(us, PieceKind::Queen).iter() {
            let att = (attacks::rook_attacks(from, occ) | attacks::bishop_attacks(from, occ)) & !own;
            for to in att.iter() {
                list.push(Move::new(from, to, Flag::Normal));
            }
        }
        for from in self.piece_bb(us, PieceKind::King).iter() {
            for to in (attacks::king(from) & !own).iter() {
                list.push(Move::new(from, to, Flag::Normal));
            }
            gen_castle(self, us, from, occ, &mut list);
        }
        list
    }
}

fn gen_pawn(b: &Board, us: Color, from: Square, occ: crate::square::Bitboard, enemy: crate::square::Bitboard, list: &mut MoveList) {
    use crate::square::{Bitboard, Square};
    let (push, start_rank, promo_rank) = match us {
        Color::White => (1i32, 1u8, 7u8),
        Color::Black => (-1i32, 6u8, 0u8),
    };
    let f = from.file() as i32;
    let r = from.rank() as i32;

    // single + double push
    let one = Square::from_algebraic(f as u8, (r + push) as u8);
    if (occ & Bitboard::single(one)).is_empty() {
        if one.rank() == promo_rank {
            push_promos(list, from, one);
        } else {
            list.push(Move::new(from, one, Flag::Normal));
            if from.rank() == start_rank {
                let two = Square::from_algebraic(f as u8, (r + 2 * push) as u8);
                if (occ & Bitboard::single(two)).is_empty() {
                    list.push(Move::new(from, two, Flag::DoublePawn));
                }
            }
        }
    }

    // captures
    let att = if us == Color::White { attacks::wpawn_att(from) } else { attacks::bpawn_att(from) };
    for to in (att & enemy).iter() {
        if to.rank() == promo_rank { push_promos(list, from, to); }
        else { list.push(Move::new(from, to, Flag::Normal)); }
    }

    // en passant
    if let Some(ep) = b.ep {
        if !(att & Bitboard::single(ep)).is_empty() {
            list.push(Move::new(from, ep, Flag::EnPassant));
        }
    }
}

fn push_promos(list: &mut MoveList, from: Square, to: Square) {
    for k in [PieceKind::Knight, PieceKind::Bishop, PieceKind::Rook, PieceKind::Queen] {
        list.push(Move::promotion(from, to, k));
    }
}

fn gen_castle(b: &Board, us: Color, from: Square, occ: crate::square::Bitboard, list: &mut MoveList) {
    use crate::square::{Bitboard, Square};
    let rank = if us == Color::White { 0u8 } else { 7u8 };
    let ksq = Square::from_algebraic(4, rank);
    if from != ksq { return; }
    let (can_k, can_q) = match us {
        Color::White => (b.castling & 1 != 0, b.castling & 2 != 0),
        Color::Black => (b.castling & 4 != 0, b.castling & 8 != 0),
    };
    if can_k {
        let between = Bitboard::single(Square::from_algebraic(5, rank))
            | Bitboard::single(Square::from_algebraic(6, rank));
        if (occ & between).is_empty() {
            list.push(Move::new(ksq, Square::from_algebraic(6, rank), Flag::Castle));
        }
    }
    if can_q {
        let between = Bitboard::single(Square::from_algebraic(3, rank))
            | Bitboard::single(Square::from_algebraic(2, rank))
            | Bitboard::single(Square::from_algebraic(1, rank));
        if (occ & between).is_empty() {
            list.push(Move::new(ksq, Square::from_algebraic(2, rank), Flag::Castle));
        }
    }
}

// ---- UCI encoding / decoding ----

impl Move {
    /// UCI string, e.g. "e2e4", "e1g1", "e7e8q".
    pub fn to_uci(self) -> String {
        let mut s = format!("{}{}", sq_name(self.from()), sq_name(self.to()));
        if let Some(k) = self.promo() {
            s.push(match k {
                PieceKind::Knight => 'n',
                PieceKind::Bishop => 'b',
                PieceKind::Rook => 'r',
                PieceKind::Queen => 'q',
                _ => 'q',
            });
        }
        s
    }

    /// Compare two moves by from/to/promo, ignoring the special flag. This
    /// lets `#legal?` match a user UCI ("e1g1") against a generated castling
    /// move, since a bare UCI string cannot encode the castle/ep/double flag.
    pub fn same_target(self, other: Move) -> bool {
        self.from() == other.from() && self.to() == other.to() && self.promo() == other.promo()
    }
}

fn sq_name(s: Square) -> String {
    let f = (b'a' + s.file()) as char;
    let r = (b'1' + s.rank()) as char;
    format!("{f}{r}")
}

/// Parse a UCI move string into a `Move` (promotions carry the piece letter).
/// The resulting flag is Normal/Promotion only — castle/ep/double flags are
/// not recoverable from a bare UCI string; compare with `same_target`.
pub fn uci_parse(s: &str) -> Option<Move> {
    let b = s.as_bytes();
    if b.len() < 4 { return None; }
    let from = parse_sq(&b[0..2])?;
    let to = parse_sq(&b[2..4])?;
    if let Some(&c) = b.get(4) {
        let kind = match c {
            b'n' => PieceKind::Knight,
            b'b' => PieceKind::Bishop,
            b'r' => PieceKind::Rook,
            b'q' => PieceKind::Queen,
            _ => return None,
        };
        return Some(Move::promotion(from, to, kind));
    }
    Some(Move::new(from, to, Flag::Normal))
}

fn parse_sq(n: &[u8]) -> Option<Square> {
    if n.len() != 2 { return None; }
    let f = n[0].checked_sub(b'a')?;
    let r = n[1].checked_sub(b'1')?;
    if f > 7 || r > 7 { return None; }
    Some(Square::from_algebraic(f, r))
}
