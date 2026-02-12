# GPU Benchmark Suite

Comprehensive Docker environment for benchmarking NVIDIA GPU encoding performance and comparing cloud/bare-metal server capabilities:
- **GPU Encoding**: NVIDIA NVENC/NVDEC hardware acceleration testing
- **CPU vs GPU**: Compare software vs hardware encoding performance
- **Parallel Streams**: Test maximum simultaneous encoding capacity
- **CPU**: Sysbench multi-threaded performance tests
- **Network**: Speedtest download/upload/latency
- **Stress Testing**: stress-ng CPU stress tests

## Features

- **Multi-stage Docker build** optimized for size (~8GB final image)
- **NVIDIA NVENC/NVDEC** hardware encoding/decoding support
- **FFmpeg 6.0** with CUDA support (H.264, HEVC, AV1)
- **GStreamer 1.20** with nvcodec plugin
- **Python GI bindings** for GStreamer pipeline testing
- **Parallel stream testing** to find GPU capacity limits
- **Production-equivalent encoding tests** with realistic parameters
- **Automated benchmarking** with JSON output

---

## Quick Start

### Prerequisites

- NVIDIA GPU (Maxwell or newer)
- NVIDIA Driver 525+
- Docker + Docker Compose V2
- NVIDIA Container Toolkit

### 1. Build and Run

**Option A: Use Pre-built Image (Fast)** ⭐ Recommended

```bash
# Clone repository
git clone https://github.com/stein-hak/gpu-benchmark.git
cd gpu-benchmark

# Copy config (uses steinhak/gpu-benchmark:latest by default)
cp .env.example .env

# Pull and run
make pull
make up
```

**Option B: Build Locally (Slower)**

```bash
# Clone repository
git clone https://github.com/stein-hak/gpu-benchmark.git
cd gpu-benchmark

# Quick build script
./build.sh

# Or manual
docker compose build
docker compose up -d
```

### 2. Verify Installation

```bash
# Using make
make verify

# Or manually
docker compose exec gpu-benchmark verify-stack
```

### 3. Run Tests

```bash
# Simple test
docker compose exec gpu-benchmark python3 tests/test_simple.py

# Enter container for manual tests
make shell
```

---

## Project Structure

```
gpu-benchmark/
├── Dockerfile              # Multi-stage build
├── docker-compose.yml      # Container config
├── Makefile               # Convenience commands
├── build.sh               # Quick setup script
├── requirements.txt       # Python dependencies
├── .dockerignore          # Build exclusions
├── .gitignore            # Git exclusions
├── scripts/
│   ├── verify-stack.sh   # Verify components
│   └── info.sh           # System information
├── tests/
│   ├── __init__.py
│   └── test_simple.py    # Basic CPU/GPU test
└── results/              # Test outputs (created automatically)
```

---

## Server Benchmarking

### Quick Benchmark

```bash
# Run full benchmark (CPU + Network)
make benchmark

# Or inside container
docker compose exec gpu-benchmark benchmark
```

**Output includes:**
- CPU model, architecture, cores
- Sysbench single-thread, multi-thread, hyperthreading tests
- Network download/upload speed and latency
- JSON report saved to `results/benchmark_YYYYMMDD_HHMMSS.json`

### Stress Testing

```bash
# 60-second stress test
make benchmark-stress

# 5-minute stress test
make benchmark-stress-long

# Custom duration (inside container)
docker compose exec gpu-benchmark benchmark --stress 120
```

**Stress test:**
- Uses 100% CPU on all cores
- Measures sustained performance under load
- Useful for thermal throttling detection
- Outputs bogo ops and ops/sec

### Example Output

```
========================================
  Server Benchmark Suite
========================================

[1/4] Gathering CPU Information...
  CPU Model: Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz
  Architecture: x86_64
  Physical Cores: 8
  Threads: 16
  Current MHz: 2394.374
  Max MHz: 3300.0000
  L3 Cache: 35840 KiB

[2/4] Running Sysbench CPU Benchmark...
  Test: Prime numbers up to 20000
  Threads: 1, 8, 16

  → Single thread...
    Events/sec: 842.45
    Avg latency: 1.19ms

  → 8 threads (all cores)...
    Events/sec: 6234.78
    Avg latency: 1.28ms

  → 16 threads (with HT)...
    Events/sec: 11453.12
    Avg latency: 1.40ms

[3/4] Running Network Speed Test...
  Download: 945.23 Mbps
  Upload: 892.15 Mbps
  Ping: 3.45 ms

[4/4] Stress Test SKIPPED
  Run with --stress or -s to enable

========================================
  Benchmark Complete!
========================================

Results saved to: results/benchmark_20260210_143022.json
```

### Benchmark Results JSON

```json
{
  "timestamp": "2026-02-10T14:30:22+00:00",
  "hostname": "benchmark-server",
  "cpu": {
    "model": "Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz",
    "architecture": "x86_64",
    "cores": 8,
    "threads": 16,
    "current_mhz": "2394.374",
    "max_mhz": "3300.0000",
    "l3_cache": "35840 KiB"
  },
  "sysbench": {
    "single_thread": {
      "events_per_sec": 842.45,
      "avg_latency_ms": 1.19
    },
    "all_cores": {
      "threads": 8,
      "events_per_sec": 6234.78,
      "avg_latency_ms": 1.28
    },
    "hyperthreading": {
      "threads": 16,
      "events_per_sec": 11453.12,
      "avg_latency_ms": 1.40
    }
  },
  "network": {
    "download_mbps": 945.23,
    "upload_mbps": 892.15,
    "ping_ms": 3.45
  },
  "stress_test": null
}
```

---

## Docker Hub Integration

### Publishing Images (For Maintainers)

```bash
# 1. Login to Docker Hub
docker login

# 2. Configure image name
cp .env.example .env
# Edit .env:
#   DOCKER_HUB_USER=your-username
#   IMAGE_NAME=your-username/gpu-benchmark
#   IMAGE_TAG=latest

# 3. Build and push
make build-and-push

# Or push specific tag
IMAGE_TAG=v1.0.0 make build-and-push
```

### Using Pre-built Images (For Users)

```bash
# 1. Configure
cp .env.example .env
# Edit .env:
#   IMAGE_NAME=your-username/gpu-benchmark
#   BUILD_MODE=pull

# 2. Pull and run
make pull
make up
```

**Benefits:**
- ✅ 10x faster deployment (no 20min build)
- ✅ Consistent environment across servers
- ✅ Perfect for cloud benchmarking multiple providers
- ✅ CI/CD friendly

---

## Available Commands

### Make targets:

```bash
make help                   # Show all commands

# Image Management
make build                  # Build Docker image locally
make pull                   # Pull pre-built image from Docker Hub
make push                   # Push image to Docker Hub
make build-and-push         # Build and push in one command

# Container Operations
make up                     # Start container
make down                   # Stop container
make shell                  # Enter container bash
make logs                   # Show container logs

# Benchmarking
make benchmark              # Run CPU + Network benchmark
make benchmark-stress       # Run benchmark with 60s stress test
make benchmark-stress-long  # Run benchmark with 300s stress test

# GPU Testing
make verify                 # Verify GPU stack (FFmpeg, GStreamer, NVENC)
make info                   # Show system info
make test                   # Run CPU vs GPU encoding tests (60s)
make test-parallel          # Test maximum parallel NVENC streams

# Maintenance
make clean                  # Clean results
make rebuild                # Rebuild from scratch
```

### Manual commands:

```bash
# Build
docker compose build

# Start
docker compose up -d

# Stop
docker compose down

# Shell
docker compose exec gpu-benchmark bash

# Run command
docker compose exec gpu-benchmark <command>
```

---

## Use Cases

### Compare Cloud Providers

Benchmark different cloud providers to find best performance/price:

```bash
# Deploy to multiple providers
# Provider A
ssh user@provider-a
git clone <repo> && cd gpu-benchmark
./build.sh
make benchmark > provider-a-results.txt

# Provider B
ssh user@provider-b
git clone <repo> && cd gpu-benchmark
./build.sh
make benchmark > provider-b-results.txt

# Compare results
diff provider-a-results.txt provider-b-results.txt
```

### Detect Overselling

Check if cloud provider is overselling CPU:

```bash
# Run stress test to check sustained performance
make benchmark-stress-long

# Compare stress test results with quick benchmark
# If stress results are much worse → possible overselling/throttling
```

### Bare Metal vs Cloud

```bash
# Bare metal
make benchmark-stress

# Cloud instance
make benchmark-stress

# Compare:
# - Single-thread performance (CPU quality)
# - Multi-thread scaling (core isolation)
# - Stress test stability (throttling detection)
```

### Network Quality Testing

```bash
# Test network quality for video streaming/recording
make benchmark

# Check results/benchmark_*.json
# Look for:
# - download_mbps > 500 for HD video upload
# - upload_mbps > 100 for streaming
# - ping_ms < 50 for real-time apps
```

---

## Manual Testing

### Inside container:

```bash
# Enter container
make shell

# Verify stack
verify-stack

# System info
info

# FFmpeg CPU test
ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=24,format=rgb24 -t 10 \
  -c:v libx264 -preset veryfast -tune zerolatency -crf 23 \
  -f null -

# FFmpeg GPU test (NVENC)
ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=24 -t 10 \
  -c:v h264_nvenc -preset p1 -tune ll -b:v 5M \
  -f null -

# GStreamer test
gst-launch-1.0 videotestsrc num-buffers=240 ! \
  video/x-raw,width=1920,height=1080,framerate=24/1 ! \
  nvh264enc ! fakesink

# Monitor GPU
watch -n 1 nvidia-smi
```

---

## Test with Project Settings

### CPU x264 (project equivalent):

```bash
# Without preset (like project)
ffmpeg -hide_banner -benchmark \
  -f lavfi -i "testsrc2=size=1920x1080:rate=24,format=rgb24" -t 60 \
  -c:v libx264 \
  -tune zerolatency \
  -refs 1 \
  -coder 0 \
  -subq 4 \
  -rc-lookahead 20 \
  -mbtree 1 \
  -crf 23 \
  -profile:v baseline \
  -pix_fmt yuv420p \
  -threads 2 \
  output-cpu.mp4

# Expected: speed ~1.4-1.5x
```

### CPU x264 with veryfast preset:

```bash
ffmpeg -hide_banner -benchmark \
  -f lavfi -i "testsrc2=size=1920x1080:rate=24,format=rgb24" -t 60 \
  -c:v libx264 \
  -preset veryfast \
  -tune zerolatency \
  -refs 1 \
  -coder 0 \
  -subq 4 \
  -rc-lookahead 20 \
  -mbtree 1 \
  -crf 23 \
  -profile:v baseline \
  -pix_fmt yuv420p \
  -threads 2 \
  output-cpu-veryfast.mp4

# Expected: speed ~1.9-2.0x (33% faster!)
```

### GPU NVENC:

```bash
ffmpeg -hide_banner -benchmark \
  -f lavfi -i "testsrc2=size=1920x1080:rate=24,format=rgb24" -t 60 \
  -c:v h264_nvenc \
  -preset p1 \
  -tune ll \
  -rc cbr \
  -b:v 5M \
  output-gpu.mp4

# Expected: speed >20x
```

---

## Performance Expectations

Based on Tesla T4 / V100:

| Method | Speed | CPU Usage | GPU Usage | Capacity (8 cores) |
|--------|-------|-----------|-----------|-------------------|
| **CPU (no preset)** | 1.44x | ~70% per task | 0% | ~11 tasks |
| **CPU (veryfast)** | 1.92x | ~60% per task | 0% | ~15 tasks |
| **CPU (ultrafast)** | 2.15x | ~50% per task | 0% | ~17 tasks |
| **GPU (NVENC)** | 20-30x | ~5% per task | ~60% | ~30 tasks |

---

## Troubleshooting

### GPU not detected

```bash
# Check NVIDIA driver
nvidia-smi

# Check Docker GPU access
docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi

# Check container GPU
docker compose exec gpu-benchmark nvidia-smi
```

### NVENC not available

```bash
# Check FFmpeg encoders
docker compose exec gpu-benchmark ffmpeg -encoders 2>/dev/null | grep nvenc

# Check GStreamer plugins
docker compose exec gpu-benchmark gst-inspect-1.0 nvh264enc
```

### Build errors

```bash
# Clean rebuild
make rebuild

# Check Docker logs
make logs
```

---

## GPU Testing Examples

### Verify NVENC Stack

```bash
make verify
```

Output shows:
- GPU detection
- FFmpeg NVENC encoders (H.264, HEVC, AV1)
- GStreamer nvcodec plugins
- Python library availability

### Run Encoding Performance Tests

```bash
# CPU vs GPU comparison (60 seconds each)
make test
```

Tests both CPU (x264) and GPU (NVENC) encoding with production-equivalent settings:
- 1080p @ 24fps
- Baseline profile
- Low latency tuning
- Shows speed multiplier (e.g., 28x realtime)

### Test Maximum Parallel Streams

```bash
# Find GPU capacity limit
make test-parallel
```

Progressively tests 1, 2, 4, 8, 12... parallel NVENC streams until failure.
Example output:
```
Maximum realtime streams: 8

Streams    Success    Avg Speed    Min Speed    Status
----------------------------------------------------------------------
1          1/1         9.58x        9.58x      ✓ PASS
2          2/2         7.46x        7.31x      ✓ PASS
4          4/4         5.98x        5.76x      ✓ PASS
8          8/8         3.27x        3.13x      ✓ PASS
12         8/12        2.63x        2.43x      ✗ FAIL
```

---

## Image Size

- **Builder stage**: ~8GB (with build tools)
- **Runtime stage**: ~2GB (runtime only)
- **Savings**: 75% reduction

---

## License

MIT License - Free to use for benchmarking cloud and bare-metal GPU servers.

---

## Useful Links

- [NVIDIA NVENC Documentation](https://developer.nvidia.com/nvidia-video-codec-sdk)
- [FFmpeg NVENC Guide](https://trac.ffmpeg.org/wiki/HWAccelIntro)
- [GStreamer nvcodec Plugin](https://gstreamer.freedesktop.org/documentation/nvcodec/)
