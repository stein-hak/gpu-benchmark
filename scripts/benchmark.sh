#!/bin/bash
# Comprehensive server benchmark script
# Tests: CPU info, sysbench, speedtest, optional stress-ng

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output directory
RESULTS_DIR="/workspace/results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="${RESULTS_DIR}/benchmark_${TIMESTAMP}.json"

mkdir -p "${RESULTS_DIR}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Server Benchmark Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Initialize JSON report
cat > "${REPORT_FILE}" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
EOF

# ============================================
# 1. CPU Information
# ============================================
echo -e "${GREEN}[1/4] Gathering CPU Information...${NC}"

CPU_MODEL=$(lscpu | grep "Model name" | sed 's/Model name: *//')
CPU_ARCH=$(lscpu | grep "Architecture" | awk '{print $2}')
CPU_CORES=$(nproc)
CPU_THREADS=$(lscpu | grep "^CPU(s):" | awk '{print $2}')
CPU_MHZ=$(lscpu | grep "CPU MHz" | awk '{print $3}')
CPU_MAX_MHZ=$(lscpu | grep "CPU max MHz" | awk '{print $4}')
CPU_CACHE=$(lscpu | grep "L3 cache" | sed 's/L3 cache: *//')

echo "  CPU Model: ${CPU_MODEL}"
echo "  Architecture: ${CPU_ARCH}"
echo "  Physical Cores: ${CPU_CORES}"
echo "  Threads: ${CPU_THREADS}"
echo "  Current MHz: ${CPU_MHZ:-N/A}"
echo "  Max MHz: ${CPU_MAX_MHZ:-N/A}"
echo "  L3 Cache: ${CPU_CACHE:-N/A}"

# Add to JSON
cat >> "${REPORT_FILE}" <<EOF
  "cpu": {
    "model": "${CPU_MODEL}",
    "architecture": "${CPU_ARCH}",
    "cores": ${CPU_CORES},
    "threads": ${CPU_THREADS},
    "current_mhz": "${CPU_MHZ:-null}",
    "max_mhz": "${CPU_MAX_MHZ:-null}",
    "l3_cache": "${CPU_CACHE:-null}"
  },
EOF

echo ""

# ============================================
# 2. Sysbench CPU Benchmark
# ============================================
echo -e "${GREEN}[2/4] Running Sysbench CPU Benchmark...${NC}"
echo "  Test: Prime numbers up to 20000"
echo "  Threads: 1, ${CPU_CORES}, $((CPU_CORES * 2))"
echo ""

# Single thread
echo -e "${YELLOW}  → Single thread...${NC}"
SYSBENCH_1T=$(sysbench cpu --cpu-max-prime=20000 --threads=1 run 2>&1)
EVENTS_1T=$(echo "$SYSBENCH_1T" | grep "events per second" | awk '{print $4}')
LATENCY_1T=$(echo "$SYSBENCH_1T" | grep "avg:" | awk '{print $2}')

echo "    Events/sec: ${EVENTS_1T}"
echo "    Avg latency: ${LATENCY_1T}ms"

# All cores
echo -e "${YELLOW}  → ${CPU_CORES} threads (all cores)...${NC}"
SYSBENCH_NT=$(sysbench cpu --cpu-max-prime=20000 --threads=${CPU_CORES} run 2>&1)
EVENTS_NT=$(echo "$SYSBENCH_NT" | grep "events per second" | awk '{print $4}')
LATENCY_NT=$(echo "$SYSBENCH_NT" | grep "avg:" | awk '{print $2}')

echo "    Events/sec: ${EVENTS_NT}"
echo "    Avg latency: ${LATENCY_NT}ms"

# Hyperthreading test
HT_THREADS=$((CPU_CORES * 2))
echo -e "${YELLOW}  → ${HT_THREADS} threads (with HT)...${NC}"
SYSBENCH_HT=$(sysbench cpu --cpu-max-prime=20000 --threads=${HT_THREADS} run 2>&1)
EVENTS_HT=$(echo "$SYSBENCH_HT" | grep "events per second" | awk '{print $4}')
LATENCY_HT=$(echo "$SYSBENCH_HT" | grep "avg:" | awk '{print $2}')

echo "    Events/sec: ${EVENTS_HT}"
echo "    Avg latency: ${LATENCY_HT}ms"

# Add to JSON
cat >> "${REPORT_FILE}" <<EOF
  "sysbench": {
    "single_thread": {
      "events_per_sec": ${EVENTS_1T},
      "avg_latency_ms": ${LATENCY_1T}
    },
    "all_cores": {
      "threads": ${CPU_CORES},
      "events_per_sec": ${EVENTS_NT},
      "avg_latency_ms": ${LATENCY_NT}
    },
    "hyperthreading": {
      "threads": ${HT_THREADS},
      "events_per_sec": ${EVENTS_HT},
      "avg_latency_ms": ${LATENCY_HT}
    }
  },
EOF

echo ""

# ============================================
# 3. Network Speed Test
# ============================================
echo -e "${GREEN}[3/4] Running Network Speed Test...${NC}"

SPEEDTEST_OUTPUT=$(speedtest-cli --json 2>/dev/null || echo '{"download": 0, "upload": 0, "ping": 0}')

DOWNLOAD=$(echo "$SPEEDTEST_OUTPUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('download', 0) / 1_000_000)" 2>/dev/null || echo "0")
UPLOAD=$(echo "$SPEEDTEST_OUTPUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('upload', 0) / 1_000_000)" 2>/dev/null || echo "0")
PING=$(echo "$SPEEDTEST_OUTPUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('ping', 0))" 2>/dev/null || echo "0")

if [ "$DOWNLOAD" != "0" ]; then
    echo -e "  ${YELLOW}Download:${NC} ${DOWNLOAD} Mbps"
    echo -e "  ${YELLOW}Upload:${NC} ${UPLOAD} Mbps"
    echo -e "  ${YELLOW}Ping:${NC} ${PING} ms"
else
    echo -e "  ${RED}Speed test failed (might need external network access)${NC}"
fi

# Add to JSON
cat >> "${REPORT_FILE}" <<EOF
  "network": {
    "download_mbps": ${DOWNLOAD},
    "upload_mbps": ${UPLOAD},
    "ping_ms": ${PING}
  },
EOF

echo ""

# ============================================
# 4. Optional: Stress Test
# ============================================
if [ "$1" == "--stress" ] || [ "$1" == "-s" ]; then
    STRESS_DURATION=${2:-60}
    echo -e "${GREEN}[4/4] Running Stress Test (${STRESS_DURATION}s)...${NC}"
    echo -e "${RED}  WARNING: This will use 100% CPU${NC}"
    echo ""

    # CPU stress
    echo -e "${YELLOW}  → CPU stress test...${NC}"
    stress-ng --cpu ${CPU_CORES} --timeout ${STRESS_DURATION}s --metrics-brief 2>&1 | tee /tmp/stress-output.txt

    STRESS_BOGO=$(grep "bogo ops" /tmp/stress-output.txt | awk '{print $4}' || echo "0")
    STRESS_REAL=$(grep "bogo ops real time" /tmp/stress-output.txt | awk '{print $6}' || echo "0")

    echo "    Bogo ops: ${STRESS_BOGO}"
    echo "    Bogo ops/s (real time): ${STRESS_REAL}"

    # Add to JSON
    cat >> "${REPORT_FILE}" <<EOF
  "stress_test": {
    "duration_sec": ${STRESS_DURATION},
    "cpu_cores": ${CPU_CORES},
    "bogo_ops": ${STRESS_BOGO},
    "bogo_ops_per_sec": ${STRESS_REAL}
  },
EOF
else
    echo -e "${GREEN}[4/4] Stress Test ${YELLOW}SKIPPED${NC}"
    echo "  Run with --stress or -s to enable"
    echo "  Example: benchmark.sh --stress 60"

    # Add null to JSON
    cat >> "${REPORT_FILE}" <<EOF
  "stress_test": null,
EOF
fi

echo ""

# ============================================
# Finalize JSON
# ============================================
cat >> "${REPORT_FILE}" <<EOF
  "completed": true
}
EOF

# ============================================
# Summary
# ============================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Benchmark Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}Results saved to:${NC} ${REPORT_FILE}"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "  CPU: ${CPU_MODEL}"
echo "  Cores: ${CPU_CORES} physical, ${CPU_THREADS} logical"
echo "  Sysbench (1T): ${EVENTS_1T} events/sec"
echo "  Sysbench (${CPU_CORES}T): ${EVENTS_NT} events/sec"
echo "  Network Down/Up: ${DOWNLOAD}/${UPLOAD} Mbps"
echo ""
