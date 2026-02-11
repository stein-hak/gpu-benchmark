# ============================================
# Stage 1: Builder - compile FFmpeg with NVENC
# ============================================
FROM nvidia/cuda:12.2.0-devel-ubuntu22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Build dependencies
RUN apt-get update && apt-get install -y \
    wget curl git \
    build-essential pkg-config \
    yasm nasm cmake ninja-build \
    libx264-dev libx265-dev libvpx-dev \
    libopus-dev libmp3lame-dev \
    libass-dev libfreetype6-dev \
    libfdk-aac-dev libvorbis-dev libtheora-dev \
    libva-dev libvdpau-dev libdrm-dev \
    && rm -rf /var/lib/apt/lists/*

# Install NVIDIA Video Codec SDK headers (specific version for FFmpeg 6.0)
WORKDIR /tmp
RUN git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git && \
    cd nv-codec-headers && \
    git checkout n12.0.16.0 && \
    make install && \
    cd .. && rm -rf nv-codec-headers

# Build FFmpeg with NVENC support
ARG FFMPEG_VERSION=6.0
WORKDIR /tmp/ffmpeg-build
RUN wget -q https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz && \
    tar xf ffmpeg-${FFMPEG_VERSION}.tar.xz && \
    cd ffmpeg-${FFMPEG_VERSION} && \
    ./configure \
        --prefix=/opt/ffmpeg \
        --enable-nonfree \
        --enable-gpl \
        --enable-version3 \
        --enable-cuda-nvcc \
        --enable-cuvid \
        --enable-nvenc \
        --enable-nvdec \
        --enable-libnpp \
        --extra-cflags="-I/usr/local/cuda/include" \
        --extra-ldflags="-L/usr/local/cuda/lib64" \
        --enable-libx264 \
        --enable-libx265 \
        --enable-libvpx \
        --enable-libopus \
        --enable-libmp3lame \
        --enable-libass \
        --enable-libfreetype \
        --enable-libfdk-aac \
        --enable-libvorbis \
        --enable-libtheora \
        --enable-shared && \
    make -j$(nproc) && \
    make install

# ============================================
# Stage 2: Runtime - minimal final image
# ============================================
FROM nvidia/cuda:12.2.0-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=all

LABEL maintainer="gpu-benchmark"
LABEL description="GPU encoding/decoding benchmark - runtime"

# Runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core utils
    wget curl ca-certificates \
    # FFmpeg codec libraries
    libx264-163 libx265-199 libvpx7 \
    libopus0 libmp3lame0 \
    libass9 libfreetype6 \
    libfdk-aac2 libvorbis0a libtheora0 \
    libva2 libvdpau1 libdrm2 \
    # GStreamer full stack
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-x \
    gstreamer1.0-alsa \
    gstreamer1.0-pulseaudio \
    # Python 3
    python3 python3-pip \
    python3-gi python3-gst-1.0 \
    # Monitoring tools
    htop nvtop \
    # Benchmarking tools
    sysbench stress-ng speedtest-cli \
    lshw pciutils lm-sensors \
    && rm -rf /var/lib/apt/lists/*

# Copy FFmpeg from builder
COPY --from=builder /opt/ffmpeg /opt/ffmpeg
COPY --from=builder /usr/local/cuda/lib64/*.so* /usr/local/cuda/lib64/

# Set up FFmpeg in PATH and library path
ENV PATH="/opt/ffmpeg/bin:${PATH}"
ENV LD_LIBRARY_PATH="/opt/ffmpeg/lib:/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"
ENV PKG_CONFIG_PATH="/opt/ffmpeg/lib/pkgconfig:${PKG_CONFIG_PATH}"

# Install Python packages
COPY requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt && \
    rm /tmp/requirements.txt

# Copy scripts
COPY scripts/verify-stack.sh /usr/local/bin/verify-stack
COPY scripts/info.sh /usr/local/bin/info
COPY scripts/benchmark.sh /usr/local/bin/benchmark
RUN chmod +x /usr/local/bin/verify-stack /usr/local/bin/info /usr/local/bin/benchmark

# Working directory
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]
