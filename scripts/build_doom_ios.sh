#!/bin/bash
# Reproducible Doom engine static build for iOS. GPL-2.0: https://github.com/ozkl/doomgeneric
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_COMMIT=e257a09527062bfb986b6e5e0780839b6cbd5b71
ENGINE="$ROOT/DoomSource"
if [[ ! -e "$ENGINE/doomgeneric/doomgeneric.c" ]]; then
  git clone --quiet https://github.com/ozkl/doomgeneric.git "$ENGINE"
fi
git -C "$ENGINE" fetch --quiet --depth 1 origin "$SOURCE_COMMIT"
git -C "$ENGINE" checkout --quiet --detach "$SOURCE_COMMIT"
SDK="${1:-iphoneos}"
if [[ "$SDK" == "iphoneos" ]]; then
  TARGET="arm64-apple-ios16.0"
else
  TARGET="arm64-apple-ios16.0-simulator"
fi
BUILD="$ROOT/BuildGenerated"
mkdir -p "$BUILD/objects"
rm -f "$BUILD/objects/"*.o "$BUILD/libdoom.a"
SRC="$ENGINE/doomgeneric"
# Match the upstream core source list; explicitly omit desktop-specific backends.
OBJECTS=$(sed -n '/^SRC_DOOM = /s/^SRC_DOOM = //p' "$SRC/Makefile")
SDKROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
for object in $OBJECTS; do
  if [[ "$object" == "doomgeneric_xlib.o" ]]; then continue; fi
  name="${object%.o}"
  xcrun --sdk "$SDK" clang -target "$TARGET" -isysroot "$SDKROOT" \
    -std=gnu11 -O2 -fcommon -w -DNORMALUNIX -D_DEFAULT_SOURCE \
    -DDOOMGENERIC_RESX=320 -DDOOMGENERIC_RESY=200 \
    -I"$SRC" -c "$SRC/$name.c" -o "$BUILD/objects/$name.o"
done
xcrun --sdk "$SDK" clang -target "$TARGET" -isysroot "$SDKROOT" \
  -std=gnu11 -O2 -fcommon -w -DDOOMGENERIC_RESX=320 -DDOOMGENERIC_RESY=200 \
  -I"$SRC" -I"$ROOT/HelloIPhone" -c "$ROOT/HelloIPhone/DoomBridge.c" -o "$BUILD/objects/DoomBridge.o"
xcrun ar rcs "$BUILD/libdoom.a" "$BUILD/objects/"*.o
xcrun ranlib "$BUILD/libdoom.a"
echo "DOOM_ENGINE_BUILD_PASS sdk=$SDK source=$SOURCE_COMMIT"
