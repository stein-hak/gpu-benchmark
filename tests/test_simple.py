#!/usr/bin/env python3
"""
Simple encoding test - quick verification
"""

import subprocess
import time
import re


def test_cpu_encoding():
    """Test CPU x264 encoding (production settings)"""
    print("\n" + "="*70)
    print("CPU x264 Encoding Test (Production Settings)")
    print("="*70)

    # Parameters matching production GStreamer x264enc settings
    cmd = [
        "ffmpeg", "-hide_banner", "-benchmark",
        "-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=24,format=yuv420p",
        "-t", "60",
        "-c:v", "libx264",
        "-refs", "1",                    # ref=1
        "-tune", "zerolatency",          # tune=zerolatency
        "-coder", "0",                   # cabac=false
        "-subq", "4",                    # subme=4
        "-rc-lookahead", "20",           # rc-lookahead=20
        "-mbtree", "1",                  # mb-tree=true
        "-crf", "23",                    # pass=qual (quality mode)
        "-profile:v", "baseline",        # profile=baseline
        "-pix_fmt", "yuv420p",
        "-f", "null", "-"
    ]

    start = time.time()
    result = subprocess.run(cmd, capture_output=True, text=True)
    elapsed = time.time() - start

    # Parse output - get last occurrence for final values
    output = result.stderr
    frame_matches = re.findall(r'frame=\s*(\d+)', output)
    time_matches = re.findall(r'time=(\d{2}):(\d{2}):(\d{2}\.\d+)', output)
    speed_matches = re.findall(r'speed=\s*(\d+\.?\d*)x', output)

    frames = int(frame_matches[-1]) if frame_matches else 0
    if time_matches:
        hours = int(time_matches[-1][0])
        minutes = int(time_matches[-1][1])
        seconds = float(time_matches[-1][2])
        video_time = hours * 3600 + minutes * 60 + seconds
        fps = frames / video_time if video_time > 0 else 0.0
    else:
        fps = 0.0

    speed = float(speed_matches[-1]) if speed_matches else 0.0

    print(f"\nResults:")
    print(f"  Elapsed: {elapsed:.2f}s")
    print(f"  Frames: {frames}")
    print(f"  Avg FPS: {fps:.1f}")
    print(f"  Speed: {speed:.2f}x")
    print(f"  Status: {'✓ PASS' if speed > 1.0 else '✗ FAIL'}")

    return speed > 1.0


def test_gpu_encoding():
    """Test GPU NVENC encoding (production equivalent)"""
    print("\n" + "="*70)
    print("GPU NVENC Encoding Test (Production Equivalent)")
    print("="*70)

    # NVENC parameters equivalent to production x264enc settings
    cmd = [
        "ffmpeg", "-hide_banner", "-benchmark",
        "-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=24,format=yuv420p",
        "-t", "60",
        "-c:v", "h264_nvenc",
        "-preset", "p1",                 # Fastest preset (low latency)
        "-tune", "ll",                   # Low latency (like zerolatency)
        "-profile:v", "baseline",        # Baseline profile
        "-rc", "vbr",                    # Variable bitrate (like CRF)
        "-cq", "23",                     # Quality target (like CRF 23)
        "-refs", "1",                    # ref=1
        "-bf", "0",                      # No B-frames (baseline)
        "-f", "null", "-"
    ]

    start = time.time()
    result = subprocess.run(cmd, capture_output=True, text=True)
    elapsed = time.time() - start

    if result.returncode != 0:
        print(f"\n✗ NVENC not available")
        print(f"Error: {result.stderr[:200]}")
        return False

    # Parse output - get last occurrence for final values
    output = result.stderr
    frame_matches = re.findall(r'frame=\s*(\d+)', output)
    time_matches = re.findall(r'time=(\d{2}):(\d{2}):(\d{2}\.\d+)', output)
    speed_matches = re.findall(r'speed=\s*(\d+\.?\d*)x', output)

    frames = int(frame_matches[-1]) if frame_matches else 0
    if time_matches:
        hours = int(time_matches[-1][0])
        minutes = int(time_matches[-1][1])
        seconds = float(time_matches[-1][2])
        video_time = hours * 3600 + minutes * 60 + seconds
        fps = frames / video_time if video_time > 0 else 0.0
    else:
        fps = 0.0

    speed = float(speed_matches[-1]) if speed_matches else 0.0

    print(f"\nResults:")
    print(f"  Elapsed: {elapsed:.2f}s")
    print(f"  Frames: {frames}")
    print(f"  Avg FPS: {fps:.1f}")
    print(f"  Speed: {speed:.2f}x")
    print(f"  Status: {'✓ PASS' if speed > 5.0 else '✗ FAIL (expected >5x)'}")

    return speed > 5.0


def main():
    """Run simple tests"""
    print("GPU Benchmark - Simple Tests")
    print("="*70)

    # Test 1: CPU encoding
    try:
        cpu_ok = test_cpu_encoding()
    except Exception as e:
        print(f"CPU test failed: {e}")
        cpu_ok = False

    # Test 2: GPU encoding
    try:
        gpu_ok = test_gpu_encoding()
    except Exception as e:
        print(f"GPU test failed: {e}")
        gpu_ok = False

    # Summary
    print("\n" + "="*70)
    print("Test Summary")
    print("="*70)
    print(f"CPU Encoding:  {'✓ PASS' if cpu_ok else '✗ FAIL'}")
    print(f"GPU Encoding:  {'✓ PASS' if gpu_ok else '✗ FAIL (no GPU?)'}")
    print("="*70)

    return cpu_ok and gpu_ok


if __name__ == "__main__":
    import sys
    success = main()
    sys.exit(0 if success else 1)
