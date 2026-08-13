use magnus::prelude::*;

#[magnus::init]
fn init(_ruby: &magnus::Ruby) -> Result<(), magnus::Error> {
    let _bb = _ruby
        .define_module("PGN")?
        .define_module("Bitboard")?;
    Ok(())
}
