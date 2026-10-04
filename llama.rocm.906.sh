#!/usr/bin/env bash
set -euo pipefail
# Builds llama.cpp targeting gfx1102 (RDNA 3) and gfx906 (vega 20)
# for debian but can be modified to work on ubuntu and other nix boxes with very minor path adjustments.
# Apply the patch from https://github.com/idragonfly-ai/rocm-patches/gfx906 before running this build.
# Change this to the path of your actual llama.cpp repository
TARGET_DIR="/repos/llama.cpp"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory $TARGET_DIR does not exist." >&2
    exit 1
fi

cd "$TARGET_DIR"

ACTIVE_LIB=$(readlink -f /usr/lib/x86_64-linux-gnu/librocblas.so || true)

if [ -z "$ACTIVE_LIB" ] || [ ! -e "$ACTIVE_LIB" ]; then
    ACTIVE_LIB=$(find /usr/lib/x86_64-linux-gnu -name "librocblas.so.*" | sort -V | tail -n 1)
fi

if [ -z "$ACTIVE_LIB" ]; then
    echo "Error: Could not determine active rocblas library version." >&2
    exit 1
fi

ACTIVE_ROCM_PATH=$(dirname "$ACTIVE_LIB")

echo "Active ROCm library path: $ACTIVE_ROCM_PATH"
echo "Active library file: $ACTIVE_LIB"

export ROCM_PATH="$ACTIVE_ROCM_PATH"
export LD_LIBRARY_PATH="$ACTIVE_ROCM_PATH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

echo "Exported ROCM_PATH=$ROCM_PATH"
echo "Exported LD_LIBRARY_PATH=$LD_LIBRARY_PATH"

if [ -d "build" ]; then
    echo "Cleaning existing build directory..."
    rm -rf build
fi

echo "Purging previous llama library installations..."
sudo rm -rf /usr/lib/x86_64-linux-gnu/llama
sudo rm -f /etc/ld.so.conf.d/llama.conf
sudo ldconfig

echo "Configuring cmake..."
HIPCXX="$(hipconfig -l)/clang"
HIP_PATH="$(hipconfig -R)"
HIP_DEVICE_LIB_PATH="$ACTIVE_ROCM_PATH" \

cmake -B build \
    -DCMAKE_C_COMPILER=/usr/bin/hipcc \
    -DCMAKE_CXX_COMPILER=/usr/bin/hipcc \
    -DCMAKE_PREFIX_PATH="$ACTIVE_ROCM_PATH" \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DGGML_HIP=ON \
    -DGPU_TARGETS="gfx1102;gfx906" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib/x86_64-linux-gnu/llama

echo "Building binaries..."
cmake --build build --config Release -j$(nproc)

echo "Installing compiled build..."
sudo cmake --install build

echo "Writing dynamic linker configuration for the llama library path..."
echo "/usr/lib/x86_64-linux-gnu/llama" | sudo tee /etc/ld.so.conf.d/llama.conf

echo "Updating dynamic linker cache..."
sudo ldconfig

echo "Custom installation and linker configuration completed successfully."
