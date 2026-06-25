#!/bin/bash
# Script de compilation du module Rust FoveaCore vers WebAssembly (WASM) via Emscripten
# Cible : Godot Web Export (wasm32-unknown-emscripten)

echo "=== Compilant FoveaCore Rust vers WebAssembly (Emscripten) ==="

# S'assurer que la cible wasm32-unknown-emscripten est installée
rustup target add wasm32-unknown-emscripten

# Activer les optimisations de taille et vitesse pour le web
export RUSTFLAGS="-C opt-level=z -C codegen-units=1"

# Lancer la compilation cargo en mode release
cargo build --target wasm32-unknown-emscripten --release

echo "=== Compilation WASM terminée ! ==="
