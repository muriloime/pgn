/// Adapter move carrying exactly what `to_uci` and `same_target` need:
/// from-square, to-square, and optional promotion kind. No flag bits,
/// so a position-free `uci_parse` can produce a comparable token — this
/// preserves the existing `same_target` semantics (match on
/// from + to + promo only), so `legal?("e1g1")` finds the castle and
/// `legal?("e7e8q")` finds that exact promotion.
#[derive(Clone, Copy, PartialEq, Eq)]
pub struct Move {
    from: u8, // 0..=63, index = rank * 8 + file
    to: u8,
    promo: Option<Promo>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Promo {
    Knight,
    Bishop,
    Rook,
    Queen,
}

impl Move {
    /// Build an adapter `Move` from a `chessie::Move` (a legal move).
    ///
    /// chessie encodes castling internally as "King takes Rook"
    /// (`to` = the rook's square, Chess960 style). `into_standard_castle`
    /// rewrites the `to` square to the king's destination (`e1g1`/`e1c1`),
    /// matching the standard-UCI output the previous engine produced and
    /// that `uci_parse` / `bitboard_spec.rb` expect. No-op for non-castle
    /// moves.
    pub(crate) fn from_chessie(m: chessie::Move) -> Self {
        let m = m.into_standard_castle();
        Move {
            from: m.from().index() as u8,
            to: m.to().index() as u8,
            promo: m.promotion().map(|kind| match kind {
                chessie::PieceKind::Knight => Promo::Knight,
                chessie::PieceKind::Bishop => Promo::Bishop,
                chessie::PieceKind::Rook => Promo::Rook,
                chessie::PieceKind::Queen => Promo::Queen,
                // Pawns/Kings never appear as a promotion kind.
                _ => unreachable!("non-promotion PieceKind in Move::promotion"),
            }),
        }
    }

    /// UCI string: `"e2e4"`, `"e1g1"` (castle, king from→to),
    /// `"e7e8q"` (promotion). Equal to `chessie::Move::to_uci` for
    /// every legal move (castle and en-passant both reduce to from+to
    /// in UCI), so the sorted-UCI output is unchanged.
    pub fn to_uci(self) -> String {
        let mut s = String::with_capacity(5);
        s.push_str(&sq_name(self.from));
        s.push_str(&sq_name(self.to));
        if let Some(p) = self.promo {
            s.push(match p {
                Promo::Knight => 'n',
                Promo::Bishop => 'b',
                Promo::Rook => 'r',
                Promo::Queen => 'q',
            });
        }
        s
    }

    /// Match on from + to + promo (the pre-existing semantics).
    pub fn same_target(self, other: Move) -> bool {
        self.from == other.from && self.to == other.to && self.promo == other.promo
    }
}

/// Thin wrapper around `Vec<Move>`; the binding calls `.iter()` on it.
pub struct MoveList(pub Vec<Move>);

impl MoveList {
    pub fn iter(&self) -> std::slice::Iter<'_, Move> {
        self.0.iter()
    }
}

/// Parse a UCI string into a `Move` token **without** a position.
/// Only `to_uci`/`same_target` consume the result, so from + to + promo
/// is all that is needed. Returns `None` on any malformed input.
pub fn uci_parse(s: &str) -> Option<Move> {
    let b = s.as_bytes();
    if b.len() < 4 {
        return None;
    }
    let from = parse_sq(&b[0..2])?;
    let to = parse_sq(&b[2..4])?;
    let promo = if b.len() >= 5 {
        Some(match b[4] {
            b'n' => Promo::Knight,
            b'b' => Promo::Bishop,
            b'r' => Promo::Rook,
            b'q' => Promo::Queen,
            _ => return None,
        })
    } else {
        None
    };
    Some(Move { from, to, promo })
}

fn parse_sq(t: &[u8]) -> Option<u8> {
    let f = t[0].checked_sub(b'a')?;
    let r = t[1].checked_sub(b'1')?;
    if f > 7 || r > 7 {
        return None;
    }
    Some(r * 8 + f)
}

fn sq_name(idx: u8) -> String {
    let file = (b'a' + (idx & 7)) as char;
    let rank = (b'1' + (idx >> 3)) as char;
    let mut s = String::with_capacity(2);
    s.push(file);
    s.push(rank);
    s
}
