use godot::prelude::*;

// Déclaration de nos modules Rust
pub mod fovea_4d_format;
pub mod fovea_fast_path;

// Structure principale représentant notre GDExtension
struct FoveaCoreExtension;

// Enregistrement de l'extension auprès du moteur Godot
#[gdextension]
unsafe impl ExtensionLibrary for FoveaCoreExtension {}
