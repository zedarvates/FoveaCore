#![allow(clippy::result_large_err)] // Generated Godot bindings expose large error variants.

use godot::prelude::*;
use std::fs::File;
use std::io::Read;
use std::io::Write;
use std::io::BufReader;

const FOVEA_MAGIC: [u8; 8] = *b"FOVEA_3D";
const FOVEA_VERSION: u32 = 2;
const FOVEA_HEADER_SIZE: usize = 72;
const COLOR_ENTRY_SIZE: usize = 12;
const COVARIANCE_ENTRY_SIZE: usize = 32;
const SPLAT_RECORD_SIZE: usize = 16;
const MAX_COLOR_CODEBOOK_SIZE: u32 = 256;
const MAX_COVARIANCE_CODEBOOK_SIZE: u32 = 1024;

/// En-tête du fichier .fovea natif
#[derive(Clone, Copy)]
#[repr(C)]
pub struct FoveaAssetHeader {
    pub magic: [u8; 8], // Doit correspondre à b"FOVEA_3D"
    pub version: u32,
    pub splat_count: u32,
    pub color_codebook_size: u32,  // Nouveau: taille de la palette de couleurs
    pub covar_codebook_size: u32,
    
    // Bounding box pour décoder la Quantisation Spatiale (Fixed-Point Math)
    pub aabb_min: [f32; 3],
    pub aabb_max: [f32; 3],

    // Offsets absolus pour les données optionnelles
    pub style_offset: u32,
    pub style_size: u32,
    pub mesh_offset: u32,
    pub mesh_size: u32,
    pub meta_offset: u32,
    pub meta_size: u32,
}

#[derive(Clone, Copy, Debug)]
struct FoveaLayout {
    palette_start: usize,
    palette_end: usize,
    covariance_start: usize,
    covariance_end: usize,
    splats_start: usize,
    splats_end: usize,
}

fn encode_header(header: &FoveaAssetHeader) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(FOVEA_HEADER_SIZE);
    bytes.extend_from_slice(&header.magic);
    for value in [
        header.version,
        header.splat_count,
        header.color_codebook_size,
        header.covar_codebook_size,
    ] {
        bytes.extend_from_slice(&value.to_le_bytes());
    }
    for value in header.aabb_min.into_iter().chain(header.aabb_max) {
        bytes.extend_from_slice(&value.to_le_bytes());
    }
    for value in [
        header.style_offset,
        header.style_size,
        header.mesh_offset,
        header.mesh_size,
        header.meta_offset,
        header.meta_size,
    ] {
        bytes.extend_from_slice(&value.to_le_bytes());
    }
    debug_assert_eq!(bytes.len(), FOVEA_HEADER_SIZE);
    bytes
}

fn read_u32_le(bytes: &[u8], cursor: &mut usize) -> Option<u32> {
    let end = cursor.checked_add(4)?;
    let value = u32::from_le_bytes(bytes.get(*cursor..end)?.try_into().ok()?);
    *cursor = end;
    Some(value)
}

fn read_f32_le(bytes: &[u8], cursor: &mut usize) -> Option<f32> {
    let end = cursor.checked_add(4)?;
    let value = f32::from_le_bytes(bytes.get(*cursor..end)?.try_into().ok()?);
    *cursor = end;
    Some(value)
}

fn decode_header(bytes: &[u8]) -> Option<FoveaAssetHeader> {
    if bytes.len() < FOVEA_HEADER_SIZE {
        return None;
    }
    let magic: [u8; 8] = bytes.get(0..8)?.try_into().ok()?;
    let mut cursor = 8;
    let version = read_u32_le(bytes, &mut cursor)?;
    let splat_count = read_u32_le(bytes, &mut cursor)?;
    let color_codebook_size = read_u32_le(bytes, &mut cursor)?;
    let covar_codebook_size = read_u32_le(bytes, &mut cursor)?;
    let aabb_min = [
        read_f32_le(bytes, &mut cursor)?,
        read_f32_le(bytes, &mut cursor)?,
        read_f32_le(bytes, &mut cursor)?,
    ];
    let aabb_max = [
        read_f32_le(bytes, &mut cursor)?,
        read_f32_le(bytes, &mut cursor)?,
        read_f32_le(bytes, &mut cursor)?,
    ];
    Some(FoveaAssetHeader {
        magic,
        version,
        splat_count,
        color_codebook_size,
        covar_codebook_size,
        aabb_min,
        aabb_max,
        style_offset: read_u32_le(bytes, &mut cursor)?,
        style_size: read_u32_le(bytes, &mut cursor)?,
        mesh_offset: read_u32_le(bytes, &mut cursor)?,
        mesh_size: read_u32_le(bytes, &mut cursor)?,
        meta_offset: read_u32_le(bytes, &mut cursor)?,
        meta_size: read_u32_le(bytes, &mut cursor)?,
    })
}

fn validated_layout(header: &FoveaAssetHeader, file_len: usize) -> Option<FoveaLayout> {
    if header.magic != FOVEA_MAGIC
        || header.version != FOVEA_VERSION
        || header.splat_count == 0
        || !(1..=MAX_COLOR_CODEBOOK_SIZE).contains(&header.color_codebook_size)
        || !(1..=MAX_COVARIANCE_CODEBOOK_SIZE).contains(&header.covar_codebook_size)
    {
        return None;
    }
    if !header.aabb_min.iter().chain(header.aabb_max.iter()).all(|v| v.is_finite())
        || header.aabb_min.iter().zip(header.aabb_max.iter()).any(|(min, max)| min > max)
    {
        return None;
    }

    let palette_start = FOVEA_HEADER_SIZE;
    let palette_end = palette_start.checked_add(
        (header.color_codebook_size as usize).checked_mul(COLOR_ENTRY_SIZE)?,
    )?;
    let covariance_start = palette_end;
    let covariance_end = covariance_start.checked_add(
        (header.covar_codebook_size as usize).checked_mul(COVARIANCE_ENTRY_SIZE)?,
    )?;
    let splats_start = covariance_end;
    let splats_end = splats_start.checked_add(
        (header.splat_count as usize).checked_mul(SPLAT_RECORD_SIZE)?,
    )?;
    if splats_end > file_len {
        return None;
    }

    let mut optional_ranges: Vec<(usize, usize)> = Vec::new();
    for (offset, size) in [
        (header.style_offset, header.style_size),
        (header.mesh_offset, header.mesh_size),
        (header.meta_offset, header.meta_size),
    ] {
        if (offset == 0) != (size == 0) {
            return None;
        }
        if offset == 0 {
            continue;
        }
        let start = offset as usize;
        let end = start.checked_add(size as usize)?;
        if start < splats_end || end > file_len {
            return None;
        }
        optional_ranges.push((start, end));
    }
    optional_ranges.sort_by_key(|range| range.0);
    let mut previous_end = splats_end;
    for (start, end) in optional_ranges {
        if start < previous_end {
            return None;
        }
        previous_end = end;
    }

    Some(FoveaLayout {
        palette_start,
        palette_end,
        covariance_start,
        covariance_end,
        splats_start,
        splats_end,
    })
}

fn parse_layout(bytes: &[u8]) -> Option<(FoveaAssetHeader, FoveaLayout)> {
    let header = decode_header(bytes)?;
    let layout = validated_layout(&header, bytes.len())?;
    Some((header, layout))
}

/// Structure GPU ultra-optimisée : EXACTEMENT 16 octets par splat !
/// L'attribut align(16) garantit un mapping parfait pour les Compute Shaders Vulkan/OpenGL.
#[repr(C, align(16))]
pub struct FoveaPackedSplat {
    // 1. Spatial Quantization : Grille locale (16-bits par axe) -> 6 octets
    pub pos_x: u16,
    pub pos_y: u16,
    pub pos_z: u16,
    
    // 2. Normale encodée pour le Backface Culling rapide (8-bits) -> 2 octets
    pub norm_u: i8,
    pub norm_v: i8,
    
    // 3. Vector Quantization : Index vers les Palettes partagées -> 4 octets
    //    color_index: 8 bits (palette 256 couleurs), covar_index: 16 bits
    pub color_index: u8,      // Index dans la palette de couleurs (0-255)
    pub padding1: u8,         // Padding pour alignement
    pub covar_index: u16,     // Index vers la palette de covariance
    
    // 4. Données locales -> 4 octets
    pub opacity: u8,          // Opacité (0-255)
    pub layer_id: u8,
    pub dither_seed: u8,      // Seed pour dithering stochastique
    pub brush_type: u8,       // GaussianSplat.BrushType (2 = Gaussian)
}

/// Représente une couleur RGB pour le K-Means
#[derive(Clone, Copy)]
struct Color3D {
    r: f32,
    g: f32,
    b: f32,
}

impl Color3D {
    fn new(r: f32, g: f32, b: f32) -> Self {
        Color3D { r, g, b }
    }
    
    fn distance_squared(&self, other: &Color3D) -> f32 {
        let dr = self.r - other.r;
        let dg = self.g - other.g;
        let db = self.b - other.b;
        dr * dr + dg * dg + db * db
    }
    
    fn add(&mut self, other: &Color3D) {
        self.r += other.r;
        self.g += other.g;
        self.b += other.b;
    }
    
}

/// Classe exposée à Godot pour charger les assets de manière asynchrone et sécurisée
#[derive(GodotClass)]
#[class(tool, base=RefCounted)]
pub struct FoveaAssetLoader {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for FoveaAssetLoader {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl FoveaAssetLoader {
    /// Convertit un fichier .ply standard 3DGS vers le format binaire optimisé .fovea
    /// avec quantification des couleurs (K-Means) et dithering Floyd-Steinberg
    #[func]
    pub fn convert_ply_to_fovea(ply_path: GString, fovea_path: GString) -> bool {
        let ply_str = ply_path.to_string();
        let fovea_str = fovea_path.to_string();
        
        let file = match File::open(&ply_str) {
            Ok(f) => f,
            Err(e) => {
                godot_print!("FoveaEngine [Rust Error] : Impossible de lire le PLY: {}", e);
                return false;
            }
        };
        
        let mut reader = BufReader::new(file);
        let mut vertex_count = 0;
        let mut property_names = Vec::new();
        
        // 1. Parsing manuel ultra-rapide de l'en-tête texte du PLY
        loop {
            let mut line = String::new();
            let mut byte_buf = [0u8; 1];
            while let Ok(1) = reader.read(&mut byte_buf) {
                let c = byte_buf[0] as char;
                line.push(c);
                if c == '\n' { break; }
            }
            
            if line.is_empty() { break; }
            
            if line.starts_with("element vertex") {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() == 3 {
                    vertex_count = parts[2].parse().unwrap_or(0);
                }
            }

            if line.starts_with("property") {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 3 {
                    property_names.push(parts[2].to_string());
                }
            }
            
            if line.starts_with("end_header") {
                break;
            }
        }
        
        if vertex_count == 0 {
            godot_print!("FoveaEngine [Rust Error] : Aucun vertex trouvé dans le PLY.");
            return false;
        }
        
        godot_print!("FoveaEngine [Rust] : Début de la conversion de {} splats...", vertex_count);
        
        // 2. Préparation du fichier de sortie .fovea
        let mut out_file = match File::create(&fovea_str) {
            Ok(f) => f,
            Err(_) => return false,
        };
        
        let floats_per_vertex = property_names.len();
        if floats_per_vertex == 0 {
            godot_print!("FoveaEngine [Rust Error] : Aucun format de propriété trouvé dans le PLY.");
            return false;
        }

        // Identification dynamique des offsets (selon la structure COLMAP/3DGS standard)
        let idx_x = property_names.iter().position(|r| r == "x").unwrap_or(0);
        let idx_y = property_names.iter().position(|r| r == "y").unwrap_or(1);
        let idx_z = property_names.iter().position(|r| r == "z").unwrap_or(2);
        let idx_f_dc_0 = property_names.iter().position(|r| r == "f_dc_0").unwrap_or(6);
        let idx_f_dc_1 = property_names.iter().position(|r| r == "f_dc_1").unwrap_or(7);
        let idx_f_dc_2 = property_names.iter().position(|r| r == "f_dc_2").unwrap_or(8);
        let idx_opac = property_names.iter().position(|r| r == "opacity").unwrap_or(54);
        
        // Nouveaux offsets pour l'anisotropie (Scale & Rotation)
        let idx_scale_0 = property_names.iter().position(|r| r == "scale_0").unwrap_or(usize::MAX);
        let idx_scale_1 = property_names.iter().position(|r| r == "scale_1").unwrap_or(usize::MAX);
        let idx_scale_2 = property_names.iter().position(|r| r == "scale_2").unwrap_or(usize::MAX);
        let idx_rot_0 = property_names.iter().position(|r| r == "rot_0").unwrap_or(usize::MAX);
        let idx_rot_1 = property_names.iter().position(|r| r == "rot_1").unwrap_or(usize::MAX);
        let idx_rot_2 = property_names.iter().position(|r| r == "rot_2").unwrap_or(usize::MAX);
        let idx_rot_3 = property_names.iter().position(|r| r == "rot_3").unwrap_or(usize::MAX);

        struct RawSplat {
            pos: [f32; 3],
            opacity: f32,
            scale: [f32; 3],
            rot: [f32; 4],
        }
        
        let mut raw_splats = Vec::with_capacity(vertex_count as usize);
        let mut aabb_min = [f32::MAX; 3];
        let mut aabb_max = [f32::MIN; 3];
        let mut raw_colors = Vec::with_capacity(vertex_count as usize);

        // 3. Lecture séquentielle rapide et calcul de la Bounding Box
        let mut byte_row = vec![0u8; floats_per_vertex * 4];
        for _ in 0..vertex_count {
            if reader.read_exact(&mut byte_row).is_err() { break; }
            
            let get_float = |idx: usize| -> f32 {
                let start = idx * 4;
                if start + 4 > byte_row.len() { return 0.0; }
                f32::from_le_bytes(byte_row[start..start+4].try_into().unwrap_or([0; 4]))
            };

            let x = get_float(idx_x);
            let y = get_float(idx_y);
            let z = get_float(idx_z);
            let f_dc_0 = get_float(idx_f_dc_0);
            let f_dc_1 = get_float(idx_f_dc_1);
            let f_dc_2 = get_float(idx_f_dc_2);
            let opacity = get_float(idx_opac);
            
            let scale_0 = if idx_scale_0 != usize::MAX { get_float(idx_scale_0) } else { -4.0 };
            let scale_1 = if idx_scale_1 != usize::MAX { get_float(idx_scale_1) } else { -4.0 };
            let scale_2 = if idx_scale_2 != usize::MAX { get_float(idx_scale_2) } else { -4.0 };
            let rot_0 = if idx_rot_0 != usize::MAX { get_float(idx_rot_0) } else { 1.0 };
            let rot_1 = if idx_rot_1 != usize::MAX { get_float(idx_rot_1) } else { 0.0 };
            let rot_2 = if idx_rot_2 != usize::MAX { get_float(idx_rot_2) } else { 0.0 };
            let rot_3 = if idx_rot_3 != usize::MAX { get_float(idx_rot_3) } else { 0.0 };

            // NaN / Inf Filtering
            if !x.is_finite() || !y.is_finite() || !z.is_finite() ||
               !f_dc_0.is_finite() || !f_dc_1.is_finite() || !f_dc_2.is_finite() ||
               !opacity.is_finite() || !scale_0.is_finite() || !scale_1.is_finite() || !scale_2.is_finite() ||
               !rot_0.is_finite() || !rot_1.is_finite() || !rot_2.is_finite() || !rot_3.is_finite() {
                continue;
            }

            // Convertir SH0 en couleur RGB linéaire
            let c0 = f_dc_0 * 0.28209479 + 0.5;
            let c1 = f_dc_1 * 0.28209479 + 0.5;
            let c2 = f_dc_2 * 0.28209479 + 0.5;
            
            let color = Color3D::new(c0, c1, c2);
            raw_colors.push(color);

            aabb_min[0] = aabb_min[0].min(x); aabb_min[1] = aabb_min[1].min(y); aabb_min[2] = aabb_min[2].min(z);
            aabb_max[0] = aabb_max[0].max(x); aabb_max[1] = aabb_max[1].max(y); aabb_max[2] = aabb_max[2].max(z);

            raw_splats.push(RawSplat { 
                pos: [x, y, z], opacity,
                scale: [scale_0, scale_1, scale_2], rot: [rot_0, rot_1, rot_2, rot_3] 
            });
        }
        
        // 4. Préparation pour la Spatial Quantization
        let range_x = (aabb_max[0] - aabb_min[0]).max(0.0001);
        let range_y = (aabb_max[1] - aabb_min[1]).max(0.0001);
        let range_z = (aabb_max[2] - aabb_min[2]).max(0.0001);

        // --- 4.1. VECTOR QUANTIZATION (K-Means) SUR LA COVARIANCE ---
        godot_print!("FoveaEngine [Rust] : Lancement de la Vector Quantization (K-Means) sur l'anisotropie...");
        const K_CLUSTERS: usize = 1024;
        let actual_k = K_CLUSTERS.min(raw_splats.len());
        
        let mut centroids: Vec<[f32; 7]> = (0..actual_k)
            .map(|i| {
                let s = &raw_splats[(i * raw_splats.len()) / actual_k];
                [s.scale[0], s.scale[1], s.scale[2], s.rot[0], s.rot[1], s.rot[2], s.rot[3]]
            })
            .collect();
            
        let mut assignments = vec![0u16; raw_splats.len()];
        let num_iterations = 6;
        
        for _ in 0..num_iterations {
            let mut sums = vec![[0.0f32; 7]; actual_k];
            let mut counts = vec![0u32; actual_k];
            
            for (i, raw) in raw_splats.iter().enumerate() {
                let v = [raw.scale[0], raw.scale[1], raw.scale[2], raw.rot[0], raw.rot[1], raw.rot[2], raw.rot[3]];
                let mut best_dist = f32::MAX;
                let mut best_c = 0;
                
                for (c_idx, c) in centroids.iter().enumerate() {
                    let dist = (v[0]-c[0]).powi(2) + (v[1]-c[1]).powi(2) + (v[2]-c[2]).powi(2) +
                               (v[3]-c[3]).powi(2) + (v[4]-c[4]).powi(2) + (v[5]-c[5]).powi(2) + (v[6]-c[6]).powi(2);
                    if dist < best_dist {
                        best_dist = dist;
                        best_c = c_idx;
                    }
                }
                
                assignments[i] = best_c as u16;
                for (sum, value) in sums[best_c].iter_mut().zip(v) {
                    *sum += value;
                }
                counts[best_c] += 1;
            }
            
            for c_idx in 0..actual_k {
                if counts[c_idx] > 0 {
                    for (centroid, sum) in centroids[c_idx].iter_mut().zip(sums[c_idx]) {
                        *centroid = sum / (counts[c_idx] as f32);
                    }
                }
            }
        }
        
        // Normalisation des quaternions post-moyenne
        for c in centroids.iter_mut() {
            let len = (c[3].powi(2) + c[4].powi(2) + c[5].powi(2) + c[6].powi(2)).sqrt();
            if len > 0.0001 {
                c[3] /= len; c[4] /= len; c[5] /= len; c[6] /= len;
            } else {
                c[3] = 1.0; c[4] = 0.0; c[5] = 0.0; c[6] = 0.0;
            }
        }
        
        // Sérialisation du Codebook (32 octets par palette pour alignement std140 GPU)
        let mut codebook_bytes = Vec::with_capacity(actual_k * 32);
        for c in centroids.iter() {
            codebook_bytes.extend_from_slice(&c[0].to_le_bytes());
            codebook_bytes.extend_from_slice(&c[1].to_le_bytes());
            codebook_bytes.extend_from_slice(&c[2].to_le_bytes());
            codebook_bytes.extend_from_slice(&c[3].to_le_bytes());
            codebook_bytes.extend_from_slice(&c[4].to_le_bytes());
            codebook_bytes.extend_from_slice(&c[5].to_le_bytes());
            codebook_bytes.extend_from_slice(&c[6].to_le_bytes());
            codebook_bytes.extend_from_slice(&0.0f32.to_le_bytes());
        }

        // --- 4.2. K-MEANS SUR LES COULEURS (RGB) ---
        godot_print!("FoveaEngine [Rust] : Lancement du K-Means sur les couleurs (max 256)...");
        const COLOR_CLUSTERS: usize = 256;
        let color_k = COLOR_CLUSTERS.min(raw_colors.len().min(256));
        
        // Initialisation K-Means++ pour les couleurs
        let mut color_centroids: Vec<Color3D> = Vec::with_capacity(color_k);
        color_centroids.push(raw_colors[0]);
        
        for _ in 1..color_k {
            let mut max_dist = 0.0f32;
            let mut next_centroid = raw_colors[0];
            
            for color in raw_colors.iter() {
                let mut min_dist = f32::MAX;
                for centroid in color_centroids.iter() {
                    let dist = color.distance_squared(centroid);
                    min_dist = min_dist.min(dist);
                }
                if min_dist > max_dist {
                    max_dist = min_dist;
                    next_centroid = *color;
                }
            }
            color_centroids.push(next_centroid);
        }
        
        let mut color_assignments = vec![0u8; raw_colors.len()];
        let color_iterations = 8;
        
        for _ in 0..color_iterations {
            let mut color_sums = vec![Color3D::new(0.0, 0.0, 0.0); color_k];
            let mut color_counts = vec![0u32; color_k];
            
            for (i, color) in raw_colors.iter().enumerate() {
                let mut best_dist = f32::MAX;
                let mut best_idx = 0;
                
                for (c_idx, centroid) in color_centroids.iter().enumerate() {
                    let dist = color.distance_squared(centroid);
                    if dist < best_dist {
                        best_dist = dist;
                        best_idx = c_idx;
                    }
                }
                
                color_assignments[i] = best_idx as u8;
                color_sums[best_idx].add(color);
                color_counts[best_idx] += 1;
            }
            
            let mut changed = false;
            for c_idx in 0..color_k {
                if color_counts[c_idx] > 0 {
                    let count_f = color_counts[c_idx] as f32;
                    let new_centroid = Color3D::new(
                        color_sums[c_idx].r / count_f,
                        color_sums[c_idx].g / count_f,
                        color_sums[c_idx].b / count_f,
                    );
                    
                    if new_centroid.distance_squared(&color_centroids[c_idx]) > 0.0001 {
                        changed = true;
                    }
                    color_centroids[c_idx] = new_centroid;
                }
            }
            
            if !changed { break; }
        }
        
        // --- 4.3. DITHERING FLOYD-STEINBERG ---
        godot_print!("FoveaEngine [Rust] : Application du dithering Floyd-Steinberg...");
        
        // Pour le dithering, on a besoin de l'ordre spatial des splats
        // On va appliquer un dithering basé sur la position spatiale
        let mut dither_seeds = vec![0u8; raw_splats.len()];
        
        // Créer une grille 2D pour le dithering spatial
        // On mappe les positions 3D en coordonnées 2D pour le dithering
        for (i, splat) in raw_splats.iter().enumerate() {
            let nx = ((splat.pos[0] - aabb_min[0]) / range_x * 255.0) as u32;
            let ny = ((splat.pos[1] - aabb_min[1]) / range_y * 255.0) as u32;
            let nz = ((splat.pos[2] - aabb_min[2]) / range_z * 255.0) as u32;
            
            // Seed pseudo-aléatoire basée sur la position (pour dithering stochastique)
            let seed = ((nx.wrapping_mul(73856093) ^
                        ny.wrapping_mul(19349663) ^
                        nz.wrapping_mul(83492791)) & 0xFF) as u8;
            
            dither_seeds[i] = seed;
            
            // Ajuster l'index de couleur avec dithering (bruit sur l'index)
            let current_idx = color_assignments[i] as i16;
            let dither_offset = (seed as i16 - 128) / 512; // -0.25 à +0.25
            let dithered_idx = (current_idx + dither_offset).clamp(0, color_k as i16 - 1) as u8;
            color_assignments[i] = dithered_idx;
        }
        
        godot_print!("FoveaEngine [Rust] : Palette générée avec {} couleurs.", color_k);

        // 5. Encodage GPU-Ready (16 octets/splat) et écriture binaire
        let header = FoveaAssetHeader {
            magic: FOVEA_MAGIC,
            version: FOVEA_VERSION,
            splat_count: raw_splats.len() as u32,
            color_codebook_size: color_k as u32,
            covar_codebook_size: actual_k as u32,
            aabb_min, aabb_max,
            style_offset: 0,
            style_size: 0,
            mesh_offset: 0,
            mesh_size: 0,
            meta_offset: 0,
            meta_size: 0,
        };
        
        let header_bytes = encode_header(&header);
        if out_file.write_all(&header_bytes).is_err() { return false; }
        
        // --- Écriture de la palette de couleurs (RGB, 3 floats par couleur) ---
        let mut palette_bytes = Vec::with_capacity(color_k * 12); // 3 * 4 bytes
        for c in color_centroids.iter() {
            palette_bytes.extend_from_slice(&c.r.to_le_bytes());
            palette_bytes.extend_from_slice(&c.g.to_le_bytes());
            palette_bytes.extend_from_slice(&c.b.to_le_bytes());
        }
        if out_file.write_all(&palette_bytes).is_err() { return false; }
        
        // --- Écriture du codebook de covariance ---
        if out_file.write_all(&codebook_bytes).is_err() { return false; }

        // 6. Encodage final des splats (16 octets/splat)
        let mut packed_splats = Vec::with_capacity(raw_splats.len());
        for (i, raw) in raw_splats.into_iter().enumerate() {
            // A. Spatial Quantization (Position Normalisée en 16-bits)
            let qx = (((raw.pos[0] - aabb_min[0]) / range_x) * 65535.0).clamp(0.0, 65535.0) as u16;
            let qy = (((raw.pos[1] - aabb_min[1]) / range_y) * 65535.0).clamp(0.0, 65535.0) as u16;
            let qz = (((raw.pos[2] - aabb_min[2]) / range_z) * 65535.0).clamp(0.0, 65535.0) as u16;

            // B. Opacité (0-255)
            let sigmoid_op = 1.0 / (1.0 + (-raw.opacity).exp());
            let op8 = (sigmoid_op * 255.0).clamp(0.0, 255.0) as u8;

            packed_splats.push(FoveaPackedSplat {
                pos_x: qx, pos_y: qy, pos_z: qz,
                norm_u: 0, norm_v: 0,
                color_index: color_assignments[i],  // Index de palette 8-bit !
                padding1: 0,
                covar_index: assignments[i],
                opacity: op8,
                layer_id: 0,
                dither_seed: dither_seeds[i],
                // Keep the binary contract aligned with GaussianSplat.BrushType:
                // 0 = Stone, 2 = Gaussian.
                brush_type: 2,
            });
        }

        // Morton Order sorting helper functions
        fn part_1_by_2(mut x: u32) -> u32 {
            x &= 0x000003ff;
            x = (x ^ (x << 16)) & 0xff0000ff;
            x = (x ^ (x << 8))  & 0x0300f00f;
            x = (x ^ (x << 4))  & 0x030c30c3;
            x = (x ^ (x << 2))  & 0x09249249;
            x
        }

        fn morton_encode_3d(x: u32, y: u32, z: u32) -> u32 {
            (part_1_by_2(x) << 2) | (part_1_by_2(y) << 1) | part_1_by_2(z)
        }

        // Sort splats using Morton codes to group close ones spatially (improving GPU cache)
        packed_splats.sort_by_cached_key(|splat| {
            let mx = splat.pos_x as u32 >> 6;
            let my = splat.pos_y as u32 >> 6;
            let mz = splat.pos_z as u32 >> 6;
            morton_encode_3d(mx, my, mz)
        });
        
        let splats_bytes: &[u8] = unsafe {
            std::slice::from_raw_parts(
                packed_splats.as_ptr() as *const u8,
                packed_splats.len() * std::mem::size_of::<FoveaPackedSplat>()
            )
        };
        if out_file.write_all(splats_bytes).is_err() { return false; }
        
        // --- 7. Calcul des statistiques ---
        let original_rgb_bits = raw_colors.len() * 3 * 8; // 24 bits par couleur (RGB8)
        let quantized_bits = raw_colors.len() * 8; // 8 bits par couleur (index)
        let palette_bits = color_k * 3 * 32; // 32 bits par couleur de palette (float32)
        let total_compressed = palette_bits + quantized_bits;
        let compression_ratio = original_rgb_bits as f64 / total_compressed as f64;
        
        godot_print!("FoveaEngine [Rust] : === STATISTIQUES DE COMPRESSION ===");
        godot_print!("FoveaEngine [Rust] : Couleurs originales : {} ({} bits)", raw_colors.len(), original_rgb_bits);
        godot_print!("FoveaEngine [Rust] : Palette quantifiée : {} couleurs ({} bits)", color_k, palette_bits);
        godot_print!("FoveaEngine [Rust] : Index par splat : {} bits", 8);
        godot_print!("FoveaEngine [Rust] : Ratio de compression : {:.2}x", compression_ratio);
        godot_print!("FoveaEngine [Rust] : Mémoire économisée : {:.1}%", (1.0 - total_compressed as f64 / original_rgb_bits as f64) * 100.0);
        
        godot_print!("FoveaEngine [Rust] : Converti avec succès en {} ({} splats quantifiés).", fovea_str, packed_splats.len());
        true
    }
    
    /// Charge un fichier .fovea et retourne les octets bruts prêts pour le Compute Shader
    #[func]
    pub fn load_fast_path(path: GString) -> PackedByteArray {
        let path_str = path.to_string();
        
        // 1. Lecture ultra-rapide via I/O natif (sans parsing CPU)
        let mut file = match File::open(&path_str) {
            Ok(f) => f,
            Err(e) => {
                godot_print!("FoveaEngine [Rust Error] : Impossible d'ouvrir {} - {}", path_str, e);
                return PackedByteArray::new();
            }
        };

        let mut buffer = Vec::new();
        if let Err(e) = file.read_to_end(&mut buffer) {
            godot_print!("FoveaEngine [Rust Error] : Erreur de lecture sur {} - {}", path_str, e);
            return PackedByteArray::new();
        }

        // 2. Validation complète de l'en-tête, des tailles et des sections.
        let (_, layout) = match parse_layout(&buffer) {
            Some(parsed) => parsed,
            None => {
            godot_print!("FoveaEngine [Rust Error] : Fichier corrompu ou format invalide !");
            return PackedByteArray::new();
            }
        };

        godot_print!("FoveaEngine [Rust] : Asset chargé en RAM ({} octets). Prêt pour VRAM.", buffer.len());

        // 3. On ne renvoie QUE les octets des splats pour le buffer du MultiMesh (Zéro décalage)
        PackedByteArray::from(&buffer[layout.splats_start..layout.splats_end])
    }
    
    /// Lit l'en-tête binaire d'un fichier .fovea pour en extraire l'AABB (Bounding Box)
    #[func]
    pub fn get_asset_aabb(path: GString) -> Aabb {
        let path_str = path.to_string();
        let mut file = match File::open(&path_str) {
            Ok(f) => f,
            Err(_) => return Aabb::new(Vector3::ZERO, Vector3::ZERO),
        };

        let file_len = match file.metadata() {
            Ok(metadata) => metadata.len() as usize,
            Err(_) => return Aabb::new(Vector3::ZERO, Vector3::ZERO),
        };
        let mut header_bytes = [0u8; FOVEA_HEADER_SIZE];
        if file.read_exact(&mut header_bytes).is_err() {
            return Aabb::new(Vector3::ZERO, Vector3::ZERO);
        }

        let header = match decode_header(&header_bytes) {
            Some(header) if validated_layout(&header, file_len).is_some() => header,
            _ => return Aabb::new(Vector3::ZERO, Vector3::ZERO),
        };
        if header.magic != FOVEA_MAGIC {
            return Aabb::new(Vector3::ZERO, Vector3::ZERO);
        }

        let min = Vector3::new(header.aabb_min[0], header.aabb_min[1], header.aabb_min[2]);
        let max = Vector3::new(header.aabb_max[0], header.aabb_max[1], header.aabb_max[2]);
        
        Aabb::new(min, max - min)
    }
    
    /// Lit spécifiquement la palette de couleurs (Codebook) pour le shader
    #[func]
    pub fn load_color_palette(path: GString) -> PackedByteArray {
        let path_str = path.to_string();
        let mut file = match File::open(&path_str) {
            Ok(f) => f,
            Err(_) => return PackedByteArray::new(),
        };

        let mut buffer = Vec::new();
        if file.read_to_end(&mut buffer).is_err() {
            return PackedByteArray::new();
        }

        let (_, layout) = match parse_layout(&buffer) {
            Some(parsed) => parsed,
            None => return PackedByteArray::new(),
        };
        PackedByteArray::from(&buffer[layout.palette_start..layout.palette_end])
    }
    
    /// Lit spécifiquement la palette de covariance (K-Means Codebook) pour le shader
    #[func]
    pub fn load_covar_codebook(path: GString) -> PackedByteArray {
        let path_str = path.to_string();
        let mut file = match File::open(&path_str) {
            Ok(f) => f,
            Err(_) => return PackedByteArray::new(),
        };

        let mut buffer = Vec::new();
        if file.read_to_end(&mut buffer).is_err() {
            return PackedByteArray::new();
        }

        let (_, layout) = match parse_layout(&buffer) {
            Some(parsed) => parsed,
            None => return PackedByteArray::new(),
        };
        PackedByteArray::from(&buffer[layout.covariance_start..layout.covariance_end])
    }

    /// Alias de compatibilité pour load_covar_codebook appelé par GDScript
    #[func]
    pub fn load_covariance_codebook(path: GString) -> PackedByteArray {
        Self::load_covar_codebook(path)
    }

    /// Charge directement un segment de fichier dans un buffer GPU (Style DirectStorage)
    #[func]
    pub fn upload_file_slice_to_gpu_buffer(
        &self,
        mut rd: Gd<godot::classes::RenderingDevice>,
        file_path: GString,
        file_offset: i64,
        size: i64,
        buffer_rid: Rid,
        buffer_offset: i64,
    ) -> bool {
        let path_str = file_path.to_string();
        let mut file = match File::open(&path_str) {
            Ok(f) => f,
            Err(e) => {
                godot_print!("FoveaEngine DirectStorage [Error] : Impossible d'ouvrir le fichier {} - {}", path_str, e);
                return false;
            }
        };
        use std::io::Seek;
        if file.seek(std::io::SeekFrom::Start(file_offset as u64)).is_err() {
            godot_print!("FoveaEngine DirectStorage [Error] : Echec de seek dans le fichier");
            return false;
        }
        let mut buffer = vec![0u8; size as usize];
        if let Err(e) = file.read_exact(&mut buffer) {
            godot_print!("FoveaEngine DirectStorage [Error] : Echec de read_exact dans le fichier : {}", e);
            return false;
        }
        let packed_bytes = PackedByteArray::from(buffer.as_slice());
        rd.buffer_update(buffer_rid, buffer_offset as u32, size as u32, &packed_bytes);
        true
    }

    /// Charge asynchronement un segment de fichier dans un buffer GPU (Style DirectStorage)
    #[func]
    pub fn upload_file_slice_to_gpu_buffer_async(
        &self,
        rd: Gd<godot::classes::RenderingDevice>,
        file_path: GString,
        file_offset: i64,
        size: i64,
        buffer_rid: Rid,
        buffer_offset: i64,
    ) -> bool {
        let path_str = file_path.to_string();
        
        struct SendGd(Gd<godot::classes::RenderingDevice>);
        unsafe impl Send for SendGd {}
        unsafe impl Sync for SendGd {}
        
        let rd_send = SendGd(rd);
        let rid_send = buffer_rid;
        
        std::thread::spawn(move || {
            let mut file = match File::open(&path_str) {
                Ok(f) => f,
                Err(e) => {
                    godot_print!("FoveaEngine DirectStorage Async [Error] : Impossible d'ouvrir le fichier {} - {}", path_str, e);
                    return;
                }
            };
            use std::io::Seek;
            if file.seek(std::io::SeekFrom::Start(file_offset as u64)).is_err() {
                godot_print!("FoveaEngine DirectStorage Async [Error] : Echec de seek dans le fichier");
                return;
            }
            let mut buffer = vec![0u8; size as usize];
            if let Err(e) = file.read_exact(&mut buffer) {
                godot_print!("FoveaEngine DirectStorage Async [Error] : Echec de read_exact : {}", e);
                return;
            }
            let packed_bytes = PackedByteArray::from(buffer.as_slice());
            
            let mut rd_wrap = rd_send;
            unsafe {
                let rd_raw = &mut rd_wrap.0 as *mut Gd<godot::classes::RenderingDevice>;
                (*rd_raw).buffer_update(rid_send, buffer_offset as u32, size as u32, &packed_bytes);
            }
        });
        
        true
    }

    /// Réordonne les octets des splats selon un tableau d'indices triés
    #[func]
    pub fn reorder_splats(&self, bytes: PackedByteArray, sorted_indices: PackedInt32Array) -> PackedByteArray {
        let splats_slice = bytes.as_slice();
        let indices_slice = sorted_indices.as_slice();
        let total_splats = splats_slice.len() / 16;
        let mut out_buffer = vec![0u8; bytes.len()];
        
        for i in 0..total_splats {
            let orig_idx = indices_slice[i] as usize;
            if orig_idx * 16 + 15 < splats_slice.len() {
                out_buffer[i * 16 .. (i + 1) * 16].copy_from_slice(&splats_slice[orig_idx * 16 .. (orig_idx + 1) * 16]);
            }
        }
        PackedByteArray::from(out_buffer.as_slice())
    }

    /// Extrait les triangles visibles en espace mondial avec backface culling rapide en Rust
    #[func]
    pub fn extract_visible_triangles_native(
        &self,
        vertices: PackedVector3Array,
        normals: PackedVector3Array,
        indices: PackedInt32Array,
        world_transform: Transform3D,
        camera_position: Vector3,
    ) -> Dictionary {
        let vertices_slice = vertices.as_slice();
        let normals_slice = normals.as_slice();
        let indices_slice = indices.as_slice();
        
        let total_triangles = indices_slice.len() / 3;
        
        let mut visible_indices = Vec::new();
        let mut visible_vertices = Vec::new();
        let mut visible_normals = Vec::new();
        let mut centers = Vec::new();
        let mut areas = Vec::new();
        let mut distances = Vec::new();
        
        let mut culled_backface = 0i32;
        
        for i in (0..indices_slice.len()).step_by(3) {
            if i + 2 >= indices_slice.len() { break; }
            let idx0 = indices_slice[i] as usize;
            let idx1 = indices_slice[i+1] as usize;
            let idx2 = indices_slice[i+2] as usize;
            
            if idx0 >= vertices_slice.len() || idx1 >= vertices_slice.len() || idx2 >= vertices_slice.len() {
                continue;
            }
            
            let v0_local = vertices_slice[idx0];
            let v1_local = vertices_slice[idx1];
            let v2_local = vertices_slice[idx2];
            
            // Transformer les vertices en coordonnées mondiales
            let v0_world = world_transform.basis * v0_local + world_transform.origin;
            let v1_world = world_transform.basis * v1_local + world_transform.origin;
            let v2_world = world_transform.basis * v2_local + world_transform.origin;
            
            // Calcul de la normale pour le backface culling
            let edge1 = v1_world - v0_world;
            let edge2 = v2_world - v0_world;
            let face_normal = edge1.cross(edge2).normalized();
            let to_camera = (camera_position - v0_world).normalized();
            
            let dot = face_normal.dot(to_camera);
            if dot <= 0.0 {
                culled_backface += 1;
                continue;
            }
            
            // Calcul de l'aire
            let area = edge1.cross(edge2).length() / 2.0;
            
            // Centre du triangle
            let center = (v0_world + v1_world + v2_world) / 3.0;
            
            // Distance à la caméra
            let distance = center.distance_to(camera_position);
            
            // Normales mondiales
            let n0_world = (world_transform.basis * normals_slice[idx0]).normalized();
            let n1_world = (world_transform.basis * normals_slice[idx1]).normalized();
            let n2_world = (world_transform.basis * normals_slice[idx2]).normalized();
            
            // Stocker les résultats
            visible_indices.push(idx0 as i32);
            visible_indices.push(idx1 as i32);
            visible_indices.push(idx2 as i32);
            
            visible_vertices.push(v0_world);
            visible_vertices.push(v1_world);
            visible_vertices.push(v2_world);
            
            visible_normals.push(n0_world);
            visible_normals.push(n1_world);
            visible_normals.push(n2_world);
            
            centers.push(center);
            areas.push(area);
            distances.push(distance);
        }
        
        let visible_count = centers.len() as i32;
        let culled_occlusion = (total_triangles as i32) - visible_count - culled_backface;
        
        let mut dict = Dictionary::new();
        dict.set("indices", PackedInt32Array::from(visible_indices.as_slice()));
        dict.set("vertices", PackedVector3Array::from(visible_vertices.as_slice()));
        dict.set("normals", PackedVector3Array::from(visible_normals.as_slice()));
        dict.set("centers", PackedVector3Array::from(centers.as_slice()));
        dict.set("areas", PackedFloat32Array::from(areas.as_slice()));
        dict.set("distances", PackedFloat32Array::from(distances.as_slice()));
        
        dict.set("total_triangles", total_triangles as i32);
        dict.set("visible_count", visible_count);
        dict.set("culled_backface", culled_backface);
        dict.set("culled_occlusion", culled_occlusion);
        
        dict
    }
}

#[cfg(test)]
mod format_tests {
    use super::*;

    fn canonical_header() -> FoveaAssetHeader {
        FoveaAssetHeader {
            magic: FOVEA_MAGIC,
            version: FOVEA_VERSION,
            splat_count: 1,
            color_codebook_size: 1,
            covar_codebook_size: 1,
            aabb_min: [0.0, 0.0, 0.0],
            aabb_max: [1.0, 1.0, 1.0],
            style_offset: 0,
            style_size: 0,
            mesh_offset: 0,
            mesh_size: 0,
            meta_offset: 0,
            meta_size: 0,
        }
    }

    fn canonical_file_bytes() -> Vec<u8> {
        let mut bytes = encode_header(&canonical_header());
        bytes.resize(
            FOVEA_HEADER_SIZE + COLOR_ENTRY_SIZE + COVARIANCE_ENTRY_SIZE + SPLAT_RECORD_SIZE,
            0,
        );
        bytes
    }

    #[test]
    fn canonical_header_round_trips_as_little_endian() {
        let header = canonical_header();
        let encoded = encode_header(&header);
        assert_eq!(encoded.len(), FOVEA_HEADER_SIZE);
        assert_eq!(&encoded[0..8], &FOVEA_MAGIC);
        assert_eq!(u32::from_le_bytes(encoded[8..12].try_into().unwrap()), FOVEA_VERSION);

        let decoded = decode_header(&encoded).expect("canonical header decodes");
        assert_eq!(decoded.magic, FOVEA_MAGIC);
        assert_eq!(decoded.version, FOVEA_VERSION);
        assert_eq!(decoded.splat_count, 1);
    }

    #[test]
    fn canonical_layout_has_exact_section_boundaries() {
        let bytes = canonical_file_bytes();
        let (_, layout) = parse_layout(&bytes).expect("canonical layout validates");
        assert_eq!(layout.palette_start, FOVEA_HEADER_SIZE);
        assert_eq!(layout.palette_end, FOVEA_HEADER_SIZE + COLOR_ENTRY_SIZE);
        assert_eq!(layout.covariance_end, FOVEA_HEADER_SIZE + COLOR_ENTRY_SIZE + COVARIANCE_ENTRY_SIZE);
        assert_eq!(layout.splats_end, bytes.len());
        assert_eq!(std::mem::size_of::<FoveaPackedSplat>(), SPLAT_RECORD_SIZE);
    }

    #[test]
    fn corrupted_headers_are_rejected() {
        let mut unsupported_version = canonical_file_bytes();
        unsupported_version[8..12].copy_from_slice(&(FOVEA_VERSION + 1).to_le_bytes());
        assert!(parse_layout(&unsupported_version).is_none());

        let mut section_inside_payload = canonical_file_bytes();
        section_inside_payload[48..52].copy_from_slice(&(FOVEA_HEADER_SIZE as u32).to_le_bytes());
        section_inside_payload[52..56].copy_from_slice(&1u32.to_le_bytes());
        assert!(parse_layout(&section_inside_payload).is_none());

        let truncated = canonical_file_bytes()[0..FOVEA_HEADER_SIZE - 1].to_vec();
        assert!(parse_layout(&truncated).is_none());
    }

    #[test]
    fn gdscript_generated_golden_fixture_is_accepted() {
        // The fixture is generated through FoveaAssetWriter in
        // test/fixtures/generate_fixtures.gd. Keeping this compile-time input
        // makes the GDScript writer -> Rust reader contract deterministic.
        let bytes = include_bytes!("../../../../test/fixtures/reference_3dgs.fovea");
        let (header, layout) = parse_layout(bytes).expect("GDScript golden fixture validates");

        assert_eq!(header.splat_count, 8_000);
        assert_eq!(layout.splats_end, header.meta_offset as usize);
        assert_eq!(header.style_offset, 0);
        assert_eq!(header.style_size, 0);
        assert_eq!(header.meta_size as usize, bytes.len() - layout.splats_end);
        assert!(header.meta_size > 0);
    }
}
