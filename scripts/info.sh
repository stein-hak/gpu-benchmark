#!/bin/bash
# Display system and GPU information

echo "System Information"
echo "=================="
echo ""

echo "Operating System:"
cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2 | sed 's/^/  /'
echo ""

echo "CPU:"
grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | sed 's/^ */  /'
echo "  Cores: $(nproc)"
echo ""

echo "Memory:"
free -h | grep "Mem:" | awk '{print "  Total: " $2 "\n  Used:  " $3 "\n  Free:  " $4}'
echo ""

echo "GPU:"
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.total,compute_cap,driver_version --format=csv,noheader | \
        awk -F', ' '{print "  Name: " $1 "\n  Memory: " $2 "\n  Compute: " $3 "\n  Driver: " $4}'
    echo ""
    echo "GPU Status:"
    nvidia-smi --query-gpu=utilization.gpu,utilization.memory,temperature.gpu --format=csv,noheader | \
        awk -F', ' '{print "  GPU Util: " $1 "\n  Mem Util: " $2 "\n  Temp: " $3}'
else
    echo "  No NVIDIA GPU found"
fi
