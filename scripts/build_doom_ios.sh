#!/bin/bash
# Reproducible GPL-2.0 Doom core build for iOS device and simulator.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_COMMIT=e257a09527062bfb986b6e5e0780839b6cbd5b71
ENGINE="$ROOT/DoomSource"
if [[ -d "$ENGINE/.git" ]]; then
  git -C "$ENGINE" fetch --quiet --depth 1 origin "$SOURCE_COMMIT"
  git -C "$ENGINE" checkout --quiet --detach "$SOURCE_COMMIT"
  git -C "$ENGINE" rev-parse HEAD > "$ENGINE/COMMIT_PINNED.txt"
elif [[ -f "$ENGINE/doomgeneric/doomgeneric.c" ]]; then
  test -f "$ENGINE/COMMIT_PINNED.txt"
  test "$(cat "$ENGINE/COMMIT_PINNED.txt")" = "$SOURCE_COMMIT"
else
  git clone --quiet https://github.com/ozkl/doomgeneric.git "$ENGINE"
  git -C "$ENGINE" fetch --quiet --depth 1 origin "$SOURCE_COMMIT"
  git -C "$ENGINE" checkout --quiet --detach "$SOURCE_COMMIT"
  git -C "$ENGINE" rev-parse HEAD > "$ENGINE/COMMIT_PINNED.txt"
fi
SDK="${1:-iphoneos}"
BUILD="$ROOT/BuildGenerated"
SRC="$ENGINE/doomgeneric"
mkdir -p "$BUILD"
OBJECTS=$(sed -n '/^SRC_DOOM = /s/^SRC_DOOM = //p' "$SRC/Makefile")
SDKROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
if [[ "$SDK" == "iphoneos" ]]; then ARCHS=(arm64); else ARCHS=(arm64 x86_64); fi
THIN_LIBS=()
for ARCH in "${ARCHS[@]}"; do
  if [[ "$SDK" == "iphoneos" ]]; then TARGET="$ARCH-apple-ios16.0";
  else TARGET="$ARCH-apple-ios16.0-simulator"; fi
  DIR="$BUILD/objects-$ARCH"
  mkdir -p "$DIR"
  rm -f "$DIR/"*.o
  for object in $OBJECTS; do
    [[ "$object" == "doomgeneric_xlib.o" ]] && continue
    name="${object%.o}"
    INPUT="$SRC/$name.c"
    if [[ "$name" == "i_system" ]]; then
      # iOS disallows system(). Legacy external shell hooks are disabled.
      INPUT="$BUILD/i_system_ios.c"
      printf 'static int doom_ios_system(const char *cmd) { (void)cmd; return -1; }\n' > "$INPUT"
      sed 's/system(/doom_ios_system(/g' "$SRC/i_system.c" >> "$INPUT"
    fi
    xcrun --sdk "$SDK" clang -target "$TARGET" -isysroot "$SDKROOT" \
      -std=gnu11 -O2 -fcommon -w -DNORMALUNIX -D_DEFAULT_SOURCE \
      -DDOOMGENERIC_RESX=320 -DDOOMGENERIC_RESY=200 \
      -I"$SRC" -c "$INPUT" -o "$DIR/$name.o"
  done
  xcrun --sdk "$SDK" clang -target "$TARGET" -isysroot "$SDKROOT" \
    -std=gnu11 -O2 -fcommon -w -DDOOMGENERIC_RESX=320 -DDOOMGENERIC_RESY=200 \
    -I"$SRC" -I"$ROOT/HelloIPhone" \
    -c "$ROOT/HelloIPhone/DoomBridge.c" -o "$DIR/DoomBridge.o"
  THIN="$BUILD/libdoom_$ARCH.a"
  rm -f "$THIN"
  xcrun ar rcs "$THIN" "$DIR/"*.o
  xcrun ranlib "$THIN"
  THIN_LIBS+=("$THIN")
done
rm -f "$BUILD/libdoom.a"
if [[ "${#THIN_LIBS[@]}" == "1" ]]; then
  cp "${THIN_LIBS[0]}" "$BUILD/libdoom.a"
else
  xcrun lipo -create "${THIN_LIBS[@]}" -output "$BUILD/libdoom.a"
fi
xcrun lipo -info "$BUILD/libdoom.a"
echo "DOOM_ENGINE_BUILD_PASS sdk=$SDK source=$SOURCE_COMMIT"
