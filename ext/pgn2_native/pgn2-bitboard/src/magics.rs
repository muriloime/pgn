use crate::attacks;
use crate::square::{Bitboard, Square};

/// A slider attack table indexed by a perfect bit-extract of the relevant occupancy.
///
/// On x86-64 with BMI2 we use the hardware `pext` instruction, which gathers the bits of
/// `occ & mask` at the positions where `mask` is set into a dense index in `[0, 2^bits)`.
/// This is a perfect hash by construction: no magic number, no search, no collisions, and an
/// instant deterministic build. The classic "magic number" search is, for a 12-bit rook mask,
/// effectively non-converging with random candidates (thousands of different-class collisions
/// per trial), and verified precomputed magics are a transcription hazard. `pext` sidesteps
/// both problems.
///
/// On targets without BMI2 (e.g. aarch64) the fast table is not used; `rook_attacks`/
/// `bishop_attacks` fall back to the ray walker (`rook_attacks_ref`/`bishop_attacks_ref`),
/// which is correct though slower.
struct SliderTable {
    mask: Bitboard,
    attacks: Vec<Bitboard>,
}

static mut ROOK: Vec<SliderTable> = Vec::new();
static mut BISHOP: Vec<SliderTable> = Vec::new();
static mut BUILT: bool = false;
#[cfg(target_arch = "x86_64")]
static mut BMI2: bool = false;
static INIT: std::sync::Once = std::sync::Once::new();

#[cfg(target_arch = "x86_64")]
fn pext_index(mask_bits: u64, occ_bits: u64) -> usize {
    unsafe { core::arch::x86_64::_pext_u64(occ_bits, mask_bits) as usize }
}

/// Build the attack table for one square/kind by enumerating every subset of the mask
/// and recording the reference (ray-walker) attack set at its pext index.
#[cfg(target_arch = "x86_64")]
fn build_table(is_rook: bool) -> Vec<SliderTable> {
    use std::arch::is_x86_feature_detected;
    let mut out: Vec<SliderTable> = Vec::with_capacity(64);
    if !is_x86_feature_detected!("bmi2") {
        // No BMI2: leave tables empty; callers use the ray walker.
        for _ in 0..64 { out.push(SliderTable { mask: Bitboard::empty(), attacks: Vec::new() }); }
        return out;
    }
    for sq in 0..64u8 {
        let s = Square(sq);
        let mask = if is_rook { attacks::rook_mask(s) } else { attacks::bishop_mask(s) };
        let bits = mask.popcount();
        let n = 1usize << bits;
        let mut table = vec![Bitboard::empty(); n];
        let mut idx = 0u64;
        loop {
            let pi = pext_index(mask.0, idx);
            let atts = if is_rook { attacks::rook_attacks_ref(s, Bitboard(idx)) }
                       else { attacks::bishop_attacks_ref(s, Bitboard(idx)) };
            table[pi] = atts;
            let next = idx.wrapping_sub(mask.0) & mask.0;
            if next == 0 { break; }
            idx = next;
        }
        out.push(SliderTable { mask, attacks: table });
    }
    out
}

pub fn build_all() {
    INIT.call_once(|| unsafe { build_inner(); });
}

unsafe fn build_inner() {
    #[cfg(target_arch = "x86_64")]
    {
        if std::arch::is_x86_feature_detected!("bmi2") {
            let r = build_table(true);
            let b = build_table(false);
            ROOK = r;
            BISHOP = b;
            BMI2 = true; // set LAST, after tables are ready
        }
    }
    BUILT = true;
}

#[inline]
pub fn rook_attacks(sq: Square, occ: Bitboard) -> Bitboard {
    #[cfg(target_arch = "x86_64")]
    unsafe {
        if BMI2 {
            let t = &ROOK[sq.0 as usize];
            let idx = pext_index(t.mask.0, (occ & t.mask).0);
            return t.attacks[idx];
        }
    }
    attacks::rook_attacks_ref(sq, occ)
}

#[inline]
pub fn bishop_attacks(sq: Square, occ: Bitboard) -> Bitboard {
    #[cfg(target_arch = "x86_64")]
    unsafe {
        if BMI2 {
            let t = &BISHOP[sq.0 as usize];
            let idx = pext_index(t.mask.0, (occ & t.mask).0);
            return t.attacks[idx];
        }
    }
    attacks::bishop_attacks_ref(sq, occ)
}

#[cfg(test)]
mod tests {
    use crate::attacks;
    use crate::square::{Bitboard, Square};

    /// Enumerate subset #`seed` of `mask` (bits of seed select mask bits, low→high).
    fn subset(mask: Bitboard, mut seed: u64) -> Bitboard {
        let mut out = 0u64;
        let mut bits = mask.0;
        while bits != 0 {
            let lsb = bits & bits.wrapping_neg();
            if seed & 1 == 1 { out |= lsb; }
            seed >>= 1;
            bits ^= lsb;
        }
        Bitboard(out)
    }

    #[test]
    fn slider_rook_matches_reference() {
        attacks::init();
        for sq in 0..64u8 {
            let s = Square(sq);
            let mask = attacks::rook_mask(s);
            let bits = mask.popcount();
            let n = 1u64 << bits;
            for seed in 0..n {
                let occ = subset(mask, seed);
                assert_eq!(attacks::rook_attacks(s, occ), attacks::rook_attacks_ref(s, occ),
                    "rook mismatch sq={sq} seed={seed}");
            }
        }
    }

    #[test]
    fn slider_bishop_matches_reference() {
        attacks::init();
        for sq in 0..64u8 {
            let s = Square(sq);
            let mask = attacks::bishop_mask(s);
            let bits = mask.popcount();
            let n = 1u64 << bits;
            for seed in 0..n {
                let occ = subset(mask, seed);
                assert_eq!(attacks::bishop_attacks(s, occ), attacks::bishop_attacks_ref(s, occ),
                    "bishop mismatch sq={sq} seed={seed}");
            }
        }
    }
}
