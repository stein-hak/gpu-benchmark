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
    # Additional dependencies for GStreamer 1.28
    python3-pip python3-setuptools python3-dev \
    autoconf automake libtool flex bison \
    libgl1-mesa-dev libxml2-dev libglib2.0-dev \
    libcairo2-dev libjpeg-dev libpng-dev zlib1g-dev \
    libssl-dev \
    libv4l-dev libxcb-shm0-dev libxcb-xfixes0-dev \
    python3-gi libgirepository1.0-dev \
    librtmp-dev libpulse-dev \
    libgudev-1.0-dev \
    # Required for Rust plugins
    libclang-dev llvm \
    && rm -rf /var/lib/apt/lists/*

# Install NVIDIA Video Codec SDK headers (specific version for FFmpeg 6.0)
WORKDIR /tmp
RUN git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git && \
    cd nv-codec-headers && \
    git checkout n12.0.16.0 && \
    make install && \
    cd .. && rm -rf nv-codec-headers

# Install Rust (required for GStreamer 1.28)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install Python dependencies for GStreamer build
RUN pip3 install --no-cache-dir meson wheel tomli

# Install cargo-c for building Rust plugins
RUN cargo install cargo-c

# Build GStreamer 1.28 with comprehensive plugin support
ENV GSTREAMER_INSTALL_DIR=/opt/gstreamer
WORKDIR /tmp/gstreamer-build
RUN git clone https://gitlab.freedesktop.org/gstreamer/gstreamer.git -b 1.28.2 && \
    cd gstreamer && \
    mkdir build && cd build && \
    meson setup --prefix=${GSTREAMER_INSTALL_DIR} \
        -Dbuildtype=release \
        -Dgood=enabled \
        -Dbad=enabled \
        -Dugly=enabled \
        -Dlibav=enabled \
        -Dgpl=enabled \
        -Dgst-plugins-base:gl=enabled \
        -Dgst-plugins-base:ogg=enabled \
        -Dgst-plugins-base:opus=enabled \
        -Dgst-plugins-base:vorbis=enabled \
        -Dgst-plugins-base:theora=enabled \
        -Dgst-plugins-good:jpeg=enabled \
        -Dgst-plugins-good:png=enabled \
        -Dgst-plugins-good:vpx=enabled \
        -Dgst-plugins-good:pulse=enabled \
        -Dgst-plugins-good:v4l2=enabled \
        -Dgst-plugins-good:ximagesrc=enabled \
        -Dgst-plugins-bad:rtmp=enabled \
        -Dgst-plugins-bad:nvcodec=enabled \
        -Dgst-plugins-bad:va=enabled \
        -Dgst-plugins-bad:openh264=disabled \
        -Dgst-plugins-ugly:x264=enabled \
        -Drs=enabled \
        -Dexamples=disabled \
        -Dtests=disabled \
        -Dpython=enabled \
        -Dintrospection=enabled \
        -Dorc=enabled \
        -Drtsp_server=enabled \
        -Dgst-rtsp-server:introspection=enabled \
        .. && \
    ninja && \
    ninja install && \
    ldconfig

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
    # GStreamer runtime dependencies (we build from source, so just deps)
    libglib2.0-0 libgstreamer1.0-0 \
    libxml2 libcairo2 libcairo-gobject2 \
    libjpeg-turbo8 libpng16-16 \
    libpulse0 libv4l-0 \
    librtmp1 libgudev-1.0-0 \
    # EGL/OpenGL runtime for nvcodec and opengl plugins
    libegl1 libgl1 libgles2 \
    # VA-API runtime support
    libva-drm2 libva-x11-2 \
    intel-media-va-driver i965-va-driver mesa-va-drivers \
    vainfo \
    # Python 3 with GObject introspection and runtime
    python3 python3-pip python3-gi \
    libpython3.10 \
    # Monitoring tools
    htop nvtop \
    # Benchmarking tools
    sysbench stress-ng speedtest-cli \
    lshw pciutils lm-sensors \
    && rm -rf /var/lib/apt/lists/*

# Copy GStreamer and FFmpeg from builder
ENV GSTREAMER_INSTALL_DIR=/opt/gstreamer
COPY --from=builder ${GSTREAMER_INSTALL_DIR} ${GSTREAMER_INSTALL_DIR}
COPY --from=builder /opt/ffmpeg /opt/ffmpeg
COPY --from=builder /usr/local/cuda/lib64/*.so* /usr/local/cuda/lib64/

# Set up GStreamer environment
ENV PATH="${GSTREAMER_INSTALL_DIR}/bin:/opt/ffmpeg/bin:${PATH}"
ENV LD_LIBRARY_PATH="${GSTREAMER_INSTALL_DIR}/lib/x86_64-linux-gnu:/opt/ffmpeg/lib:/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"
ENV PKG_CONFIG_PATH="${GSTREAMER_INSTALL_DIR}/lib/x86_64-linux-gnu/pkgconfig:/opt/ffmpeg/lib/pkgconfig:${PKG_CONFIG_PATH}"
ENV GI_TYPELIB_PATH="${GSTREAMER_INSTALL_DIR}/lib/x86_64-linux-gnu/girepository-1.0:${GI_TYPELIB_PATH}"
ENV GST_PLUGIN_PATH="${GSTREAMER_INSTALL_DIR}/lib/x86_64-linux-gnu/gstreamer-1.0:${GST_PLUGIN_PATH}"
ENV PYTHONPATH="${GSTREAMER_INSTALL_DIR}/lib/python3/dist-packages:${PYTHONPATH}"

# Enable VA-API and NVIDIA drivers
ENV LIBVA_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri
ENV LIBVA_DRIVER_NAME=auto

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
