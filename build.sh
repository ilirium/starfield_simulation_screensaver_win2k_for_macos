#!/bin/bash
# Builds Starfield.saver and the standalone preview harness.
# Command Line Tools are enough; full Xcode is not required.
set -euo pipefail
cd "$(dirname "$0")"

NAME=Starfield
BUILD=build
SAVER="$BUILD/$NAME.saver"
SDK=$(xcrun --show-sdk-path)
SWIFTFLAGS=(-O -wmo -sdk "$SDK" -target arm64-apple-macosx14.0)

# Sources shared by the bundle; main.swift belongs to the preview only.
LIB_SRC=(Sources/StarfieldEngine.swift Sources/StarfieldView.swift Sources/ConfigController.swift)

rm -rf "$SAVER" "$BUILD/${NAME}Preview" "$BUILD/Render" "$BUILD/LoadTest" \
       "$BUILD/EngineTests" "$BUILD/obj"
mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources" "$BUILD/obj"

echo "==> compiling saver"
# A .saver is an MH_BUNDLE, so compile to objects and let clang link with -bundle.
xcrun swiftc "${SWIFTFLAGS[@]}" -module-name "$NAME" -parse-as-library \
    -emit-object -o "$BUILD/obj/$NAME.o" "${LIB_SRC[@]}"

xcrun clang -bundle -isysroot "$SDK" -target arm64-apple-macosx14.0 \
    -o "$SAVER/Contents/MacOS/$NAME" "$BUILD/obj/$NAME.o" \
    -framework ScreenSaver -framework Cocoa \
    -L"$SDK/usr/lib/swift" -L/usr/lib/swift \
    -Xlinker -rpath -Xlinker /usr/lib/swift

cp Resources/Info.plist "$SAVER/Contents/Info.plist"

echo "==> signing (ad hoc)"
codesign --force --deep --sign - --timestamp=none "$SAVER"

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

echo "==> verifying the bundle loads"
"$BUILD/LoadTest" "$SAVER"

echo
echo "built: $SAVER"
echo "       $BUILD/${NAME}Preview"
echo "       $BUILD/Render      (./build/Render <out-dir> [--svg docs/assets])"
echo "       $BUILD/LoadTest    (./build/LoadTest <path.saver>)"
echo "       $BUILD/EngineTests (./build/EngineTests)"
