#!/bin/bash
# ============================================================================
# FoveaEngine — WorldMirror 2.0 Setup Script (Linux/macOS)
# Installe torch + HY-World-2.0 dependencies
# ============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_DIR="$SCRIPT_DIR/../deps"

echo "[FoveaEngine] Setting up WorldMirror 2.0 environment..."

# 1. Check Python
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python not found. Install Python 3.10+ first."
    exit 1
fi

# 2. Install PyTorch (CUDA 12.4)
echo "[FoveaEngine] Installing torch==2.4.0+cu124..."
pip install torch==2.4.0 torchvision==0.19.0 --index-url https://download.pytorch.org/whl/cu124 || {
    echo "WARNING: PyTorch CUDA install failed. Trying CPU-only fallback..."
    pip install torch==2.4.0 torchvision==0.19.0
}

# 3. Clone HY-World-2.0 if not present
if [ ! -d "$DEPS_DIR/HY-World-2.0" ]; then
    echo "[FoveaEngine] Cloning HY-World-2.0..."
    mkdir -p "$DEPS_DIR"
    git clone https://github.com/Tencent-Hunyuan/HY-World-2.0 "$DEPS_DIR/HY-World-2.0" || {
        echo "WARNING: git clone failed. Please clone manually."
        echo "  git clone https://github.com/Tencent-Hunyuan/HY-World-2.0"
    }
fi

# 4. Install hyworld2 dependencies
if [ -f "$DEPS_DIR/HY-World-2.0/requirements.txt" ]; then
    echo "[FoveaEngine] Installing hyworld2 dependencies..."
    pip install -r "$DEPS_DIR/HY-World-2.0/requirements.txt"
fi

# 5. Verify
echo "[FoveaEngine] Verifying WorldMirror 2.0..."
if python3 -c "import hyworld2.worldrecon.pipeline; print('WorldMirror 2.0 OK')" 2>/dev/null; then
    echo "[FoveaEngine] ✅ WorldMirror 2.0 is ready!"
else
    echo "[FoveaEngine] ⚠ hyworld2 module not found. Add to PYTHONPATH:"
    echo "   export PYTHONPATH=\$PYTHONPATH:<repo_path>"
fi

echo "[FoveaEngine] Setup complete."
