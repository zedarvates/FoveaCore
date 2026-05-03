# 📦 FoveaEngine Dependencies (StudioTo3D)

For the reconstruction pipeline to work, you must install **FFmpeg** and **COLMAP** on your system.

---

## 📹 1. FFmpeg
Used to extract images from your videos.

### Windows Installation:
1. Download the latest version from **[GitHub ShareX/FFmpeg Releases](https://github.com/ShareX/FFmpeg/releases)**.
2. Extract the archive (e.g., `C:\ffmpeg`).
3. The important file is `bin\ffmpeg.exe`.

---

## 🏛️ 2. COLMAP
Used for photogrammetry (Structure from Motion).

### Windows Installation:
1. Download the Windows version (with CUDA if you have an NVIDIA card) from **[GitHub COLMAP/COLMAP Releases](https://github.com/colmap/colmap/releases)**.
2. Extract the archive (e.g., `C:\colmap`).
3. The important file is `colmap.exe`.

---

## 🧬 3. 3D Gaussian Splatting (Python)
Used for point cloud training.

### Prerequisites:
- Python 3.10+
- CUDA Toolkit 11.8+
- NVIDIA GPU with 8GB+ VRAM recommended.

---

## ⚙️ Configuration in Godot

Once installed, you can configure the paths in the **StudioTo3D** panel of FoveaEngine:

1. Open the **StudioTo3D** panel in the Godot editor.
2. Go to the **Settings** section (at the bottom).
3. Fill in the full paths to your executables:
   - FFmpeg Path: `C:\ffmpeg\bin\ffmpeg.exe`
   - COLMAP Path: `C:\colmap\colmap.exe`

4. Click **Check Tools** to validate that Godot can launch them.

### Tip: Add to PATH
If you add these folders to your Windows `PATH` environment variable, you won't need to specify full paths in Godot. The engine will automatically detect `ffmpeg` and `colmap`.

---

## 🌍 4. WorldMirror 2.0 (Fast Reconstruction)

Replaces COLMAP + 3DGS with a SOTA feed-forward model (Tencent Hunyuan). Video → 3DGS + depth + cameras in ~10 seconds.

### Prerequisites:
- Python 3.10+
- CUDA 12.4 (recommended) or CPU fallback (slow)
- NVIDIA GPU with 8GB+ VRAM recommended
- ~5 GB disk space for the model

### Quick Installation (Windows):
```
scripts\setup_worldmirror.bat
```

### Quick Installation (Linux/macOS):
```
bash scripts/setup_worldmirror.sh
```

### Manual Installation:
```bash
pip install torch==2.4.0 torchvision==0.19.0 --index-url https://download.pytorch.org/whl/cu124
git clone https://github.com/Tencent-Hunyuan/HY-World-2.0
cd HY-World-2.0 && pip install -r requirements.txt
```

The model (~5 GB) is automatically downloaded from HuggingFace on first use.
