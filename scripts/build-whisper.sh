#!/bin/bash
set -euo pipefail

# Builds whisper.cpp as static archives for the TalkTraceTranscriber binary.
# Everything lands in native/vendor, which is gitignored. A stamp file makes
# repeat runs free.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="v1.9.2"
TARBALL_SHA256="a6abd064fcca8b85e794d205abf328c522e9451db43a3eadc178b883b7d0e9cd"
VENDOR="$ROOT/native/vendor"
SRC="$VENDOR/whisper"
STAMP="$VENDOR/.stamp-$TAG"

if [ -f "$STAMP" ]; then
  echo "whisper: $TAG already built"
  exit 0
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "whisper: cmake is required. Install it with: brew install cmake" >&2
  exit 1
fi

mkdir -p "$VENDOR"
TARBALL="$VENDOR/whisper-$TAG.tar.gz"

if [ ! -f "$TARBALL" ]; then
  echo "whisper: downloading $TAG"
  curl -fsSL -o "$TARBALL.part" \
    "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/$TAG.tar.gz"
  mv "$TARBALL.part" "$TARBALL"
fi

echo "$TARBALL_SHA256  $TARBALL" | shasum -a 256 -c - >/dev/null

if [ ! -d "$SRC" ]; then
  echo "whisper: extracting"
  rm -rf "$VENDOR/whisper.cpp-${TAG#v}"
  tar xzf "$TARBALL" -C "$VENDOR"
  mv "$VENDOR/whisper.cpp-${TAG#v}" "$SRC"
fi

# BUILD_SHARED_LIBS defaults to ON in ggml, which would give dylibs that each
# need their own signature inside the hardened runtime. OFF gives archives we
# link straight into the transcriber.
# GGML_METAL and GGML_METAL_EMBED_LIBRARY are both on by default on macOS, so
# the shaders end up inside the binary and there is no .metallib to ship.
echo "whisper: configuring"
cmake -S "$SRC" -B "$SRC/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_EXAMPLES=OFF \
  -DWHISPER_BUILD_SERVER=OFF \
  -DWHISPER_SDL2=OFF >/dev/null

echo "whisper: building (this takes a few minutes the first time)"
cmake --build "$SRC/build" --config Release -j "$(sysctl -n hw.ncpu)" >/dev/null

missing=0
for lib in libwhisper.a libggml.a libggml-base.a libggml-cpu.a libggml-metal.a libggml-blas.a; do
  if [ -z "$(find "$SRC/build" -name "$lib" -print -quit)" ]; then
    echo "whisper: missing $lib" >&2
    missing=1
  fi
done
[ "$missing" -eq 0 ] || exit 1

touch "$STAMP"
echo "whisper: $TAG built -> $SRC/build"
