FROM ubuntu:20.04 AS ffmpeg-build

ENV DEBIAN_FRONTEND=noninteractive

# Install build tools
RUN apt-get update && \
    apt-get install -y \
      build-essential \
      cmake \
      curl \
      make \
      nasm \
      pkg-config \
      yasm

# ffmpeg-build-base-image
COPY --from=ghcr.io/akashisn/ffmpeg-build-base / /

#
# Build ffmpeg
#
ARG FFMPEG_VERSION=4.4
RUN curl -sL -o /tmp/ffmpeg-${FFMPEG_VERSION}.tar.xz  https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz
RUN cd /tmp && \
    tar xf /tmp/ffmpeg-${FFMPEG_VERSION}.tar.xz && \
    cd /tmp/ffmpeg-${FFMPEG_VERSION} && \
    ./configure `cat /usr/local/ffmpeg_configure_options` \
                --disable-autodetect \
                --disable-debug \
                --disable-doc \
                --disable-ffplay \
                --enable-gpl \
                --enable-small \
                --enable-version3 \
                --extra-libs="`cat /usr/local/ffmpeg_extra_libs`" \
                --pkg-config-flags="--static" > /usr/local/configure_options && \
    make -j $(nproc) && \
    make install

# Copy artifacts
RUN mkdir /build && \
    cp --archive --parents --no-dereference /usr/local/bin/ff* /build && \
    cp --archive --parents --no-dereference /usr/local/configure_options /build


# final ffmpeg image
FROM ubuntu:20.04 AS ffmpeg

COPY --from=ffmpeg-build /build /

WORKDIR /workdir
ENTRYPOINT [ "ffmpeg" ]
CMD [ "--help" ]


# export image
FROM scratch AS export

COPY --from=ffmpeg-build /build/usr/local/ /