# ⚙️ Reconstruction Setup Guide — FoveaEngine

This guide provides instructions to set up the reconstruction backends (WorldMirror 2.0, DVLT, COLMAP, and monocular STAR/DA3) for the **StudioTo3D** pipeline.

---

## 🖥️ System Requirements & Hardware

| Backend Path | Minimum GPU | Recommended GPU | VRAM | Estimated Time |
|---|---|---|---|---|
| **WorldMirror 2.0** | NVIDIA RTX 3060 | RTX 4070+ (CUDA 12.4) | 8GB - 12GB | ~2 - 10 seconds |
| **DVLT (Déjà View)** | NVIDIA RTX 3080 | RTX 4080+ (CUDA 12.4) | 12GB - 24GB | ~10 - 60 seconds |
| **COLMAP + 3DGS** | NVIDIA GTX 1080 | RTX 3060+ (CUDA 11.8+) | 6GB - 12GB | 30 - 90 minutes |
| **STAR / DA3** | CPU Fallback | RTX 3060 (CUDA 11.8+) | 4GB - 8GB | ~10 - 30 seconds |

---

## 📦 Python Environment Setup

The neural backends (WorldMirror 2.0, DVLT, and WAN 2.1) require a Python virtual environment with CUDA support.

### Option A: Automatic Installation (Recommended)
We provide automated scripts to configure the Python environment and clone dependencies.

#### Windows (PowerShell/cmd)
```cmd
scripts\setup_worldmirror.bat
scripts\setup_diffsynth.bat
```

#### Linux
```bash
bash scripts/setup_worldmirror.sh
bash scripts/setup_diffsynth.sh
```

### Option B: Manual Setup

1. **Create and Activate Virtual Environment**
   ```bash
   python -m venv venv_fovea
   # Windows:
   venv_fovea\Scripts\activate
   # Linux/macOS:
   source venv_fovea/bin/activate
   ```

2. **Install PyTorch (CUDA 12.4 compatibility)**
   ```bash
   pip install torch==2.4.0 torchvision==0.19.0 --index-url https://download.pytorch.org/whl/cu124
   ```

3. **Install Tencent WorldMirror 2.0 (HY-World-2.0)**
   ```bash
   git clone https://github.com/Tencent-Hunyuan/HY-World-2.0
   cd HY-World-2.0
   pip install -r requirements.txt
   ```

4. **Install DiffSynth-Studio & Wan 2.1 (for DVLT & Vista4D backends)**
   ```bash
   pip install diffsynth
   # Install Wan 2.1 dependencies
   pip install sentencepiece transformers
   ```

*Note: The network weights (~5 GB for WorldMirror 2.0; ~28 GB for Wan 2.1) are automatically downloaded from HuggingFace on the first run and cached in `~/.cache/huggingface/hub/`.*

---

## 📹 External Tools Installation

To support video processing and classical Structure-from-Motion (SfM), download FFmpeg and COLMAP.

### 1. FFmpeg (Required for Video Input)
FFmpeg extracts individual image frames from video files.
- **Windows**: Download static builds from [ShareX/FFmpeg Releases](https://github.com/ShareX/FFmpeg/releases). Extract to `C:\ffmpeg`. The key file is `C:\ffmpeg\bin\ffmpeg.exe`.
- **Linux**: Install via package manager: `sudo apt install ffmpeg`.

### 2. COLMAP (Required for Classical Fallback)
COLMAP performs photogrammetric camera pose estimation.
- **Windows**: Download CUDA-enabled builds from [COLMAP Releases](https://github.com/colmap/colmap/releases). Extract to `C:\colmap`. The key file is `C:\colmap\colmap.exe`.
- **Linux**: Install via package manager: `sudo apt install colmap`.

---

## 🛠️ Godot Editor Configuration

Once python and external tools are installed, link them inside the **StudioTo3D Settings panel**:

1. In Godot 4, open `addons/foveacore/scenes/reconstruction/studio_to_3d_panel.tscn` (or find the tab in the editor bottom panel).
2. Scroll to the **Settings** section.
3. Configure the following absolute file paths:
   - **Python Path**: Path to the python interpreter in your venv (e.g. `C:\fovea-engine\venv_fovea\Scripts\python.exe`).
   - **FFmpeg Path**: Path to the executable (e.g. `C:\ffmpeg\bin\ffmpeg.exe` or simply `ffmpeg` if in system PATH).
   - **COLMAP Path**: Path to the executable (e.g. `C:\colmap\colmap.exe` or `colmap`).
4. Click **Check Tools** to run validation diagnostics. If everything is configured correctly, status indicators will turn green.
