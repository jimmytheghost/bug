#!/bin/bash
# Local-only LAME build. No Homebrew/global installation. ARCHS may be "arm64 x86_64".
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Resources/Encoder"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/bug-encoder.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"
URL='https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz'
SHA='ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e'
if ! curl --fail --location --retry 2 "$URL" -o "$WORK/lame.tar.gz"; then
  curl --fail --location --retry 2 'https://download.videolan.org/pub/contrib/lame/lame-3.100.tar.gz' -o "$WORK/lame.tar.gz"
fi
printf '%s  %s\n' "$SHA" "$WORK/lame.tar.gz" | shasum -a 256 -c -
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
ARCH_LIST="${ARCHS:-$(uname -m)}"
LIBS=()
for ARCH in $ARCH_LIST; do
  case "$ARCH" in arm64) HOST=aarch64-apple-darwin ;; x86_64) HOST=x86_64-apple-darwin ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; esac
  mkdir "$WORK/$ARCH"
  tar -xzf "$WORK/lame.tar.gz" -C "$WORK/$ARCH"
  (
    cd "$WORK/$ARCH/lame-3.100"
    # LAME 3.100's Darwin export list includes removed/deactivated APIs.
    # Build-only patch: drop obsolete init and disabled decoder exports.
    sed -E '/^lame_init_old$/d; /^lame_decode/d; /^hip_/d' include/libmp3lame.sym > include/libmp3lame.sym.fixed
    mv include/libmp3lame.sym.fixed include/libmp3lame.sym
    CC="$(xcrun -f clang)" CFLAGS="-O2 -std=gnu89 -arch $ARCH -mmacosx-version-min=15.0" LDFLAGS="-arch $ARCH -mmacosx-version-min=15.0" \
      ./configure --host="$HOST" --disable-static --enable-shared --disable-frontend --disable-decoder --disable-nasm --prefix="$WORK/install-$ARCH" || { cat config.log >&2; exit 1; }
    make -j "$(sysctl -n hw.ncpu)"
  )
  LIBS+=("$WORK/$ARCH/lame-3.100/libmp3lame/.libs/libmp3lame.0.dylib")
done
xcrun lipo -create "${LIBS[@]}" -output "$WORK/libmp3lame.dylib"
install_name_tool -id '@rpath/libmp3lame.dylib' "$WORK/libmp3lame.dylib"
codesign --force --sign - "$WORK/libmp3lame.dylib"
cp "$WORK/libmp3lame.dylib" "$OUT/libmp3lame.dylib"
cp "$WORK/${ARCH_LIST%% *}/lame-3.100/COPYING" "$OUT/COPYING.LAME"
# Ship corresponding unmodified source alongside the library for LGPL compliance.
cp "$WORK/lame.tar.gz" "$OUT/lame-3.100.tar.gz"
printf 'Built %s for %s\n' "$OUT/libmp3lame.dylib" "$ARCH_LIST"
