@echo off
REM ============================================================================
REM FoveaEngine — DiffSynth-Studio Unified Setup (Windows)
REM Installs DiffSynth + dependencies for WorldMirror 2.0, Vista4D, AnyRecon
REM ============================================================================

echo [FoveaEngine] Setting up DiffSynth-Studio ecosystem...

REM 1. Check Python
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Python 3.10+ required.
    exit /b 1
)

REM 2. Install PyTorch (CUDA 12.4)
echo [FoveaEngine] Installing PyTorch (CUDA 12.4)...
pip install torch==2.4.0 torchvision==0.19.0 --index-url https://download.pytorch.org/whl/cu124
if %errorlevel% neq 0 (
    echo WARNING: CUDA PyTorch failed. Trying CPU-only...
    pip install torch==2.4.0 torchvision==0.19.0
)

REM 3. Install DiffSynth-Studio
echo [FoveaEngine] Installing DiffSynth-Studio...
pip install diffsynth
if %errorlevel% neq 0 (
    echo WARNING: diffsynth install failed. Try pip install diffsynth --pre
)

REM 4. Install Flash Attention (optional)
echo [FoveaEngine] Attempting Flash Attention install...
pip install flash-attn --no-build-isolation 2>nul || echo WARNING: Flash Attention skipped

REM 5. Setup WorldMirror 2.0
if exist "%~dp0setup_worldmirror.bat" (
    echo [FoveaEngine] Running WorldMirror 2.0 setup...
    call "%~dp0setup_worldmirror.bat"
)

REM 6. Verify
echo [FoveaEngine] Verifying DiffSynth...
python -c "import diffsynth; print('DiffSynth-Studio OK')" >nul 2>&1 && echo ✅ DiffSynth ready || echo ⚠ DiffSynth not found

echo.
echo [FoveaEngine] Setup complete.
echo   Next: pip install -r requirements_worldmirror.txt
echo   Bridge: python diffsynth_bridge.py --backend worldmirror2 --input frames/ --output output/
pause
