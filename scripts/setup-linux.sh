#!/usr/bin/env bash
# Installs the project-local ARM toolchain and libpng for Linux and WSL2.
# System build utilities (make, gcc, ar, curl, tar, sha256sum) must be present.
# Re-running is safe: finished steps are skipped.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TC="$ROOT/.toolchain"
mkdir -p "$TC/downloads"

GCC_VER="14.2.1-1.1"
LIBPNG_VER="1.6.44"

case "$(uname -m)" in
  x86_64) GCC_HOST="linux-x64" ;;
  aarch64|arm64) GCC_HOST="linux-arm64" ;;
  *) echo "Unsupported CPU: $(uname -m)"; exit 1 ;;
esac

for cmd in curl tar sha256sum make gcc ar git python3 gzip unzip; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd"
    echo "On Debian or Ubuntu, install the build tools with:"
    echo "  sudo apt update && sudo apt install build-essential curl git python3 gzip unzip zlib1g-dev"
    exit 1
  fi
done

# --- arm-none-eabi GCC --------------------------------------------------------
GCC_NAME="xpack-arm-none-eabi-gcc-$GCC_VER"
if [ ! -x "$TC/arm-none-eabi/bin/arm-none-eabi-gcc" ]; then
  tarball="$GCC_NAME-$GCC_HOST.tar.gz"
  url="https://github.com/xpack-dev-tools/arm-none-eabi-gcc-xpack/releases/download/v$GCC_VER/$tarball"
  echo ">> Downloading $tarball"
  curl -fL --retry 3 -o "$TC/downloads/$tarball" "$url"
  curl -fsL -o "$TC/downloads/$tarball.sha" "$url.sha"
  expected="$(awk '{print $1}' "$TC/downloads/$tarball.sha")"
  actual="$(sha256sum "$TC/downloads/$tarball" | awk '{print $1}')"
  [ "$expected" = "$actual" ] || { echo "Checksum mismatch for $tarball"; exit 1; }
  echo ">> Checksum OK, extracting"
  tar -xzf "$TC/downloads/$tarball" -C "$TC"
  ln -sfn "$GCC_NAME" "$TC/arm-none-eabi"
  rm -f "$TC/downloads/$tarball"
fi
"$TC/arm-none-eabi/bin/arm-none-eabi-gcc" --version | head -1
echo 'int f(void){return 0;}' | "$TC/arm-none-eabi/bin/arm-none-eabi-gcc" -x c -c -o /dev/null -

# --- libpng (static, built with the system compiler) --------------------------
if [ ! -f "$TC/libpng/lib/libpng.a" ]; then
  echo ">> Building libpng $LIBPNG_VER"
  src="$TC/downloads/libpng-$LIBPNG_VER"
  rm -rf "$src"
  curl -fL --retry 3 -o "$src.tar.gz" \
    "https://github.com/pnggroup/libpng/archive/refs/tags/v$LIBPNG_VER.tar.gz"
  tar -xzf "$src.tar.gz" -C "$TC/downloads"
  cp "$src/scripts/pnglibconf.h.prebuilt" "$src/pnglibconf.h"
  mkdir -p "$TC/libpng/include" "$TC/libpng/lib" "$src/obj"
  for f in png pngerror pngget pngmem pngpread pngread pngrio pngrtran pngrutil \
           pngset pngtrans pngwio pngwrite pngwtran pngwutil; do
    gcc -O2 -DPNG_ARM_NEON_OPT=0 -DPNG_INTEL_SSE_OPT=0 -I"$src" \
       -c "$src/$f.c" -o "$src/obj/$f.o"
  done
  ar rcs "$TC/libpng/lib/libpng.a" "$src"/obj/*.o
  cp "$src/png.h" "$src/pngconf.h" "$src/pnglibconf.h" "$TC/libpng/include/"
fi
echo ">> libpng: $TC/libpng/lib/libpng.a"
echo
echo "Toolchain ready. Build with: scripts/build-rom.sh"
