#!/bin/bash
# Builds Starfield.saver and the standalone preview harness.
# Command Line Tools are enough; full Xcode is not required.
set -euo pipefail
cd "$(dirname "$0")"

NAME=Starfield
BUILD=build
SAVER="$BUILD/$NAME.saver"
SDK=$(xcrun --show-sdk-path)

# Architectures for the shipped .saver, and the deployment floor.
#
# arm64 alone is a decision, not a limitation: Intel cross-compilation is
# verified working, and the loop plus the lipo step below already handle a
# second slice, so going universal means adding x86_64 to this one line.
# See aingineering/AING-0001-ci-and-distribution.md §7, question 2.
#
# 13.0 is the lowest target that links with Command Line Tools alone. Below it
# the compiler wants Swift back-deployment archives that ship arm64-only, so
# a lower floor would cost the Intel slice it was meant to buy. §2 has the
# probe output.
ARCHS=(arm64)
MIN_MACOS=13.0

# Developer tools are built for whatever machine is running the script; only
# the .saver is a shipping artifact and needs to honor ARCHS.
HOST_ARCH=$(uname -m)
SWIFTFLAGS=(-O -wmo -sdk "$SDK" -target "$HOST_ARCH-apple-macosx$MIN_MACOS")

# Sources shared by the bundle; main.swift belongs to the preview only.
LIB_SRC=(Sources/StarfieldEngine.swift Sources/StarfieldView.swift Sources/ConfigController.swift)

rm -rf "$SAVER" "$BUILD/${NAME}Preview" "$BUILD/Render" "$BUILD/LoadTest" \
       "$BUILD/EngineTests" "$BUILD/Thumbnail" "$BUILD/obj"
mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources" "$BUILD/obj"

echo "==> compiling saver (${ARCHS[*]}, macOS $MIN_MACOS+)"
SLICES=()
for arch in "${ARCHS[@]}"; do
    target="$arch-apple-macosx$MIN_MACOS"
    # A .saver is an MH_BUNDLE, which swiftc will not emit, so compile to an
    # object and let clang link it with -bundle. Dropping -wmo breaks this:
    # "cannot specify -o when generating multiple output files".
    xcrun swiftc -O -wmo -sdk "$SDK" -target "$target" \
        -module-name "$NAME" -parse-as-library \
        -emit-object -o "$BUILD/obj/$NAME-$arch.o" "${LIB_SRC[@]}"

    xcrun clang -bundle -isysroot "$SDK" -target "$target" \
        -o "$BUILD/obj/$NAME-$arch" "$BUILD/obj/$NAME-$arch.o" \
        -framework ScreenSaver -framework Cocoa \
        -L"$SDK/usr/lib/swift" -L/usr/lib/swift \
        -Xlinker -rpath -Xlinker /usr/lib/swift

    SLICES+=("$BUILD/obj/$NAME-$arch")
done

# A no-op at one architecture, which is the point: it is already here, so a
# universal build needs no new step.
xcrun lipo -create "${SLICES[@]}" -output "$SAVER/Contents/MacOS/$NAME"

cp Resources/Info.plist "$SAVER/Contents/Info.plist"
# Set the plist floor from MIN_MACOS so it cannot drift away from -target.
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MIN_MACOS" \
    "$SAVER/Contents/Info.plist" >/dev/null

# Everything that goes in the bundle must be in place before codesign runs.
# The signature seals Contents/Resources: adding a file afterwards breaks it
# with "a sealed resource is missing or invalid", and the failure is silent
# until macOS refuses to load the plugin. Hence the ordering here, and hence
# this step sitting above the signing step rather than below it.
#
# Thumbnail links StarfieldEngine alone -- no AppKit -- so building it here
# costs nothing and drags in no frameworks.
echo "==> generating preview thumbnails"
xcrun swiftc "${SWIFTFLAGS[@]}" -o "$BUILD/Thumbnail" \
    Sources/StarfieldEngine.swift Tools/Thumbnail/main.swift
"$BUILD/Thumbnail" "$SAVER/Contents/Resources"

# System Settings finds these by filename and renders them at a fixed size, so
# a wrong dimension is invisible until someone looks at the pane. Check before
# the signature seals them in.
while read -r file want_w want_h; do
    got_w=$(sips -g pixelWidth  "$SAVER/Contents/Resources/$file" | awk '/pixelWidth/{print $2}')
    got_h=$(sips -g pixelHeight "$SAVER/Contents/Resources/$file" | awk '/pixelHeight/{print $2}')
    if [ "$got_w" != "$want_w" ] || [ "$got_h" != "$want_h" ]; then
        echo "build.sh: $file is ${got_w}x${got_h}, expected ${want_w}x${want_h}" >&2
        exit 1
    fi
done <<'SIZES'
thumbnail.png 90 58
thumbnail@2x.png 180 116
SIZES

# The uninstaller travels inside the installation, so someone who emptied
# Downloads six months ago still has it. Sealed by the signature below.
cp uninstall.sh "$SAVER/Contents/Resources/uninstall.sh"
chmod +x "$SAVER/Contents/Resources/uninstall.sh"

echo "==> signing (ad hoc)"
codesign --force --deep --sign - --timestamp=none "$SAVER"

# Prove the seal actually covers what was just added. --strict is what catches
# a resource added after signing; without this the build would happily ship a
# bundle macOS then refuses.
codesign --verify --deep --strict "$SAVER"

echo "==> compiling preview harness"
xcrun swiftc "${SWIFTFLAGS[@]}" -o "$BUILD/${NAME}Preview" \
    "${LIB_SRC[@]}" Sources/main.swift \
    -framework ScreenSaver -framework Cocoa

# Render regenerates docs/assets/*.svg; LoadTest verifies the bundle the way macOS
# will. Both link the same sources as the saver, so they exercise real code.
echo "==> compiling tools"
xcrun swiftc "${SWIFTFLAGS[@]}" -o "$BUILD/Render" \
    "${LIB_SRC[@]}" Tools/Render/main.swift \
    -framework ScreenSaver -framework Cocoa
xcrun swiftc "${SWIFTFLAGS[@]}" -o "$BUILD/LoadTest" \
    Tools/LoadTest/main.swift \
    -framework ScreenSaver -framework Cocoa

# EngineTests links StarfieldEngine.swift alone -- no Cocoa, no ScreenSaver, no
# NSView. The engine is where arithmetic can regress, and staying framework-free
# means the suite runs on a headless CI machine whether or not AppKit will
# instantiate a view there.
xcrun swiftc "${SWIFTFLAGS[@]}" -o "$BUILD/EngineTests" \
    Sources/StarfieldEngine.swift Tools/EngineTests/main.swift

# Arithmetic first, then the bundle: a fidelity regression is a more specific
# failure than "the plugin would not load", so it should be the one reported.
echo "==> running engine tests"
"$BUILD/EngineTests"

# Pure shell and hermetic -- it overrides every directory uninstall.sh touches,
# so it never reaches the real ones. Cheap enough to run on every build.
echo "==> running uninstaller tests"
./Tools/uninstall-tests.sh

echo "==> verifying the bundle loads"
"$BUILD/LoadTest" "$SAVER"

echo
echo "built: $SAVER  ($(xcrun lipo -archs "$SAVER/Contents/MacOS/$NAME"), macOS $MIN_MACOS+)"
echo "       $BUILD/${NAME}Preview"
echo "       $BUILD/Render      (./build/Render <out-dir> [--svg docs/assets])"
echo "       $BUILD/LoadTest    (./build/LoadTest <path.saver>)"
echo "       $BUILD/EngineTests (./build/EngineTests)"
echo "       $BUILD/Thumbnail  (./build/Thumbnail <out-dir>)"
