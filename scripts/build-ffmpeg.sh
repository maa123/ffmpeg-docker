#!/bin/bash

source ./base.sh
mkdir -p ${ARTIFACT_DIR}

# Build ffmpeg
FFMPEG_VERSION="${FFMPEG_VERSION:-"7.0"}"
git_clone "https://github.com/FFmpeg/FFmpeg.git" n${FFMPEG_VERSION}
curl https://git.ffmpeg.org/gitweb/ffmpeg.git/commitdiff_plain/effadce6c756247ea8bae32dc13bb3e6f464f0eb > /ffmpeg_commit.diff
cd n${FFMPEG_VERSION}
patch -p1 < /ffmpeg_commit.diff
cd ..
rm -f /ffmpeg_commit.diff

FFMPEG_LIBVPL_SUPPORT_VERSION="6.0"
if [ "${FFMPEG_VERSION}" != "${FFMPEG_LIBVPL_SUPPORT_VERSION}" ]; then
  if [ "$(echo -e "${FFMPEG_VERSION}\n${FFMPEG_LIBVPL_SUPPORT_VERSION}" | sort -Vr | head -n 1)" == "${FFMPEG_LIBVPL_SUPPORT_VERSION}" ]; then
    sed -i -e "s/libvpl/libmfx/g" ${PREFIX}/ffmpeg_configure_options
  fi
fi

# Configure
case ${TARGET_OS} in
Linux | linux)
  ./configure `cat ${PREFIX}/ffmpeg_configure_options` \
              --disable-autodetect \
              --disable-debug \
              --disable-doc \
              --enable-gpl \
              --enable-version3 \
              --extra-libs="`cat ${PREFIX}/ffmpeg_extra_libs`" \
              --pkg-config-flags="--static" \
              --prefix=${PREFIX} | tee ${PREFIX}/configure_options 1>&2
  ;;
Darwin | darwin)
  HOST_OS="macos"
  HOST_ARCH="universal"
  BUILD_TARGET=
  CROSS_PREFIX=
  ;;
Windows | windows)
  ./configure `cat ${PREFIX}/ffmpeg_configure_options` \
              --arch="x86_64" \
              --cross-prefix="${CROSS_PREFIX}" \
              --disable-autodetect \
              --disable-debug \
              --disable-doc \
              --disable-w32threads \
              --enable-cross-compile \
              --enable-gpl \
              --enable-version3 \
              --extra-libs="-static -Wl,-Bstatic `cat ${PREFIX}/ffmpeg_extra_libs`" \
              --extra-cflags="--static" \
              --target-os="mingw64" \
              --pkg-config="pkg-config" \
              --pkg-config-flags="--static" \
              --prefix=${PREFIX} | tee ${PREFIX}/configure_options 1>&2
  ;;
esac

# Build
do_make_and_make_install


#
# Finalize
#

cp_archive ${PREFIX}/configure_options ${ARTIFACT_DIR}
cp_archive ${PREFIX}/bin/ff* ${ARTIFACT_DIR}

if [ "${TARGET_OS}" = "Linux" ]; then
  cp_archive ${PREFIX}/bin/vainfo ${ARTIFACT_DIR}
  cd ${RUNTIME_LIB_DIR}
  cp_archive * ${ARTIFACT_DIR}
fi
