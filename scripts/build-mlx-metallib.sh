#!/bin/sh
set -eu

PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
BUILD_DIR="$(cd "$PROJECT_DIR" && swift build --disable-sandbox -c "$CONFIGURATION" --show-bin-path)"
METAL_SOURCE_DIR="$PROJECT_DIR/.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
OUTPUT="$BUILD_DIR/mlx.metallib"
WORK_DIR="$PROJECT_DIR/.build/tracket-mlx-metal-$CONFIGURATION"

if [ ! -d "$METAL_SOURCE_DIR" ]; then
    echo "error: MLX Metal sources are missing; run swift package resolve first" >&2
    exit 1
fi

NEEDS_BUILD=0
if [ ! -f "$OUTPUT" ]; then
    NEEDS_BUILD=1
elif find "$METAL_SOURCE_DIR" -type f \( -name '*.metal' -o -name '*.h' \) -newer "$OUTPUT" | grep -q .; then
    NEEDS_BUILD=1
fi

if [ "$NEEDS_BUILD" -eq 0 ]; then
    echo "Using cached MLX Metal library: $OUTPUT"
    exit 0
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
INDEX=0
find "$METAL_SOURCE_DIR" -type f -name '*.metal' | sort | while IFS= read -r SOURCE; do
    INDEX=$((INDEX + 1))
    AIR_FILE="$WORK_DIR/kernel-$INDEX.air"
    xcrun -sdk macosx metal \
        -c \
        -target air64-apple-macos14.0 \
        -I "$METAL_SOURCE_DIR" \
        -fno-fast-math \
        -Wno-c++17-extensions \
        -Wno-c++20-extensions \
        "$SOURCE" \
        -o "$AIR_FILE"
done

set -- "$WORK_DIR"/*.air
if [ ! -e "$1" ]; then
    echo "error: MLX Metal compilation produced no AIR files" >&2
    exit 1
fi
xcrun -sdk macosx metallib "$@" -o "$OUTPUT"
echo "Built MLX Metal library: $OUTPUT"
