pub const FOVEA4D_MAGIC: &[u8; 8] = b"FOVEA_4D";
pub const FOVEA4D_VERSION: u32 = 1;
pub const FOVEA4D_HEADER_SIZE: usize = 128;

#[derive(Debug, Clone, PartialEq)]
pub struct Fovea4dHeader {
    pub flags: u32,
    pub base_sha256: [u8; 32],
    pub grid_dims: [u16; 3],
    pub keyframe_count: u16,
    pub sample_rate_hz: f32,
    pub bounds_min: [f32; 3],
    pub bounds_max: [f32; 3],
    pub displacement_scale: [f32; 3],
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Fovea4dError {
    Invalid(&'static str),
}

pub fn parse_fovea4d(bytes: &[u8]) -> Result<(Fovea4dHeader, &[u8]), Fovea4dError> {
    if bytes.len() < FOVEA4D_HEADER_SIZE {
        return Err(Fovea4dError::Invalid("file is shorter than header"));
    }
    if &bytes[0..8] != FOVEA4D_MAGIC {
        return Err(Fovea4dError::Invalid("invalid magic"));
    }
    if read_u32(bytes, 8) != FOVEA4D_VERSION {
        return Err(Fovea4dError::Invalid("unsupported version"));
    }
    if read_u32(bytes, 12) as usize != FOVEA4D_HEADER_SIZE {
        return Err(Fovea4dError::Invalid("invalid header size"));
    }
    let flags = read_u32(bytes, 16);
    if flags & !1 != 0 {
        return Err(Fovea4dError::Invalid("unknown flags"));
    }
    if read_u32(bytes, 20) != 1 {
        return Err(Fovea4dError::Invalid("unsupported codec"));
    }

    let mut base_sha256 = [0u8; 32];
    base_sha256.copy_from_slice(&bytes[24..56]);
    let grid_dims = [
        read_u16(bytes, 56),
        read_u16(bytes, 58),
        read_u16(bytes, 60),
    ];
    let keyframe_count = read_u16(bytes, 62);
    let payload_size = checked_payload_size(grid_dims, keyframe_count)
        .ok_or(Fovea4dError::Invalid("dimensions or keyframes are invalid"))?;
    let sample_rate_hz = read_f32(bytes, 64);
    if !sample_rate_hz.is_finite() || !(0.1..=240.0).contains(&sample_rate_hz) {
        return Err(Fovea4dError::Invalid("sample rate is invalid"));
    }
    let bounds_min = [
        read_f32(bytes, 68),
        read_f32(bytes, 72),
        read_f32(bytes, 76),
    ];
    let bounds_max = [
        read_f32(bytes, 80),
        read_f32(bytes, 84),
        read_f32(bytes, 88),
    ];
    if !valid_bounds(bounds_min, bounds_max) {
        return Err(Fovea4dError::Invalid("bounds are invalid"));
    }
    let displacement_scale = [
        read_f32(bytes, 92),
        read_f32(bytes, 96),
        read_f32(bytes, 100),
    ];
    if displacement_scale
        .iter()
        .any(|value| !value.is_finite() || *value <= 0.0)
    {
        return Err(Fovea4dError::Invalid("displacement scale is invalid"));
    }
    let payload_offset = read_u64(bytes, 104) as usize;
    let recorded_payload_size = read_u64(bytes, 112) as usize;
    if payload_offset != FOVEA4D_HEADER_SIZE || recorded_payload_size != payload_size {
        return Err(Fovea4dError::Invalid("payload layout is invalid"));
    }
    if bytes[120..128].iter().any(|value| *value != 0) {
        return Err(Fovea4dError::Invalid("reserved bytes must be zero"));
    }
    let total_size = payload_offset
        .checked_add(payload_size)
        .ok_or(Fovea4dError::Invalid("payload size overflows"))?;
    if bytes.len() != total_size {
        return Err(Fovea4dError::Invalid("file size does not match payload"));
    }

    Ok((
        Fovea4dHeader {
            flags,
            base_sha256,
            grid_dims,
            keyframe_count,
            sample_rate_hz,
            bounds_min,
            bounds_max,
            displacement_scale,
        },
        &bytes[payload_offset..total_size],
    ))
}

fn checked_payload_size(grid_dims: [u16; 3], keyframes: u16) -> Option<usize> {
    if grid_dims.iter().any(|value| !(2..=32).contains(value)) {
        return None;
    }
    if !(2..=256).contains(&keyframes) {
        return None;
    }
    let cells = usize::from(grid_dims[0])
        .checked_mul(usize::from(grid_dims[1]))?
        .checked_mul(usize::from(grid_dims[2]))?;
    let size = cells.checked_mul(usize::from(keyframes))?.checked_mul(6)?;
    (size <= 256 * 1024 * 1024).then_some(size)
}

fn valid_bounds(minimum: [f32; 3], maximum: [f32; 3]) -> bool {
    minimum
        .iter()
        .zip(maximum.iter())
        .all(|(min, max)| min.is_finite() && max.is_finite() && min <= max)
}

fn read_u16(bytes: &[u8], offset: usize) -> u16 {
    u16::from_le_bytes(
        bytes[offset..offset + 2]
            .try_into()
            .expect("bounded header read"),
    )
}

fn read_u32(bytes: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes(
        bytes[offset..offset + 4]
            .try_into()
            .expect("bounded header read"),
    )
}

fn read_u64(bytes: &[u8], offset: usize) -> u64 {
    u64::from_le_bytes(
        bytes[offset..offset + 8]
            .try_into()
            .expect("bounded header read"),
    )
}

fn read_f32(bytes: &[u8], offset: usize) -> f32 {
    f32::from_le_bytes(
        bytes[offset..offset + 4]
            .try_into()
            .expect("bounded header read"),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    const GDSCRIPT_FIXTURE: &[u8] =
        include_bytes!("../../../../test/fixtures/gdscript_fovea4d_v1_fixture.fovea4d");

    #[test]
    fn gdscript_fixture_is_accepted() {
        let (header, payload) =
            parse_fovea4d(GDSCRIPT_FIXTURE).expect("GDScript fixture validates");
        assert_eq!(header.grid_dims, [2, 2, 2]);
        assert_eq!(header.keyframe_count, 2);
        assert_eq!(payload.len(), 96);
    }

    #[test]
    fn structural_corruption_is_rejected() {
        for (offset, value) in [(0usize, b'X'), (120usize, 1u8)] {
            let mut corrupt = GDSCRIPT_FIXTURE.to_vec();
            corrupt[offset] = value;
            assert!(parse_fovea4d(&corrupt).is_err());
        }
        let mut trailing = GDSCRIPT_FIXTURE.to_vec();
        trailing.push(0);
        assert!(parse_fovea4d(&trailing).is_err());
        assert!(parse_fovea4d(&GDSCRIPT_FIXTURE[..GDSCRIPT_FIXTURE.len() - 1]).is_err());
    }

    #[test]
    fn every_bounded_header_field_fails_closed() {
        let mutations: Vec<(usize, Vec<u8>)> = vec![
            (8, 2u32.to_le_bytes().to_vec()),
            (12, 64u32.to_le_bytes().to_vec()),
            (16, 2u32.to_le_bytes().to_vec()),
            (20, 2u32.to_le_bytes().to_vec()),
            (56, 1u16.to_le_bytes().to_vec()),
            (58, 33u16.to_le_bytes().to_vec()),
            (62, 1u16.to_le_bytes().to_vec()),
            (64, f32::NAN.to_le_bytes().to_vec()),
            (68, 2.0f32.to_le_bytes().to_vec()),
            (92, 0.0f32.to_le_bytes().to_vec()),
            (104, 129u64.to_le_bytes().to_vec()),
            (112, 95u64.to_le_bytes().to_vec()),
        ];
        for (offset, replacement) in mutations {
            let mut corrupt = GDSCRIPT_FIXTURE.to_vec();
            corrupt[offset..offset + replacement.len()].copy_from_slice(&replacement);
            assert!(
                parse_fovea4d(&corrupt).is_err(),
                "offset {offset} was accepted"
            );
        }
    }
}
