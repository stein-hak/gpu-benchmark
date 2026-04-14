.PHONY: build up down shell verify info test clean help push pull build-and-push

# Variables (can be overridden by .env)
IMAGE_NAME ?= steinhak/gpu-benchmark
IMAGE_TAG ?= gstreamer-1.28
CONTAINER_NAME := gpu-benchmark

# Load .env if exists
-include .env
export

help: ## Show this help
	@echo "GPU Benchmark - Available commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Build Docker image
	docker compose build

up: ## Start container
	docker compose up -d

down: ## Stop container
	docker compose down

shell: ## Enter container shell
	docker compose exec $(CONTAINER_NAME) bash

verify: ## Verify GPU stack
	docker compose exec $(CONTAINER_NAME) verify-stack

info: ## Show system info
	docker compose exec $(CONTAINER_NAME) info

test: ## Run encoding performance tests
	docker compose exec $(CONTAINER_NAME) python3 /workspace/tests/test_simple.py

test-parallel: ## Test maximum parallel NVENC H.264 streams capacity
	docker compose exec $(CONTAINER_NAME) python3 /workspace/tests/test_parallel_nvenc.py

test-parallel-h264: ## Test maximum parallel NVENC H.264 streams capacity
	docker compose exec $(CONTAINER_NAME) python3 /workspace/tests/test_parallel_nvenc.py

test-parallel-h265: ## Test maximum parallel NVENC H.265/HEVC streams capacity
	docker compose exec $(CONTAINER_NAME) python3 /workspace/tests/test_parallel_nvenc_h265.py

benchmark: ## Run full server benchmark (CPU, network)
	docker compose exec $(CONTAINER_NAME) benchmark

benchmark-stress: ## Run benchmark with stress test (60s)
	docker compose exec $(CONTAINER_NAME) benchmark --stress 60

benchmark-stress-long: ## Run benchmark with long stress test (300s)
	docker compose exec $(CONTAINER_NAME) benchmark --stress 300

clean: ## Clean results and test files
	rm -rf results/*.json results/*.mp4 results/*.avi

rebuild: ## Rebuild image from scratch
	docker compose build --no-cache

logs: ## Show container logs
	docker compose logs -f

push: ## Push image to Docker Hub
	@echo "Pushing $(IMAGE_NAME):$(IMAGE_TAG) to Docker Hub..."
	docker compose build
	docker tag $(IMAGE_NAME):$(IMAGE_TAG) $(IMAGE_NAME):$(IMAGE_TAG)
	docker push $(IMAGE_NAME):$(IMAGE_TAG)
	@echo "Push complete! Image: $(IMAGE_NAME):$(IMAGE_TAG)"

pull: ## Pull pre-built image from Docker Hub
	@echo "Pulling $(IMAGE_NAME):$(IMAGE_TAG) from Docker Hub..."
	docker pull $(IMAGE_NAME):$(IMAGE_TAG)

build-and-push: ## Build and push to Docker Hub
	docker compose build
	docker push $(IMAGE_NAME):$(IMAGE_TAG)
	@echo "Build and push complete!"

use-prebuilt: ## Switch to using pre-built images (update .env)
	@if [ ! -f .env ]; then cp .env.example .env; fi
	@echo "Edit .env file and set BUILD_MODE=pull"
	@echo "Then run: make pull && make up"

# Chrome variant commands
build-chrome: ## Build Chrome variant image
	docker compose -f docker-compose.chrome.yml build

up-chrome: ## Start Chrome variant container
	docker compose -f docker-compose.chrome.yml up -d

down-chrome: ## Stop Chrome variant container
	docker compose -f docker-compose.chrome.yml down

shell-chrome: ## Enter Chrome variant container shell
	docker compose -f docker-compose.chrome.yml exec gpu-benchmark-chrome bash

test-chrome: ## Run Chrome video decode test
	docker compose -f docker-compose.chrome.yml exec gpu-benchmark-chrome ./chrome-test.sh

verify-chrome-gpu: ## Verify Chrome GPU acceleration status
	docker compose -f docker-compose.chrome.yml exec gpu-benchmark-chrome ./chrome-gpu-info.sh

save-chrome-gpu-report: ## Save chrome://gpu report to file
	docker compose -f docker-compose.chrome.yml exec gpu-benchmark-chrome ./save-chrome-gpu-report.sh

get-chrome-gpu: ## Get Chrome GPU info via DevTools Protocol
	docker compose -f docker-compose.chrome.yml exec gpu-benchmark-chrome python3 ./get-chrome-gpu.py

monitor-chrome-gpu: ## Monitor GPU usage in real-time (Ctrl+C to stop)
	@echo "Monitoring GPU usage (Ctrl+C to stop)..."
	@docker compose -f docker-compose.chrome.yml exec gpu-benchmark-chrome bash -c "watch -n 1 nvidia-smi"
