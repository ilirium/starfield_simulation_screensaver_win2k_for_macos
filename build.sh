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

rm -rf "$SAVER" "$BUILD/${NAME}Preview" "$BUILD/obj"
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

echo
echo "built: $SAVER"
echo "       $BUILD/${NAME}Preview"
