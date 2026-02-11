#!/bin/bash
# Verify GPU encoding/decoding stack

set -e

echo "========================================"
echo "GPU Stack Verification"
echo "========================================"
echo ""

# NVIDIA GPU
echo "1. NVIDIA GPU:"
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=index,name,driver_version,memory.total --format=csv,noheader
    echo ""
else
    echo "  ✗ nvidia-smi not found"
    exit 1
fi

# FFmpeg
echo "2. FFmpeg:"
if command -v ffmpeg &> /dev/null; then
    ffmpeg -version | head -1 | sed 's/^/  /'
    echo ""
else
    echo "  ✗ FFmpeg not found"
    exit 1
fi

# FFmpeg NVENC encoders
echo "3. FFmpeg NVENC Encoders:"
ffmpeg -hide_banner -encoders 2>/dev/null | grep nvenc | sed 's/^/  /' || echo "  ✗ No NVENC encoders"
echo ""

# FFmpeg NVDEC decoders
echo "4. FFmpeg NVDEC Decoders:"
ffmpeg -hide_banner -decoders 2>/dev/null | grep -E "(cuvid|nvdec)" | sed 's/^/  /' || echo "  ✗ No NVDEC decoders"
echo ""

# GStreamer
echo "5. GStreamer:"
if command -v gst-launch-1.0 &> /dev/null; then
    gst-launch-1.0 --version | head -1 | sed 's/^/  /'
    echo ""
else
    echo "  ✗ GStreamer not found"
fi

# GStreamer NVIDIA plugins
echo "6. GStreamer NVIDIA Plugins:"
for plugin in nvh264enc nvh264dec nvh265enc nvh265dec; do
    if gst-inspect-1.0 $plugin &>/dev/null; then
        echo "  ✓ $plugin"
    else
        echo "  ✗ $plugin"
    fi
done
echo ""

# Python
echo "7. Python Libraries:"
python3 << 'EOF'
import sys

packages = {
    'py3nvml': 'py3nvml.py3nvml',
    'numpy': 'numpy',
    'pandas': 'pandas',
    'psutil': 'psutil',
    'matplotlib': 'matplotlib',
}

for name, module in packages.items():
    try:
        mod = __import__(module)
        version = getattr(mod, '__version__', 'unknown')
        print(f'  ✓ {name} {version}')
    except ImportError:
        print(f'  ✗ {name}')

# Test NVML
try:
    import py3nvml.py3nvml as nvml
    nvml.nvmlInit()
    handle = nvml.nvmlDeviceGetHandleByIndex(0)
    name = nvml.nvmlDeviceGetName(handle)
    print(f'  ✓ NVML GPU access: {name}')
    nvml.nvmlShutdown()
except Exception as e:
    print(f'  ✗ NVML: {e}')
EOF

echo ""
echo "========================================"
echo "✓ Verification complete"
echo "========================================"
