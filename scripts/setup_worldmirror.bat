@echo off
REM ============================================================================
REM FoveaEngine — WorldMirror 2.0 Setup Script (Windows)
REM Installe torch + HY-World-2.0 dependencies
REM ============================================================================

echo [FoveaEngine] Setting up WorldMirror 2.0 environment...

REM 1. Check Python
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Python not found. Install Python 3.10+ first.
    exit /b 1
)

REM 2. Install PyTorch (CUDA 12.4)
echo [FoveaEngine] Installing torch==2.4.0+cu124...
pip install torch==2.4.0 torchvision==0.19.0 --index-url https://download.pytorch.org/whl/cu124

if %errorlevel% neq 0 (
    echo WARNING: PyTorch CUDA install failed. Trying CPU-only fallback...
    pip install torch==2.4.0 torchvision==0.19.0
)

REM 3. Clone HY-World-2.0 if not present
if not exist "%~dp0..\deps\HY-World-2.0" (
    echo [FoveaEngine] Cloning HY-World-2.0...
    mkdir "%~dp0..\deps" 2>nul
    git clone https://github.com/Tencent-Hunyuan/HY-World-2.0 "%~dp0..\deps\HY-World-2.0"
    if %errorlevel% neq 0 (
        echo WARNING: git clone failed. Please clone manually.
        echo   git clone https://github.com/Tencent-Hunyuan/HY-World-2.0
    )
)

REM 4. Install hyworld2 dependencies
if exist "%~dp0..\deps\HY-World-2.0\requirements.txt" (
    echo [FoveaEngine] Installing hyworld2 dependencies...
    pip install -r "%~dp0..\deps\HY-World-2.0\requirements.txt"
)

REM 5. Verify
echo [FoveaEngine] Verifying WorldMirror 2.0...
python -c "import hyworld2.worldrecon.pipeline; print('WorldMirror 2.0 OK')" >nul 2>&1
if %errorlevel% equ 0 (
    echo [FoveaEngine] ✅ WorldMirror 2.0 is ready!
) else (
    echo [FoveaEngine] ⚠ hyworld2 module not found. Add to PYTHONPATH:
    echo    set PYTHONPATH=%%PYTHONPATH%%;^<repo_path^>
)

echo [FoveaEngine] Setup complete.
pause
