use crate::piece::{Color, PieceKind};
use crate::square::{Bitboard, Square};

#[derive(Clone, Debug, PartialEq, Eq)]
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
}
