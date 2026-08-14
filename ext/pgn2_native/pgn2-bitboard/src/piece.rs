#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum Color { #[default] White, Black }
impl Color {
    pub const fn opposite(self) -> Self {
        match self { Color::White => Color::Black, Color::Black => Color::White }
    }
    pub const fn all() -> [Color; 2] { [Color::White, Color::Black] }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PieceKind { Pawn, Knight, Bishop, Rook, Queen, King }
impl PieceKind {
    pub const ALL: [PieceKind; 6] = [
        PieceKind::Pawn, PieceKind::Knight, PieceKind::Bishop,
        PieceKind::Rook, PieceKind::Queen, PieceKind::King,
    ];
    pub fn index(self) -> usize {
        self as usize
    }
}
