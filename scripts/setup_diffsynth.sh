#!/bin/bash
# ============================================================================
# FoveaEngine — DiffSynth-Studio Unified Setup (Linux/macOS)
# Installs DiffSynth + dependencies for WorldMirror 2.0, Vista4D, AnyRecon
# ============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_DIR="$SCRIPT_DIR/../deps"

echo "[FoveaEngine] Setting up DiffSynth-Studio ecosystem..."

# 1. Check Python + CUDA
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3.10+ required."
    exit 1
fi

# 2. Install PyTorch (CUDA 12.4 recommended, CPU fallback)
echo "[FoveaEngine] Installing PyTorch (CUDA 12.4)..."
pip install torch==2.4.0 torchvision==0.19.0 --index-url https://download.pytorch.org/whl/cu124 || {
    echo "WARNING: CUDA PyTorch failed. Trying CPU-only..."
    pip install torch==2.4.0 torchvision==0.19.0
}

# 3. Install DiffSynth-Studio
echo "[FoveaEngine] Installing DiffSynth-Studio..."
pip install diffsynth

# 4. Install Flash Attention (optional, for Vista4D)
echo "[FoveaEngine] Installing Flash Attention (may take a while)..."
pip install flash-attn --no-build-isolation 2>/dev/null || {
    echo "WARNING: Flash Attention skipped (standard attention fallback)"
}

# 5. Setup WorldMirror 2.0
if [ -f "$SCRIPT_DIR/setup_worldmirror.sh" ]; then
    echo "[FoveaEngine] Running WorldMirror 2.0 setup..."
    bash "$SCRIPT_DIR/setup_worldmirror.sh"
fi

# 6. Verify
echo "[FoveaEngine] Verifying DiffSynth..."
python3 -c "import diffsynth; print('DiffSynth-Studio OK')" 2>/dev/null && echo "✅ DiffSynth ready" || echo "⚠ DiffSynth not found"

echo "[FoveaEngine] Setup complete."
echo "  Next: pip install -r requirements_worldmirror.txt (if not already done)"
echo "  Bridge: python diffsynth_bridge.py --backend worldmirror2 --input frames/ --output output/"
