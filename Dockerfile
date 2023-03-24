# syntax = docker/dockerfile:1.5

ARG FFMPEG_VERSION="6.0"
ARG INTEL_HWACCEL_LIBRARY="libmfx"
FROM akashisn/ffmpeg:${FFMPEG_VERSION} AS ffmpeg-image
FROM akashisn/ffmpeg:${FFMPEG_VERSION}-${INTEL_HWACCEL_LIBRARY} AS ffmpeg-image-qsv
FROM ghcr.io/akashisn/ffmpeg-windows:${FFMPEG_VERSION} AS ffmpeg-image-windows

#
# build env image
#
FROM ubuntu:22.04 AS ffmpeg-build-env

SHELL ["/bin/bash", "-e", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# Install build tools
RUN <<EOT
rm -rf /var/lib/apt/lists/*
sed -i -r 's@http://(jp.)?archive.ubuntu.com/ubuntu/@http://ftp.udx.icscoe.jp/Linux/ubuntu/@g' /etc/apt/sources.list
apt-get update
apt-get install -y \
    autopoint \
    build-essential \
    clang \
    cmake \
    curl \
    gettext \
    git \
    gperf \
    libdrm-dev \
    libgl-dev \
    libtool \
    libwayland-dev \
    libx11-xcb-dev \
    libxcb-dri3-dev \
    libxcb-present-dev \
    libxext-dev \
    libxfixes-dev \
    lzip \
    make \
    meson \
    mingw-w64 \
    mingw-w64-tools \
    nasm \
    p7zip \
    pkg-config \
    ragel \
    subversion \
    xxd \
    yasm
EOT

# Environment
ARG FFMPEG_VERSION
ENV FFMPEG_VERSION="${FFMPEG_VERSION}" \
    PREFIX="/usr/local" \
    WORKDIR="/workdir"
WORKDIR ${WORKDIR}

# Copy build script
ADD ./scripts/base.sh ./

#
# ffmpeg library build image
#
FROM ffmpeg-build-env AS ffmpeg-library-build

# Environment
ARG TARGET_OS="Linux"
ENV TARGET_OS=${TARGET_OS}

# Copy build script
ADD ./scripts/build-library.sh ./

# Run build
RUN bash ./build-library.sh

# Copy artifacts
RUN <<EOT
mkdir /build
cp --archive --parents --no-dereference ${PREFIX}/lib /build
cp --archive --parents --no-dereference ${PREFIX}/include /build
cp --archive --parents --no-dereference ${PREFIX}/ffmpeg_extra_libs /build
cp --archive --parents --no-dereference ${PREFIX}/ffmpeg_configure_options /build
EOT


#
# ffmpeg linux binary build base image
#
FROM ffmpeg-build-env AS ffmpeg-linux-build-base

# Environment
ENV TARGET_OS="Linux"

# Copy build script
ADD ./scripts/build-ffmpeg.sh ./

# Copy ffmpeg-library image
COPY --from=ghcr.io/akashisn/ffmpeg-library:linux / /


#
# ffmpeg linux binary build image
#
FROM ffmpeg-linux-build-base AS ffmpeg-linux-build

# Build ffmpeg
RUN bash ./build-ffmpeg.sh

# Copy run.sh
COPY <<'EOT' ${PREFIX}/run.sh
#!/bin/sh
export PATH=$(dirname $0)/bin:$PATH
exec $@
EOT

# Copy artifacts
RUN <<EOT
mkdir /build
chmod +x ${PREFIX}/run.sh
cp --archive --parents --no-dereference ${PREFIX}/run.sh /build
cp --archive --parents --no-dereference ${PREFIX}/bin/ff* /build
cp --archive --parents --no-dereference ${PREFIX}/configure_options /build
EOT


#
# ffmpeg qsv linux binary build image
#
FROM ffmpeg-linux-build-base AS ffmpeg-linux-qsv-build

ARG INTEL_HWACCEL_LIBRARY
ENV INTEL_HWACCEL_LIBRARY="${INTEL_HWACCEL_LIBRARY}"

# Build ffmpeg
RUN bash ./build-ffmpeg.sh

# Copy run.sh
COPY <<'EOT' ${PREFIX}/run.sh
#!/bin/sh
export PATH=$(dirname $0)/bin:$PATH
export LD_LIBRARY_PATH=$(dirname $0)/lib:$LD_LIBRARY_PATH
export LIBVA_DRIVERS_PATH=$(dirname $0)/lib/dri
export LIBVA_DRIVER_NAME=iHD
exec $@
EOT

# Copy artifacts
RUN <<EOT
mkdir /build
chmod +x ${PREFIX}/run.sh
cp --archive --parents --no-dereference ${PREFIX}/run.sh /build
cp --archive --parents --no-dereference ${PREFIX}/bin/ff* /build
cp --archive --parents --no-dereference ${PREFIX}/configure_options /build
cp --archive --parents --no-dereference ${PREFIX}/lib/dri /build
if [ "${INTEL_HWACCEL_LIBRARY}" = "libmfx" ]; then
    cp --archive --parents --no-dereference ${PREFIX}/lib/{libva,libva-drm,libmfx,libmfxhw64,libigdgmm}.so* /build
elif [ "${INTEL_HWACCEL_LIBRARY}" = "libvpl" ]; then
    cp --archive --parents --no-dereference ${PREFIX}/lib/{libva,libva-drm,libvpl,libigdgmm}.so* /build
fi
EOT


#
# ffmpeg windows binary build image
#
FROM ffmpeg-build-env AS ffmpeg-windows-build

# Environment
ENV TARGET_OS="Windows"

# Copy build script
ADD ./scripts/build-ffmpeg.sh ./

# Copy ffmpeg-library image
COPY --from=ghcr.io/akashisn/ffmpeg-library:windows / /

# HWAccel
# Build libmfx
RUN <<EOT
source ./base.sh
download_and_unpack_file "https://github.com/lu-zero/mfx_dispatch/archive/master.tar.gz" mfx_dispatch-master.tar.gz
do_configure
do_make_and_make_install
echo -n "`cat ${PREFIX}/ffmpeg_configure_options` --enable-libmfx" > ${PREFIX}/ffmpeg_configure_options
EOT

# Other hwaccel
RUN echo -n "`cat ${PREFIX}/ffmpeg_configure_options` --enable-d3d11va --enable-dxva2" > ${PREFIX}/ffmpeg_configure_options

# Build ffmpeg
RUN bash ./build-ffmpeg.sh

# Copy artifacts
RUN <<EOT
mkdir /build
cp ${PREFIX}/bin/ff* /build/
cp ${PREFIX}/configure_options /build/
EOT


#
# final ffmpeg-library image
#
FROM scratch AS ffmpeg-library

COPY --from=ffmpeg-library-build /build /


#
# final ffmpeg image
#
FROM ubuntu:22.04 AS ffmpeg

# Copy ffmpeg
COPY --from=ffmpeg-linux-build /build /

WORKDIR /workdir
ENTRYPOINT [ "ffmpeg" ]
CMD [ "--help" ]


#
# final ffmpeg-qsv image
#
FROM ubuntu:22.04 AS ffmpeg-qsv

# Copy ffmpeg
COPY --from=ffmpeg-linux-qsv-build /build /

SHELL ["/bin/sh", "-e", "-c"]
ENV DEBIAN_FRONTEND=noninteractive \
    LIBVA_DRIVERS_PATH=/usr/local/lib/dri \
    LIBVA_DRIVER_NAME=iHD

# Install runtime dependency
RUN <<EOT
apt-get update
apt-get install -y libdrm2
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/*

ldconfig
EOT

WORKDIR /workdir
ENTRYPOINT [ "ffmpeg" ]
CMD [ "--help" ]


#
# final ffmpeg-windows image
#
FROM scratch AS ffmpeg-windows

COPY --from=ffmpeg-windows-build /build /


#
# export image
#
FROM scratch AS export

COPY --from=ffmpeg-image /usr/local/bin /bin
COPY --from=ffmpeg-image /usr/local/configure_options /
COPY --from=ffmpeg-image /usr/local/run.sh /

#
# export qsv image
#
FROM scratch AS export-qsv

COPY --from=ffmpeg-image-qsv /usr/local/bin /bin
COPY --from=ffmpeg-image-qsv /usr/local/lib /lib
COPY --from=ffmpeg-image-qsv /usr/local/configure_options /
COPY --from=ffmpeg-image-qsv /usr/local/run.sh /

#
# export windws exe
#
FROM scratch AS export-windows

COPY --from=ffmpeg-image-windows / /


#
# vainfo image
#
FROM ubuntu:22.04 AS vainfo

SHELL ["/bin/bash", "-e", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    LIBVA_DRIVERS_PATH=/usr/local/lib \
    LIBVA_DRIVER_NAME=iHD

# Download MediaSDK
ENV INTEL_MEDIA_SDK_VERSION=21.3.5
ADD https://github.com/Intel-Media-SDK/MediaSDK/releases/download/intel-mediasdk-${INTEL_MEDIA_SDK_VERSION}/MediaStack.tar.gz /tmp/
RUN <<EOT
mkdir -p /tmp/MediaStack
tar -xf "/tmp/MediaStack.tar.gz" --strip-components 1 -C "/tmp/MediaStack"
cd /tmp/MediaStack/opt/intel/mediasdk
cp --archive --no-dereference bin/vainfo /usr/local/bin/
cp --archive --no-dereference lib64/*.so* /usr/local/lib/

rm -rf /var/lib/apt/lists/*
sed -i -r 's@http://(jp.)?archive.ubuntu.com/ubuntu/@http://ftp.udx.icscoe.jp/Linux/ubuntu/@g' /etc/apt/sources.list
apt-get update
apt-get install -y libdrm2 libxext6 libxfixes3
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/*

ldconfig
EOT

WORKDIR /workdir
ENTRYPOINT [ "/usr/local/bin/vainfo" ]
