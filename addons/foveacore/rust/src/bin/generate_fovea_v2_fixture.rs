use std::env;
use std::fs;
use std::path::Path;

const MAGIC: [u8; 8] = *b"FOVEA_3D";
const VERSION: u32 = 2;
const HEADER_SIZE: usize = 72;
const COLOR_ENTRY_SIZE: usize = 12;
const COVARIANCE_ENTRY_SIZE: usize = 32;
const SPLAT_RECORD_SIZE: usize = 16;

fn push_u32(bytes: &mut Vec<u8>, value: u32) {
    bytes.extend_from_slice(&value.to_le_bytes());
}

fn push_f32(bytes: &mut Vec<u8>, value: f32) {
    bytes.extend_from_slice(&value.to_le_bytes());
}

fn build_fixture() -> Vec<u8> {
    let metadata = br#"{"fixture":"rust_v2","producer":"generate_fovea_v2_fixture","splat_count":1}"#;
    let metadata_offset = HEADER_SIZE + COLOR_ENTRY_SIZE + COVARIANCE_ENTRY_SIZE + SPLAT_RECORD_SIZE;

    let mut bytes = Vec::with_capacity(metadata_offset + metadata.len());
    bytes.extend_from_slice(&MAGIC);
    for value in [VERSION, 1, 1, 1] {
        push_u32(&mut bytes, value);
    }
    for value in [0.0_f32, 0.0, 0.0, 1.0, 1.0, 1.0] {
        push_f32(&mut bytes, value);
    }
    for value in [0, 0, 0, 0, metadata_offset as u32, metadata.len() as u32] {
        push_u32(&mut bytes, value);
    }
    assert_eq!(bytes.len(), HEADER_SIZE);

    for value in [0.2_f32, 0.6, 0.9] {
        push_f32(&mut bytes, value);
    }
    for value in [0.0_f32, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0] {
        push_f32(&mut bytes, value);
    }
    bytes.extend_from_slice(&32_768_u16.to_le_bytes());
    bytes.extend_from_slice(&32_768_u16.to_le_bytes());
    bytes.extend_from_slice(&32_768_u16.to_le_bytes());
    bytes.extend_from_slice(&[0, 0, 0, 0]);
    bytes.extend_from_slice(&0_u16.to_le_bytes());
    // opacity, layer, dither seed, brush type (GaussianSplat.BrushType.GAUSSIAN = 2)
    bytes.extend_from_slice(&[255, 0, 0, 2]);
    assert_eq!(bytes.len(), metadata_offset);

    bytes.extend_from_slice(metadata);
    bytes
}

fn main() {
    let output = env::args().nth(1).unwrap_or_else(|| {
        eprintln!("usage: cargo run --bin generate_fovea_v2_fixture -- <output.fovea>");
        std::process::exit(2);
    });
    let bytes = build_fixture();
    let path = Path::new(&output);
    if let Some(parent) = path.parent().filter(|parent| !parent.as_os_str().is_empty()) {
        fs::create_dir_all(parent).expect("create fixture directory");
    }
    fs::write(path, bytes).expect("write fixture");
    println!("Generated canonical Rust .fovea v2 fixture: {}", path.display());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fixture_has_canonical_layout_and_metadata() {
        let bytes = build_fixture();
        assert_eq!(&bytes[0..8], &MAGIC);
        assert_eq!(u32::from_le_bytes(bytes[8..12].try_into().unwrap()), VERSION);
        assert_eq!(u32::from_le_bytes(bytes[12..16].try_into().unwrap()), 1);
        let metadata_offset = u32::from_le_bytes(bytes[64..68].try_into().unwrap()) as usize;
        let metadata_size = u32::from_le_bytes(bytes[68..72].try_into().unwrap()) as usize;
        assert_eq!(metadata_offset, HEADER_SIZE + COLOR_ENTRY_SIZE + COVARIANCE_ENTRY_SIZE + SPLAT_RECORD_SIZE);
        assert_eq!(metadata_offset + metadata_size, bytes.len());
        assert_eq!(bytes[metadata_offset - 1], 2);
        assert_eq!(&bytes[metadata_offset..], br#"{"fixture":"rust_v2","producer":"generate_fovea_v2_fixture","splat_count":1}"#);
    }
}
