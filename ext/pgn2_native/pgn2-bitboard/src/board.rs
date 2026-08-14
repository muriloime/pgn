use crate::moves::{Move, Flag};
use crate::piece::{Color, PieceKind};
use crate::square::{Bitboard, Square};

#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct Board {
    /// pieces[color_index][piece_kind_index] = bitboard of that set.
    pub pieces: [[Bitboard; 6]; 2],
    /// Incremental occupancy (union of all pieces); O(1) `occupied()`.
    pub occ: Bitboard,
    /// Incremental per-color union bitboards; O(1) `white()`/`black()`.
    pub by_color: [Bitboard; 2],
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
    pub fn white(&self) -> Bitboard { self.by_color[Color::White as usize] }
    pub fn black(&self) -> Bitboard { self.by_color[Color::Black as usize] }
    pub fn occupied(&self) -> Bitboard { self.occ }

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
        let mut by_color = [Bitboard::empty(); 2];
        let mut occ = Bitboard::empty();
        for c in Color::all() {
            for k in PieceKind::ALL {
                let bb = pieces[ci(c)][ki(k)];
                by_color[ci(c)] |= bb;
                occ |= bb;
            }
        }

        let side_color = match side {
            "w" => Color::White,
            "b" => Color::Black,
            _ => return Err(format!("bad side: {side}")),
        };
        let mut cast = 0u8;
        for ch in castling.chars() {
            match ch {
                'K' => cast |= 0b0001,
                'Q' => cast |= 0b0010,
                'k' => cast |= 0b0100,
                'q' => cast |= 0b1000,
                '-' => {}
                _ => return Err(format!("bad castling char: {ch}")),
            }
        }
        let ep = if ep == "-" { None } else { parse_square(ep) };
        Ok(Board { pieces, occ, by_color, side: side_color, castling: cast, ep, halfmove, fullmove })
    }

    pub fn piece_at(&self, sq: Square) -> Option<(Color, PieceKind)> {
        let bb = Bitboard::single(sq);
        let c = if !(self.by_color[Color::White as usize] & bb).is_empty() {
            Color::White
        } else if !(self.by_color[Color::Black as usize] & bb).is_empty() {
            Color::Black
        } else {
            return None;
        };
        for k in PieceKind::ALL {
            if !(self.pieces[ci(c)][ki(k)] & bb).is_empty() {
                return Some((c, k));
            }
        }
        None
    }

    /// Place (c,k) on sq, updating pieces + incremental occ/by_color.
    fn add(&mut self, c: Color, k: PieceKind, sq: Square) {
        let b = Bitboard::single(sq);
        self.pieces[ci(c)][ki(k)] |= b;
        self.by_color[ci(c)] |= b;
        self.occ |= b;
    }
    /// Remove (c,k) from sq, updating pieces + incremental occ/by_color.
    fn sub(&mut self, c: Color, k: PieceKind, sq: Square) {
        let b = !Bitboard::single(sq);
        self.pieces[ci(c)][ki(k)] &= b;
        self.by_color[ci(c)] &= b;
        self.occ &= b;
    }

    fn rook_squares_for_castle(to: Square) -> (Square, Square) {
        // (rook_from, rook_to) for a king moving to `to`.
        let rank = to.rank();
        match to.file() {
            6 => (Square::from_algebraic(7, rank), Square::from_algebraic(5, rank)), // kingside
            _ => (Square::from_algebraic(0, rank), Square::from_algebraic(3, rank)), // queenside
        }
    }

    pub fn make(&mut self, m: Move) -> Undo {
        let (from, to) = (m.from(), m.to());
        let (color, kind) = self.piece_at(from).expect("make: no mover");
        let cap = self.piece_at(to);
        let undo = Undo {
            captured: cap,
            castling: self.castling,
            ep: self.ep,
            halfmove: self.halfmove,
        };

        self.sub(color, kind, from);
        if let Some((cap_c, cap_k)) = cap {
            self.sub(cap_c, cap_k, to);
        }

        let placed_kind = match m.flag() {
            Flag::Promotion => m.promo().expect("promo"),
            _ => kind,
        };
        self.add(color, placed_kind, to);

        match m.flag() {
            Flag::EnPassant => {
                let cap_sq = Square::from_algebraic(to.file(), from.rank());
                self.sub(color.opposite(), PieceKind::Pawn, cap_sq);
            }
            Flag::Castle => {
                let (rf, rt) = Self::rook_squares_for_castle(to);
                self.sub(color, PieceKind::Rook, rf);
                self.add(color, PieceKind::Rook, rt);
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
        self.halfmove = if kind == PieceKind::Pawn || cap.is_some() { 0 } else { self.halfmove + 1 };
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
        // The piece actually sitting on `to` is the promoted piece for a
        // promotion, else the mover itself.
        let at_to_kind = if m.is_promotion() { m.promo().expect("promo") } else { kind };
        self.sub(color, at_to_kind, to);
        self.add(color, kind, from);
        if let Some((cap_c, cap_k)) = undo.captured {
            self.add(cap_c, cap_k, to);
        }

        match m.flag() {
            Flag::EnPassant => {
                let cap_sq = Square::from_algebraic(to.file(), from.rank());
                self.add(color.opposite(), PieceKind::Pawn, cap_sq);
            }
            Flag::Castle => {
                let (rf, rt) = Self::rook_squares_for_castle(to);
                self.sub(color, PieceKind::Rook, rt);
                self.add(color, PieceKind::Rook, rf);
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
