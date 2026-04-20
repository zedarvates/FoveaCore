use godot::prelude::*;

// Déclaration de nos modules Rust
pub mod splatting;

// Structure principale représentant notre GDExtension
struct FoveaCoreExtension;

// Enregistrement de l'extension auprès du moteur Godot
#[gdextension]
unsafe impl ExtensionLibrary for FoveaCoreExtension {}