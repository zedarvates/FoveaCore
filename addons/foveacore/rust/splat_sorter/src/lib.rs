use glam::{Quat, Vec3A};
use godot::prelude::*;
use rayon::prelude::*;
use std::sync::{Arc, Mutex};

#[derive(GodotClass)]
#[class(init, base=Node3D)]
pub struct SplatSorterRust {
    #[base]
    base: Base<Node3D>,
    splats: Arc<Mutex<Vec<GaussianSplat>>>,
}

#[derive(Clone, Copy, Debug)]
#[repr(C)]
pub struct GaussianSplat {
    pub position: [f32; 3],
    pub rotation: [f32; 4], // Quaternion (x,y,z,w)
    pub scale: [f32; 3],
    pub opacity: f32,
    // Color not needed for sorting
}

#[godot_methods]
impl SplatSorterRust {
    #[func]
    fn sort_back_to_front(&self, camera_pos: Vec3) -> Array<i32> {
        let splats = self.splats.lock().unwrap();
        let n = splats.len();

        if n == 0 {
            return Array::new();
        }

        // Compute squared distances (avoid sqrt for performance)
        let mut indexed: Vec<(usize, f32)> = (0..n)
            .into_par_iter()
            .map(|i| {
                let splat = &splats[i];
                let dx = splat.position[0] - camera_pos.x;
                let dy = splat.position[1] - camera_pos.y;
                let dz = splat.position[2] - camera_pos.z;
                let dist_sq = dx * dx + dy * dy + dz * dz;
                (i, dist_sq)
            })
            .collect();

        // Sort by descending squared distance (far-to-near)
        indexed.par_sort_unstable_by(|a, b| {
            b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal)
        });

        // Extract indices
        let sorted: Array<i32> = indexed.iter().map(|(idx, _)| *idx as i32).collect();

        sorted
    }

    #[func]
    fn set_splats(&mut self, splats: VariantArray) {
        let mut guard = self.splats.lock().unwrap();
        guard.clear();

        for variant in splats.iter_shared() {
            if let Ok(dict) = variant.try_to::<Dictionary>() {
                let pos = dict.get("position")
                    .and_then(|v| v.try_to::<Vector3>().ok())
                    .unwrap_or_default();
                let rot = dict.get("rotation")
                    .and_then(|v| v.try_to::<Quaternion>().ok())
                    .unwrap_or_default();
                let scale = dict.get("scale")
                    .and_then(|v| v.try_to::<Vector3>().ok())
                    .unwrap_or_default();
                let opacity = dict.get("opacity")
                    .and_then(|v| v.try_to::<f32>().ok())
                    .unwrap_or(0.0);

                guard.push(GaussianSplat {
                    position: [pos.x, pos.y, pos.z],
                    rotation: [rot.x, rot.y, rot.z, rot.w],
                    scale: [scale.x, scale.y, scale.z],
                    opacity,
                });
            }
        }
    }
}

// Helper: convert Gd<[...]> to Vec<GaussianSplat> would be done in FFI
