use godot::prelude::*;
use std::fs::File;
use std::io::Read;
use std::io::Write;
use std::io::BufReader;
use std::mem;

/// En-tête du fichier .fovea natif
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
    pub padding2: u8,         // Padding
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
    
    fn scale(&mut self, factor: f32) {
        self.r *= factor;
        self.g *= factor;
        self.b *= factor;
    }
    
    fn lerp(&self, other: &Color3D, t: f32) -> Color3D {
        Color3D::new(
            self.r + (other.r - self.r) * t,
            self.g + (other.g - self.g) * t,
            self.b + (other.b - self.b) * t,
        )
    }
}

/// Classe exposée à Godot pour charger les assets de manière asynchrone et sécurisée
#[derive(GodotClass)]
#[class(base=RefCounted)]
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
        let mut header = String::new();
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
                let parts: Vec<&str> = line.trim().split_whitespace().collect();
                if parts.len() == 3 {
                    vertex_count = parts[2].parse().unwrap_or(0);
                }
            }

            if line.starts_with("property") {
                let parts: Vec<&str> = line.trim().split_whitespace().collect();
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
            f_dc: [f32; 3],
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
            
            // Convertir SH0 en couleur RGB linéaire
            let c0 = f_dc_0 * 0.28209479 + 0.5;
            let c1 = f_dc_1 * 0.28209479 + 0.5;
            let c2 = f_dc_2 * 0.28209479 + 0.5;
            
            let color = Color3D::new(c0, c1, c2);
            raw_colors.push(color);
            
            let scale_0 = if idx_scale_0 != usize::MAX { get_float(idx_scale_0) } else { -4.0 };
            let scale_1 = if idx_scale_1 != usize::MAX { get_float(idx_scale_1) } else { -4.0 };
            let scale_2 = if idx_scale_2 != usize::MAX { get_float(idx_scale_2) } else { -4.0 };
            let rot_0 = if idx_rot_0 != usize::MAX { get_float(idx_rot_0) } else { 1.0 };
            let rot_1 = if idx_rot_1 != usize::MAX { get_float(idx_rot_1) } else { 0.0 };
            let rot_2 = if idx_rot_2 != usize::MAX { get_float(idx_rot_2) } else { 0.0 };
            let rot_3 = if idx_rot_3 != usize::MAX { get_float(idx_rot_3) } else { 0.0 };

            aabb_min[0] = aabb_min[0].min(x); aabb_min[1] = aabb_min[1].min(y); aabb_min[2] = aabb_min[2].min(z);
            aabb_max[0] = aabb_max[0].max(x); aabb_max[1] = aabb_max[1].max(y); aabb_max[2] = aabb_max[2].max(z);

            raw_splats.push(RawSplat { 
                pos: [x, y, z], f_dc: [f_dc_0, f_dc_1, f_dc_2], opacity,
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
                for j in 0..7 { sums[best_c][j] += v[j]; }
                counts[best_c] += 1;
            }
            
            for c_idx in 0..actual_k {
                if counts[c_idx] > 0 {
                    for j in 0..7 { centroids[c_idx][j] = sums[c_idx][j] / (counts[c_idx] as f32); }
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
        
        for i in 1..color_k {
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
            let dither_offset = ((seed as i16 - 128) / 512) as i16; // -0.25 à +0.25
            let dithered_idx = (current_idx + dither_offset).clamp(0, color_k as i16 - 1) as u8;
            color_assignments[i] = dithered_idx;
        }
        
        godot_print!("FoveaEngine [Rust] : Palette générée avec {} couleurs.", color_k);

        // 5. Encodage GPU-Ready (16 octets/splat) et écriture binaire
        let header = FoveaAssetHeader {
            magic: *b"FOVEA_3D",
            version: 2,  // Version 2: inclut la palette de couleurs
            splat_count: raw_splats.len() as u32,
            color_codebook_size: color_k as u32,
            covar_codebook_size: actual_k as u32,
            aabb_min, aabb_max,
        };
        
        let header_bytes: &[u8] = unsafe {
            std::slice::from_raw_parts(
                (&header as *const FoveaAssetHeader) as *const u8,
                std::mem::size_of::<FoveaAssetHeader>()
            )
        };
        if out_file.write_all(header_bytes).is_err() { return false; }
        
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
                padding2: 0,
            });
        }
        
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

        // 2. Vérification de sécurité mathématique (Magic Bytes)
        if buffer.len() < 8 || &buffer[0..8] != b"FOVEA_3D" {
            godot_print!("FoveaEngine [Rust Error] : Fichier corrompu ou format invalide !");
            return PackedByteArray::new();
        }

        godot_print!("FoveaEngine [Rust] : Asset chargé en RAM ({} octets). Prêt pour VRAM.", buffer.len());

        let header: FoveaAssetHeader = unsafe { std::ptr::read(buffer.as_ptr() as *const _) };
        let header_size = std::mem::size_of::<FoveaAssetHeader>();
        let palette_size = (header.color_codebook_size as usize) * 12; // 3 floats * 4 bytes
        let covar_size = (header.covar_codebook_size as usize) * 32;
        
        let splats_start = header_size + palette_size + covar_size;

        // 3. On ne renvoie QUE les octets des splats pour le buffer du MultiMesh (Zéro décalage)
        PackedByteArray::from(&buffer[splats_start..])
    }
    
    /// Lit l'en-tête binaire d'un fichier .fovea pour en extraire l'AABB (Bounding Box)
    #[func]
    pub fn get_asset_aabb(path: GString) -> Aabb {
        let path_str = path.to_string();
        let mut file = match File::open(&path_str) {
            Ok(f) => f,
            Err(_) => return Aabb::new(Vector3::ZERO, Vector3::ZERO),
        };

        let mut header_bytes = [0u8; std::mem::size_of::<FoveaAssetHeader>()];
        if file.read_exact(&mut header_bytes).is_err() {
            return Aabb::new(Vector3::ZERO, Vector3::ZERO);
        }

        let header: FoveaAssetHeader = unsafe { std::ptr::read(header_bytes.as_ptr() as *const _) };

        if &header.magic != b"FOVEA_3D" {
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
        if file.read_to_end(&mut buffer).is_err() || buffer.len() < 48 {
            return PackedByteArray::new();
        }

        let header: FoveaAssetHeader = unsafe { std::ptr::read(buffer.as_ptr() as *const _) };
        let header_size = std::mem::size_of::<FoveaAssetHeader>();
        let palette_size = (header.color_codebook_size as usize) * 12;

        if buffer.len() < header_size + palette_size {
            return PackedByteArray::new();
        }

        PackedByteArray::from(&buffer[header_size..header_size + palette_size])
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
        if file.read_to_end(&mut buffer).is_err() || buffer.len() < 48 {
            return PackedByteArray::new();
        }

        let header: FoveaAssetHeader = unsafe { std::ptr::read(buffer.as_ptr() as *const _) };
        let header_size = std::mem::size_of::<FoveaAssetHeader>();
        let palette_size = (header.color_codebook_size as usize) * 12;
        let covar_size = (header.covar_codebook_size as usize) * 32;

        if buffer.len() < header_size + palette_size + covar_size {
            return PackedByteArray::new();
        }

        PackedByteArray::from(&buffer[header_size + palette_size..header_size + palette_size + covar_size])
    }
}