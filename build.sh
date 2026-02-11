#!/bin/bash
# Quick build and run script

set -e

echo "Building GPU Benchmark Docker image..."
docker compose build

echo ""
echo "Starting container..."
docker compose up -d

echo ""
echo "Waiting for container to start..."
sleep 2

echo ""
echo "Verifying GPU stack..."
docker compose exec gpu-benchmark verify-stack

echo ""
echo "="
echo "Container is ready!"
echo ""
echo "Available commands:"
echo "  make shell    - Enter container"
echo "  make verify   - Verify GPU stack"
echo "  make info     - System information"
echo "  make test     - Run tests"
echo ""
