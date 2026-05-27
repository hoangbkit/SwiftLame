#!/bin/bash
# Builds lame.xcframework for macOS 15.0+ (arm64 + x86_64)
# Output: Frameworks/lame.xcframework

set -euo pipefail

LAME_VERSION="3.100"
MIN_MACOS="15.0"
BUNDLE_VERSION="1.0.0"
OUTPUT_DIR="Frameworks"
LAME_FILE="lame-${LAME_VERSION}.tar.gz"
LAME_DIR="lame-${LAME_VERSION}"
SCRATCH=".build/scratch"
THIN=".build/thin"
FAT=".build/fat"
CONFIGURE_FLAGS="--disable-shared --disable-frontend --disable-debug --disable-dependency-tracking"

log()   { echo -e "\033[1;32m[$(date '+%H:%M:%S')]\033[0m $1"; }
info()  { echo -e "  \033[1;33m→\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; exit 1; }

cleanup() { log "Cleaning up"; rm -rf .build "$LAME_DIR"; }
trap cleanup EXIT

download_lame() {
    log "Checking for LAME ${LAME_VERSION} source"
    if [[ -f "$LAME_FILE" ]]; then
        info "Found cached $LAME_FILE"
    else
        info "Downloading $LAME_FILE..."
        curl -fSL -o "$LAME_FILE" \
            "https://altushost-swe.dl.sourceforge.net/project/lame/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz" \
        || error "Download failed. Manually place lame-${LAME_VERSION}.tar.gz here and re-run."
    fi
    file -b --mime-type "$LAME_FILE" | grep -q "gzip" \
        || { rm -f "$LAME_FILE"; error "Invalid archive. Delete and re-run."; }
}

extract_lame() {
    log "Extracting $LAME_FILE"
    rm -rf "$LAME_DIR"
    tar xf "$LAME_FILE" || error "Failed to extract $LAME_FILE"
}

compile() {
    local arch="$1" host="$2"
    local scratch_dir="${SCRATCH}/${arch}" thin_dir="${THIN}/${arch}"
    local cwd; cwd="$(pwd)"
    info "Compiling for ${arch}"

    local sdk_path; sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
    local clang;    clang="$(xcrun --sdk macosx --find clang)"

    # -Wno-implicit-function-declaration: fixes memset/bcopy errors in LAME 3.100
    # on modern Clang which treats implicit declarations as hard errors
    local flags="-arch ${arch} -isysroot ${sdk_path} -mmacos-version-min=${MIN_MACOS} -Wno-implicit-function-declaration"

    mkdir -p "$scratch_dir"
    pushd "$scratch_dir" > /dev/null

    "$cwd/$LAME_DIR/configure" $CONFIGURE_FLAGS \
        --host="$host" \
        --prefix="$cwd/$thin_dir" \
        CC="$clang" \
        CFLAGS="$flags" \
        LDFLAGS="-arch ${arch} -isysroot ${sdk_path} -mmacos-version-min=${MIN_MACOS}" \
        > configure.log 2>&1 || error "configure failed for ${arch}. See ${scratch_dir}/configure.log"

    make -j"$(sysctl -n hw.ncpu)" install \
        > make.log 2>&1 || error "make failed for ${arch}. See ${scratch_dir}/make.log"

    popd > /dev/null
    info "Done: ${arch}"
}

make_fat() {
    log "Creating universal library"
    mkdir -p "$FAT/lib"
    for lib in "$THIN/arm64/lib/"*.a; do
        local name; name="$(basename "$lib")"
        lipo -create "$THIN/arm64/lib/$name" "$THIN/x86_64/lib/$name" -output "$FAT/lib/$name"
        info "lipo: $name"
    done
    cp -rf "$THIN/arm64/include" "$FAT/"
}

make_framework() {
    local dest="$1" fw="${1}/lame.framework"
    log "Creating framework"
    rm -rf "$fw"

    # Create proper versioned bundle structure (required for macOS frameworks)
    mkdir -p "$fw/Versions/A/Headers"
    mkdir -p "$fw/Versions/A/Modules"
    mkdir -p "$fw/Versions/A/Resources"

    # Versions/Current -> A
    ln -sf A "$fw/Versions/Current"

    # Top-level symlinks -> Versions/Current/...
    ln -sf Versions/Current/Headers   "$fw/Headers"
    ln -sf Versions/Current/Modules   "$fw/Modules"
    ln -sf Versions/Current/Resources "$fw/Resources"
    ln -sf Versions/Current/lame      "$fw/lame"

    # Copy files into Versions/A
    printf 'framework module lame {\n    header "lame.h"\n    export *\n}\n' \
        > "$fw/Versions/A/Modules/module.modulemap"
    cp -f "$FAT/include/lame/lame.h" "$fw/Versions/A/Headers/"
    cp -f "$FAT/lib/libmp3lame.a"    "$fw/Versions/A/lame"

    # Info.plist goes in Versions/A/Resources (NOT at framework root)
    cat > "$fw/Versions/A/Resources/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>com.lame.framework</string>
    <key>CFBundleName</key><string>lame</string>
    <key>CFBundleVersion</key><string>${BUNDLE_VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${BUNDLE_VERSION}</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleExecutable</key><string>lame</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>MinimumOSVersion</key><string>${MIN_MACOS}</string>
    <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
</dict></plist>
PLIST
}

make_xcframework() {
    local fw_dir=".build/framework" out="${OUTPUT_DIR}/lame.xcframework"
    make_framework "$fw_dir"
    log "Creating xcframework"
    mkdir -p "$OUTPUT_DIR"
    rm -rf "$out"
    xcodebuild -create-xcframework -framework "${fw_dir}/lame.framework" -output "$out" \
        || error "xcodebuild failed"
    log "✅ Done → $out"
}

main() {
    log "Building LAME ${LAME_VERSION} — macOS ${MIN_MACOS}+ (arm64 + x86_64)"
    download_lame
    extract_lame
    compile arm64  arm-apple-darwin
    compile x86_64 x86_64-apple-darwin
    make_fat
    make_xcframework
}

main