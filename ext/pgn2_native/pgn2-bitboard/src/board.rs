use crate::moves::{Move, Flag};
use crate::piece::{Color, PieceKind};
use crate::square::{Bitboard, Square};

#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct Board {
    /// pieces[color_index][piece_kind_index] = bitboard of that set.
    pub pieces: [[Bitboard; 6]; 2],
    pub side: Color,
    /// KQkq bit order: bit0=whiteK, bit1=whiteQ, bit2=blackK, bit3=blackQ.
    pub castling: u8,
    pub ep: Option<Square>,
    pub halfmove: u16,
    pub fullmove: u16,
}

/// Records exactly what `make` mutated so `unmake` restores bit-for-bit.
pub struct Undo {
    pub captured: Option<(Color, PieceKind)>,
    pub castling: u8,
    pub ep: Option<Square>,
    pub halfmove: u16,
}

fn ci(c: Color) -> usize { c as usize }
fn ki(k: PieceKind) -> usize { k.index() }

impl Board {
    pub fn piece_bb(&self, c: Color, k: PieceKind) -> Bitboard { self.pieces[ci(c)][ki(k)] }
    pub fn white(&self) -> Bitboard {
        let mut b = Bitboard::empty();
        for k in PieceKind::ALL { b |= self.pieces[ci(Color::White)][ki(k)]; }
        b
    }
    pub fn black(&self) -> Bitboard {
        let mut b = Bitboard::empty();
        for k in PieceKind::ALL { b |= self.pieces[ci(Color::Black)][ki(k)]; }
        b
    }
    pub fn occupied(&self) -> Bitboard { self.white() | self.black() }

    pub fn from_fen(fen: &str) -> Result<Board, String> {
        let mut parts = fen.split_whitespace();
        let placement = parts.next().ok_or("missing placement")?;
        let side = parts.next().ok_or("missing side")?;
        let castling = parts.next().ok_or("missing castling")?;
        let ep = parts.next().ok_or("missing ep")?;
        let halfmove: u16 = parts.next().unwrap_or("0").parse().map_err(|e: std::num::ParseIntError| e.to_string())?;
        let fullmove: u16 = parts.next().unwrap_or("1").parse().map_err(|e: std::num::ParseIntError| e.to_string())?;

        let mut pieces = [[Bitboard::empty(); 6]; 2];
        let mut rank: i32 = 7;
        let mut file: i32 = 0;
        for ch in placement.chars() {
            match ch {
                '/' => { rank -= 1; file = 0; }
                d @ '1'..='8' => { file += (d as u8 - b'0') as i32; }
                c => {
                    let color = if c.is_ascii_uppercase() { Color::White } else { Color::Black };
                    let kind = match c.to_ascii_lowercase() {
                        'p' => PieceKind::Pawn,
                        'n' => PieceKind::Knight,
                        'b' => PieceKind::Bishop,
                        'r' => PieceKind::Rook,
                        'q' => PieceKind::Queen,
                        'k' => PieceKind::King,
                        _ => return Err(format!("bad piece char: {c}")),
                    };
                    let sq = Square::from_algebraic(file as u8, rank as u8);
                    pieces[ci(color)][ki(kind)] |= Bitboard::single(sq);
                    file += 1;
                }
            }
        }
        if rank != 0 || file != 8 { return Err("bad placement dimensions".into()); }

        let side_color = match side { "w" => Color::White, "b" => Color::Black, _ => return Err("bad side".to_string()) };
        let mut cast = 0u8;
        for c in castling.chars() {
            match c {
                'K' => cast |= 1, 'Q' => cast |= 2,
                'k' => cast |= 4, 'q' => cast |= 8,
                '-' => {}
                _ => return Err("bad castling".to_string()),
            }
        }
        let ep = match ep { "-" => None, s => Some(parse_square(s).ok_or("bad ep")?) };

        Ok(Board { pieces, side: side_color, castling: cast, ep, halfmove, fullmove })
    }

    pub fn piece_at(&self, sq: Square) -> Option<(Color, PieceKind)> {
        for c in Color::all() {
            for k in PieceKind::ALL {
                if !(self.piece_bb(c, k) & Bitboard::single(sq)).is_empty() {
                    return Some((c, k));
                }
            }
        }
        None
    }

    fn put(&mut self, c: Color, k: PieceKind, sq: Square) {
        self.pieces[c as usize][k.index()] |= Bitboard::single(sq);
    }
    fn clear(&mut self, sq: Square) {
        let mask = !Bitboard::single(sq);
        for c in Color::all() {
            for k in PieceKind::ALL {
                self.pieces[c as usize][k.index()] &= mask;
            }
        }
    }

    fn rook_squares_for_castle(to: Square) -> (Square, Square) {
        // (rook_from, rook_to) for a king moving to `to`.
        let f = to.file();
        let r = to.rank();
        match f {
            6 => (Square::from_algebraic(7, r), Square::from_algebraic(5, r)), // O-O: h-file rook -> f-file
            2 => (Square::from_algebraic(0, r), Square::from_algebraic(3, r)), // O-O-O: a-file rook -> d-file
            _ => unreachable!("castle to non-castle file"),
        }
    }

    pub fn make(&mut self, m: Move) -> Undo {
        let (from, to) = (m.from(), m.to());
        let (color, kind) = self.piece_at(from).expect("make: no mover");
        let undo = Undo {
            captured: self.piece_at(to),
            castling: self.castling,
            ep: self.ep,
            halfmove: self.halfmove,
        };
        self.clear(from);
        self.clear(to);
        self.put(color, kind, to);

        match m.flag() {
            Flag::EnPassant => {
                let cap_sq = Square::from_algebraic(to.file(), from.rank());
                self.clear(cap_sq);
            }
            Flag::Castle => {
                let (rf, rt) = Self::rook_squares_for_castle(to);
                self.clear(rf);
                self.put(color, PieceKind::Rook, rt);
            }
            Flag::Promotion => {
                self.clear(to);
                self.put(color, m.promo().expect("promo"), to);
            }
            _ => {}
        }

        self.ep = if m.is_double_pawn() {
            Some(Square::from_algebraic(from.file(), (from.rank() + to.rank()) / 2))
        } else {
            None
        };

        if kind == PieceKind::King {
            if color == Color::White { self.castling &= !0b0011; } else { self.castling &= !0b1100; }
        }
        for &sq in [from, to].iter() {
            match (sq.file(), sq.rank()) {
                (0, 0) => self.castling &= !0b0010, // a1 -> white Q-side
                (7, 0) => self.castling &= !0b0001, // h1 -> white K-side
                (0, 7) => self.castling &= !0b1000, // a8 -> black Q-side
                (7, 7) => self.castling &= !0b0100, // h8 -> black K-side
                _ => {}
            }
        }
        self.halfmove = if kind == PieceKind::Pawn || undo.captured.is_some() { 0 } else { self.halfmove + 1 };
        if color == Color::Black { self.fullmove += 1; }
        self.side = self.side.opposite();
        undo
    }

    pub fn unmake(&mut self, m: Move, undo: Undo) {
        let (from, to) = (m.from(), m.to());
        self.side = self.side.opposite();
        let color = self.side;

        let kind = if m.is_promotion() {
            PieceKind::Pawn
        } else {
            self.piece_at(to).map(|(_, k)| k).expect("unmake: no mover")
        };
        self.clear(to);
        self.put(color, kind, from);
        if let Some((cap_c, cap_k)) = undo.captured {
            self.put(cap_c, cap_k, to);
        }

        match m.flag() {
            Flag::EnPassant => {
                let cap_sq = Square::from_algebraic(to.file(), from.rank());
                self.put(color.opposite(), PieceKind::Pawn, cap_sq);
            }
            Flag::Castle => {
                let (rf, rt) = Self::rook_squares_for_castle(to);
                self.clear(rt);
                self.put(color, PieceKind::Rook, rf);
            }
            _ => {}
        }

        self.castling = undo.castling;
        self.ep = undo.ep;
        self.halfmove = undo.halfmove;
        if color == Color::Black {
            self.fullmove -= 1;
        }
    }
}

fn parse_square(s: &str) -> Option<Square> {
    let b = s.as_bytes();
    if b.len() != 2 { return None; }
    let file = b[0].checked_sub(b'a')?;
    let rank = b[1].checked_sub(b'1')?;
    if file > 7 || rank > 7 { return None; }
    Some(Square::from_algebraic(file, rank))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::piece::{Color, PieceKind};

    const STARTPOS: &str =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

    #[test]
    fn parse_startpos_piece_counts() {
        let b = Board::from_fen(STARTPOS).unwrap();
        assert_eq!(b.piece_bb(Color::White, PieceKind::Pawn).popcount(), 8);
        assert_eq!(b.piece_bb(Color::Black, PieceKind::Pawn).popcount(), 8);
        assert_eq!(b.piece_bb(Color::White, PieceKind::King).popcount(), 1);
        assert_eq!(b.piece_bb(Color::Black, PieceKind::King).popcount(), 1);
        assert_eq!(b.occupied().popcount(), 32);
        assert_eq!(b.side, Color::White);
        assert_eq!(b.castling, 0b1111);
        assert_eq!(b.ep, None);
    }

    #[test]
    fn parse_kiwipete_ep_and_castling() {
        let b = Board::from_fen(
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
        ).unwrap();
        assert_eq!(b.castling, 0b1111);
        assert_eq!(b.ep, None);
        // Kiwipete is a 32-piece position (full-ish middlegame).
        assert_eq!(b.occupied().popcount(), 32);
    }

    use crate::moves::{Move, Flag};

    #[test]
    fn make_unmake_restores_startpos() {
        crate::attacks::init();
        let mut b = Board::from_fen(STARTPOS).unwrap();
        let before = b.clone();
        let e2e4 = Move::new(Square::from_algebraic(4, 1), Square::from_algebraic(4, 3), Flag::DoublePawn);
        let undo = b.make(e2e4);
        assert_eq!(b.side, Color::Black);
        assert_eq!(b.ep, Some(Square::from_algebraic(4, 2)));
        b.unmake(e2e4, undo);
        assert_eq!(b, before);
    }

    #[test]
    fn make_unmake_capture_restores() {
        crate::attacks::init();
        let mut b = Board::from_fen("8/8/8/3p4/4P3/8/8/4K2k w - - 0 1").unwrap();
        let before = b.clone();
        let exd5 = Move::new(Square::from_algebraic(4, 3), Square::from_algebraic(3, 4), Flag::Normal);
        let undo = b.make(exd5);
        assert_eq!(b.piece_bb(Color::Black, PieceKind::Pawn).popcount(), 0);
        b.unmake(exd5, undo);
        assert_eq!(b, before);
    }

    #[test]
    fn make_unmake_white_castle_restores() {
        crate::attacks::init();
        let mut b = Board::from_fen("4k3/8/8/8/8/8/8/R3K3 w Q - 0 1").unwrap();
        let before = b.clone();
        let castle = Move::new(Square::from_algebraic(4, 0), Square::from_algebraic(2, 0), Flag::Castle);
        let undo = b.make(castle);
        let d1 = Square::from_algebraic(3, 0);
        assert_eq!(b.piece_bb(Color::White, PieceKind::Rook) & Bitboard::single(d1), Bitboard::single(d1));
        b.unmake(castle, undo);
        assert_eq!(b, before);
    }
}
