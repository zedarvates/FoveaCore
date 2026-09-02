use std::{env, fs, path::Path};

#[path = "../fovea_4d_format.rs"]
mod fovea_4d_format;

use fovea_4d_format::{parse_fovea4d, FOVEA4D_HEADER_SIZE, FOVEA4D_MAGIC};

const BASE_SHA256: [u8; 32] = [
    0xf3, 0x4c, 0x11, 0x60, 0x64, 0x85, 0x2a, 0xfe, 0x65, 0x09, 0xce, 0xb1, 0x65, 0x3e, 0xa1, 0x0e,
    0x8d, 0x9a, 0xcf, 0x20, 0x64, 0x7a, 0xa2, 0x43, 0xf1, 0x50, 0xa6, 0x0b, 0x52, 0xca, 0x9b, 0x6d,
];

fn build_fixture() -> Vec<u8> {
    let mut bytes = vec![0u8; FOVEA4D_HEADER_SIZE + 96];
    bytes[0..8].copy_from_slice(FOVEA4D_MAGIC);
    write_u32(&mut bytes, 8, 1);
    write_u32(&mut bytes, 12, FOVEA4D_HEADER_SIZE as u32);
    write_u32(&mut bytes, 16, 1);
    write_u32(&mut bytes, 20, 1);
    bytes[24..56].copy_from_slice(&BASE_SHA256);
    write_u16(&mut bytes, 56, 2);
    write_u16(&mut bytes, 58, 2);
    write_u16(&mut bytes, 60, 2);
    write_u16(&mut bytes, 62, 2);
    write_f32(&mut bytes, 64, 4.0);
    write_f32(&mut bytes, 80, 1.0);
    write_f32(&mut bytes, 84, 1.0);
    write_f32(&mut bytes, 88, 1.0);
    let scales = [
        (0.03f64 / 32767.0) as f32,
        (0.04f64 / 32767.0) as f32,
        (0.05f64 / 32767.0) as f32,
    ];
    write_f32(&mut bytes, 92, scales[0]);
    write_f32(&mut bytes, 96, scales[1]);
    write_f32(&mut bytes, 100, scales[2]);
    write_u64(&mut bytes, 104, FOVEA4D_HEADER_SIZE as u64);
    write_u64(&mut bytes, 112, 96);

    let mut cursor = FOVEA4D_HEADER_SIZE;
    for keyframe in 0..2 {
        for z in 0..2 {
            for y in 0..2 {
                for x in 0..2 {
                    let values = [
                        x as f32 * 0.01 + keyframe as f32 * 0.02,
                        y as f32 * 0.01 + keyframe as f32 * 0.03,
                        z as f32 * 0.01 + keyframe as f32 * 0.04,
                    ];
                    for axis in 0..3 {
                        let code = (values[axis] / scales[axis])
                            .round()
                            .clamp(-32767.0, 32767.0) as i16;
                        write_u16(&mut bytes, cursor, code as u16);
                        cursor += 2;
                    }
                }
            }
        }
    }
    bytes
}

fn write_u16(bytes: &mut [u8], offset: usize, value: u16) {
    bytes[offset..offset + 2].copy_from_slice(&value.to_le_bytes());
}

fn write_u32(bytes: &mut [u8], offset: usize, value: u32) {
    bytes[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
}

fn write_u64(bytes: &mut [u8], offset: usize, value: u64) {
    bytes[offset..offset + 8].copy_from_slice(&value.to_le_bytes());
}

fn write_f32(bytes: &mut [u8], offset: usize, value: f32) {
    bytes[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
}

fn main() {
    let output = env::args().nth(1).unwrap_or_else(|| {
        eprintln!("usage: generate_fovea4d_v1_fixture <output.fovea4d>");
        std::process::exit(2);
    });
    let bytes = build_fixture();
    parse_fovea4d(&bytes).expect("generated fixture must validate");
    let path = Path::new(&output);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create fixture directory");
    }
    fs::write(path, bytes).expect("write fixture");
    println!(
        "Generated canonical Rust FOVEA_4D fixture: {}",
        path.display()
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fixture_has_canonical_layout() {
        let bytes = build_fixture();
        let (header, payload) = parse_fovea4d(&bytes).expect("fixture validates");
        assert_eq!(bytes.len(), 224);
        assert_eq!(header.grid_dims, [2, 2, 2]);
        assert_eq!(payload.len(), 96);
    }
}
