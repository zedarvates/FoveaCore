# FoveaCore 🔷

[![Python](https://img.shields.io/badge/python-3.11+-blue.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)]()
[![Status](https://img.shields.io/badge/status-active-brightgreen.svg)]()
[![3D](https://img.shields.io/badge/3D-VR-orange.svg)]()

FoveaCore is a next‑generation VR rendering engine that combines structural low‑poly geometry, dynamic Gaussian Splatting, and a procedural neural Style Engine for fluid, expressive, high‑performance VR on accessible hardware.

## Core Innovations

### 🔷 Structural Low-Poly Geometry
- Minimal polygon count without sacrificing visual quality
- Dynamic LOD (Level of Detail) scaling
- Modular geometry system for rapid prototyping

### 🔷 Dynamic Gaussian Splatting
- Real-time point cloud rendering
- Adaptive density control
- Memory-efficient storage and streaming

### 🔷 Neural Style Engine
- Procedural style transfer
- Real-time material generation
- Expressive visual effects

## Architecture

```
FoveaCore
├── Renderer/
│   ├── LowPolyEngine     — Structural geometry pipeline
│   ├── SplatRenderer     — Gaussian splatting engine
│   └── StyleEngine       — Neural style transfer
├── Core/
│   ├── SceneGraph        — 3D scene management
│   ├── MaterialSystem    — Procedural materials
│   └── CameraController  — VR camera controls
└── Integration/
    ├── Hermes MCP        — Agent bridge
    └── ComfyUI           — 3D generation pipeline
```

## Getting Started

```bash
git clone https://github.com/zedarvates/FoveaCore.git
cd FoveaCore
pip install -r requirements.txt
python3 fovea_demo.py
```

## Projets liés

- [hermes-brain](https://github.com/zedarvates/hermes-brain) — Architecture cognitive
- [cogniarc](https://github.com/zedarvates/cogniarc) — ARC-AGI-3 solver
- [ultra-pipeline-framework](https://github.com/zedarvates/ultra-pipeline-framework) — Pipeline DAG
- [StoryCore-Engine](https://github.com/zedarvates/StoryCore-Engine) — Media pipeline

## Licence MIT
