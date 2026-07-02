"""
FoveaEngine MeshFlow Server — HTTP Bridge between Godot and MeshFlow Inference.

Runs a lightweight FastAPI server that:
  1. Receives a PLY point cloud (exported by FoveaPointCloudExporter in Godot).
  2. Runs MeshFlow (Meta AI, CVPR 2026) inference to generate a clean, manifold 3D mesh.
  3. Decodes multi-resolution LOD meshes (LOD 0 High, LOD 1 Medium, LOD 2 Low/Physics).
  4. Returns a GLTF/GLB bundle to Godot for physics collider and rendering LOD usage.

Modes:
  --serve       Start the HTTP server (default, for Godot integration).
  --process     Process a single PLY file offline (CLI batch mode).
  --dry-run     Use geometric fallback (no model needed, for integration testing).

Usage:
    python meshflow_server.py --serve --port 8000
    python meshflow_server.py --process --input splats.ply --output mesh.glb
    python meshflow_server.py --serve --dry-run

Dependencies:
    pip install fastapi uvicorn numpy trimesh torch
    # For full MeshFlow inference:
    pip install -e path/to/facebookresearch/meshflow
"""

import argparse
import json
import logging
import os
import struct
import sys
import tempfile
import time
from pathlib import Path

import numpy as np

logging.basicConfig(
    level=logging.INFO,
    format="[MeshFlowServer] %(levelname)s — %(message)s"
)
log = logging.getLogger("meshflow_server")

# ─────────────────────────────────────────────────────────────────────────────
#  Dependency Checks
# ─────────────────────────────────────────────────────────────────────────────

def check_meshflow() -> bool:
    try:
        import meshflow  # noqa: F401
        return True
    except ImportError:
        return False

def check_trimesh() -> bool:
    try:
        import trimesh  # noqa: F401
        return True
    except ImportError:
        return False

def check_torch() -> bool:
    try:
        import torch  # noqa: F401
        return True
    except ImportError:
        return False

def check_fastapi() -> bool:
    try:
        import fastapi  # noqa: F401
        import uvicorn  # noqa: F401
        return True
    except ImportError:
        return False


# ─────────────────────────────────────────────────────────────────────────────
#  PLY Loader — Point Cloud from FoveaPointCloudExporter
# ─────────────────────────────────────────────────────────────────────────────

def load_ply_point_cloud(ply_path: str) -> np.ndarray:
    """
    Parse a PLY file exported by FoveaPointCloudExporter (GDScript).
    Supports both ASCII and binary_little_endian formats.
    Returns an (N, 4) array: [x, y, z, opacity].
    """
    with open(ply_path, "rb") as f:
        # Parse header
        header_lines = []
        is_binary = False
        vertex_count = 0
        has_opacity = False

        while True:
            raw = f.readline()
            line = raw.decode("ascii", errors="ignore").strip()
            header_lines.append(line)
            if line.startswith("format binary"):
                is_binary = True
            elif line.startswith("element vertex"):
                vertex_count = int(line.split()[-1])
            elif line == "property float opacity":
                has_opacity = True
            elif line == "end_header":
                break

        log.info(f"PLY: {vertex_count} points, binary={is_binary}, opacity={has_opacity}")

        if vertex_count == 0:
            return np.zeros((0, 4), dtype=np.float32)

        if is_binary:
            # Each vertex: x(f32) y(f32) z(f32) opacity(f32) r(u8) g(u8) b(u8)
            # = 19 bytes
            raw_data = f.read(vertex_count * 19)
            points = np.zeros((vertex_count, 4), dtype=np.float32)
            for i in range(vertex_count):
                offset = i * 19
                x, y, z, opacity = struct.unpack_from("<4f", raw_data, offset)
                points[i] = [x, y, z, opacity]
        else:
            points = np.zeros((vertex_count, 4), dtype=np.float32)
            for i in range(vertex_count):
                parts = f.readline().decode("ascii", errors="ignore").strip().split()
                x, y, z = float(parts[0]), float(parts[1]), float(parts[2])
                opacity = float(parts[3]) if has_opacity and len(parts) > 3 else 1.0
                points[i] = [x, y, z, opacity]

        return points


# ─────────────────────────────────────────────────────────────────────────────
#  MeshFlow Inference Pipeline
# ─────────────────────────────────────────────────────────────────────────────

class MeshFlowPipeline:
    """
    Wraps the facebookresearch/meshflow models (MeshVAE + FlowDiT).
    Provides multi-LOD mesh generation from an input point cloud.
    """

    def __init__(self, checkpoint_dir: str, device: str = "cuda"):
        self.device = device
        self._vae = None
        self._flow_dit = None
        self._ready = False
        self._checkpoint_dir = Path(checkpoint_dir)
        self._load_models()

    def _load_models(self):
        try:
            import torch
            from meshflow.models import MeshVAE, FlowDiT

            log.info(f"Loading MeshVAE from {self._checkpoint_dir}...")
            vae_ckpt = self._checkpoint_dir / "mesh_vae.ckpt"
            if not vae_ckpt.exists():
                log.warning(f"Checkpoint not found: {vae_ckpt}. Inference will use dry-run mode.")
                return

            self._vae = MeshVAE.load_from_checkpoint(str(vae_ckpt))
            self._vae = self._vae.to(self.device).eval()

            log.info(f"Loading FlowDiT from {self._checkpoint_dir}...")
            dit_ckpt = self._checkpoint_dir / "flow_dit.ckpt"
            self._flow_dit = FlowDiT.load_from_checkpoint(str(dit_ckpt))
            self._flow_dit = self._flow_dit.to(self.device).eval()

            self._ready = True
            log.info("MeshFlow pipeline loaded successfully.")
        except Exception as e:
            log.error(f"Failed to load MeshFlow models: {e}")
            self._ready = False

    @property
    def is_ready(self) -> bool:
        return self._ready

    def generate(self, points: np.ndarray, num_steps: int = 25) -> dict:
        """
        Runs MeshFlow point-cloud-conditioned generation.
        Returns a dict with keys 'lod0', 'lod1', 'lod2' each containing
        a dict {'vertices': np.ndarray, 'faces': np.ndarray}.
        """
        import torch

        # Sub-sample or pad to 32768 points (required by shape encoder)
        target_n = 32768
        if len(points) > target_n:
            idx = np.random.choice(len(points), target_n, replace=False)
            pts_in = points[idx, :3]
        elif len(points) < target_n:
            # Pad by repeating existing points
            pad_idx = np.random.choice(len(points), target_n - len(points), replace=True)
            pts_in = np.vstack([points[:, :3], points[pad_idx, :3]])
        else:
            pts_in = points[:, :3]

        pts_tensor = torch.from_numpy(pts_in.astype(np.float32)).unsqueeze(0).to(self.device)

        with torch.no_grad():
            # Point cloud conditioning → latent code
            latent = self._flow_dit.generate(pts_tensor, steps=num_steps)

            # Decode at three resolution levels using TokenSplit hierarchy
            lod0 = self._decode_lod(latent, resolution="high")    # Full detail
            lod1 = self._decode_lod(latent, resolution="medium")  # Mid detail (rendering far)
            lod2 = self._decode_lod(latent, resolution="low")     # Very low (physics collider)

        return {"lod0": lod0, "lod1": lod1, "lod2": lod2}

    def _decode_lod(self, latent, resolution: str) -> dict:
        """Decode a mesh from the latent code at the specified resolution."""
        import torch
        mesh_data = self._vae.decode(latent, target_resolution=resolution)

        # MeshVAE returns (vertices, faces, validity_mask)
        verts = mesh_data["vertices"][0].cpu().numpy()  # (V, 3)
        faces = mesh_data["faces"][0].cpu().numpy()     # (F, 3)

        # Filter invalid faces using validity mask if provided
        if "validity" in mesh_data:
            valid = mesh_data["validity"][0].cpu().numpy().astype(bool)
            faces = faces[valid[:len(faces)]] if len(valid) >= len(faces) else faces

        return {"vertices": verts, "faces": faces}


# ─────────────────────────────────────────────────────────────────────────────
#  Geometric Fallback (dry-run mode — no model required)
# ─────────────────────────────────────────────────────────────────────────────

def generate_geometric_fallback(points: np.ndarray) -> dict:
    """
    Fallback when MeshFlow is not available.
    Uses convex hull + voxel decimation to generate approximate LOD meshes.
    Requires trimesh.
    """
    import trimesh

    pts = points[:, :3]
    center = pts.mean(axis=0)
    pts_centered = pts - center

    lod_meshes = {}
    for lod_id, resolution in enumerate(["high", "medium", "low"]):
        # Subsample for each LOD level
        factors = {"high": 1.0, "medium": 0.3, "low": 0.08}
        n = max(10, int(len(pts_centered) * factors[resolution]))
        idx = np.random.choice(len(pts_centered), min(n, len(pts_centered)), replace=False)
        sampled = pts_centered[idx]

        try:
            hull = trimesh.convex.convex_hull(sampled)
            verts = hull.vertices + center
            faces = hull.faces
        except Exception:
            # Extremely degenerate case: return a box
            bb = trimesh.primitives.Box(extents=np.ptp(pts_centered, axis=0) + 0.01)
            verts = bb.vertices + center
            faces = bb.faces

        lod_name = f"lod{lod_id}"
        lod_meshes[lod_name] = {"vertices": verts, "faces": faces}

    return lod_meshes


# ─────────────────────────────────────────────────────────────────────────────
#  GLTF/GLB Exporter
# ─────────────────────────────────────────────────────────────────────────────

def export_lods_to_glb(lod_meshes: dict, output_path: str) -> bool:
    """
    Pack LOD meshes into a single GLB file.
    Each LOD is a separate mesh node named 'LOD_0', 'LOD_1', 'LOD_2'.
    """
    try:
        import trimesh
        from trimesh.exchange.gltf import export_glb

        scene = trimesh.Scene()
        for lod_name, mesh_data in lod_meshes.items():
            verts = mesh_data["vertices"]
            faces = mesh_data["faces"]
            if len(verts) < 3 or len(faces) < 1:
                continue
            tm = trimesh.Trimesh(vertices=verts, faces=faces, process=True)
            node_name = lod_name.upper().replace("LOD", "LOD_")  # lod0 → LOD_0
            scene.add_geometry(tm, node_name=node_name)

        glb_bytes = export_glb(scene)
        with open(output_path, "wb") as f:
            f.write(glb_bytes)

        log.info(f"GLB exported to {output_path} ({len(glb_bytes)//1024} KB)")
        return True
    except Exception as e:
        log.error(f"GLB export failed: {e}")
        return False


# ─────────────────────────────────────────────────────────────────────────────
#  Core Processing Function
# ─────────────────────────────────────────────────────────────────────────────

def process_ply_to_glb(
    ply_path: str,
    output_path: str,
    pipeline: "MeshFlowPipeline | None",
    dry_run: bool = False
) -> dict:
    """
    Main processing function: PLY → LOD meshes → GLB.
    Returns a result dict with 'success', 'elapsed_s', 'lod_stats'.
    """
    t0 = time.time()

    # 1. Load point cloud
    points = load_ply_point_cloud(ply_path)
    if len(points) == 0:
        return {"success": False, "error": "Empty point cloud", "elapsed_s": 0}
    log.info(f"Loaded {len(points)} points from {Path(ply_path).name}")

    # 2. Generate LOD meshes
    if not dry_run and pipeline is not None and pipeline.is_ready:
        log.info("Running MeshFlow inference...")
        lod_meshes = pipeline.generate(points)
    else:
        if not dry_run:
            log.warning("MeshFlow model not ready. Falling back to geometric convex hull.")
        else:
            log.info("Dry-run mode: using geometric convex hull fallback.")
        lod_meshes = generate_geometric_fallback(points)

    # 3. Export GLB
    ok = export_lods_to_glb(lod_meshes, output_path)

    elapsed = round(time.time() - t0, 3)
    lod_stats = {
        name: {
            "vertices": len(m["vertices"]),
            "faces": len(m["faces"])
        }
        for name, m in lod_meshes.items()
    }

    return {
        "success": ok,
        "output": str(output_path),
        "elapsed_s": elapsed,
        "point_count": len(points),
        "lod_stats": lod_stats,
        "mode": "dry_run" if dry_run else ("meshflow" if pipeline and pipeline.is_ready else "geometric_fallback")
    }


# ─────────────────────────────────────────────────────────────────────────────
#  HTTP Server (FastAPI)
# ─────────────────────────────────────────────────────────────────────────────

def build_app(pipeline, dry_run: bool, output_dir: Path):
    """Build and return the FastAPI application."""
    try:
        from fastapi import FastAPI, File, UploadFile, HTTPException
        from fastapi.responses import FileResponse
    except ImportError:
        log.error("FastAPI not installed. Run: pip install fastapi uvicorn")
        sys.exit(1)

    app = FastAPI(
        title="FoveaEngine MeshFlow Server",
        description="HTTP bridge: PLY point cloud → MeshFlow inference → LOD GLB bundle",
        version="1.0.0"
    )

    @app.get("/health")
    def health():
        return {
            "status": "ok",
            "model_ready": pipeline.is_ready if pipeline else False,
            "dry_run": dry_run,
            "trimesh_available": check_trimesh(),
        }

    @app.post("/process")
    async def process_point_cloud(file: UploadFile = File(...)):
        """
        Accepts a PLY point cloud upload, runs MeshFlow inference,
        and returns the resulting GLB bundle with LOD 0/1/2 meshes.
        """
        if not file.filename.endswith(".ply"):
            raise HTTPException(status_code=400, detail="Only .ply files are accepted.")

        # Save upload to a temp file
        with tempfile.NamedTemporaryFile(suffix=".ply", delete=False) as tmp:
            content = await file.read()
            tmp.write(content)
            tmp_ply_path = tmp.name

        try:
            # Generate a stable output path based on filename
            stem = Path(file.filename).stem
            output_glb = output_dir / f"{stem}_meshflow.glb"

            result = process_ply_to_glb(
                ply_path=tmp_ply_path,
                output_path=str(output_glb),
                pipeline=pipeline,
                dry_run=dry_run
            )

            if not result["success"]:
                raise HTTPException(status_code=500, detail=result.get("error", "Processing failed"))

            log.info(f"Processed '{file.filename}' → {output_glb.name} in {result['elapsed_s']}s")
            log.info(f"  LOD stats: {json.dumps(result['lod_stats'])}")

            # Return GLB file directly
            return FileResponse(
                path=str(output_glb),
                media_type="model/gltf-binary",
                filename=output_glb.name,
                headers={
                    "X-MeshFlow-Mode": result["mode"],
                    "X-MeshFlow-Points": str(result["point_count"]),
                    "X-MeshFlow-Elapsed": str(result["elapsed_s"]),
                }
            )
        finally:
            os.unlink(tmp_ply_path)

    @app.get("/status")
    def status():
        """Returns server configuration and model readiness."""
        return {
            "server": "FoveaEngine MeshFlow Server v1.0",
            "model_ready": pipeline.is_ready if pipeline else False,
            "dry_run": dry_run,
            "output_dir": str(output_dir),
            "meshflow_installed": check_meshflow(),
            "trimesh_installed": check_trimesh(),
            "torch_installed": check_torch(),
        }

    return app


# ─────────────────────────────────────────────────────────────────────────────
#  CLI Entry Point
# ─────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="FoveaEngine MeshFlow Server — HTTP bridge for PLY→GLB mesh generation"
    )
    subparsers = parser.add_subparsers(dest="command", help="Mode")

    # --serve
    serve_p = subparsers.add_parser("serve", help="Start HTTP server for Godot integration")
    serve_p.add_argument("--port", type=int, default=8000, help="HTTP port (default: 8000)")
    serve_p.add_argument("--host", default="127.0.0.1", help="Bind address (default: 127.0.0.1)")
    serve_p.add_argument("--checkpoint-dir", default="./meshflow_checkpoints",
                         help="Path to MeshFlow model checkpoints directory")
    serve_p.add_argument("--output-dir", default="./meshflow_outputs",
                         help="Directory for generated GLB files")
    serve_p.add_argument("--device", default="cuda", help="PyTorch device (cuda or cpu)")
    serve_p.add_argument("--dry-run", action="store_true",
                         help="Use geometric fallback (no MeshFlow model required)")

    # --process
    proc_p = subparsers.add_parser("process", help="Offline batch processing (CLI)")
    proc_p.add_argument("--input", required=True, help="Input PLY file path")
    proc_p.add_argument("--output", required=True, help="Output GLB file path")
    proc_p.add_argument("--checkpoint-dir", default="./meshflow_checkpoints")
    proc_p.add_argument("--device", default="cuda")
    proc_p.add_argument("--dry-run", action="store_true")

    args = parser.parse_args()

    if args.command is None:
        parser.print_help()
        sys.exit(1)

    # Check trimesh (required for GLB export)
    if not check_trimesh():
        log.error("trimesh not installed. Run: pip install trimesh")
        sys.exit(1)

    # Determine if dry-run
    dry_run = args.dry_run

    # Load MeshFlow pipeline (or None for dry-run)
    pipeline = None
    if not dry_run:
        if not check_meshflow():
            log.warning("MeshFlow package not installed. Falling back to geometric convex hull.")
            log.warning("  Install: pip install -e path/to/facebookresearch/meshflow")
            dry_run = True
        else:
            pipeline = MeshFlowPipeline(
                checkpoint_dir=args.checkpoint_dir,
                device=args.device
            )
            if not pipeline.is_ready:
                log.warning("MeshFlow model not ready. Falling back to geometric convex hull.")

    if args.command == "serve":
        if not check_fastapi():
            log.error("FastAPI/uvicorn not installed. Run: pip install fastapi uvicorn")
            sys.exit(1)

        output_dir = Path(args.output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        app = build_app(pipeline, dry_run, output_dir)

        import uvicorn
        mode_str = "DRY-RUN (geometric fallback)" if dry_run else (
            "MESHFLOW INFERENCE" if pipeline and pipeline.is_ready else "GEOMETRIC FALLBACK"
        )
        log.info(f"Starting MeshFlow Server — Mode: {mode_str}")
        log.info(f"Endpoint: http://{args.host}:{args.port}/process")
        log.info(f"Output dir: {output_dir.resolve()}")
        uvicorn.run(app, host=args.host, port=args.port, log_level="info")

    elif args.command == "process":
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)

        result = process_ply_to_glb(
            ply_path=args.input,
            output_path=str(output_path),
            pipeline=pipeline,
            dry_run=dry_run
        )

        print(json.dumps(result, indent=2))
        sys.exit(0 if result["success"] else 1)


if __name__ == "__main__":
    main()
