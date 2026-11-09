#!/bin/bash
set -eo pipefail

case "$PLATFORM_NAME" in
    iphoneos|iphonesimulator) ;;
    *) exit 0 ;;
esac

runtime=Vendor/Python.xcframework
utils="$PROJECT_DIR/$runtime/build/utils.sh"
if [[ ! -f "$utils" ]]; then
    echo "error: Install the iOS Python runtime with bash scripts/setup-ios-python.sh." >&2
    exit 1
fi

# The pinned upstream helper leaves one redirect unquoted. Xcode bundle paths
# contain spaces, so quote it before using the helper to package extensions.
patched_utils="$TARGET_TEMP_DIR/TravelViewPythonUtils.sh"
sed 's@> ${FULL_EXT%.so}.fwork@> "${FULL_EXT%.so}.fwork"@' "$utils" > "$patched_utils"
source "$patched_utils"
export EXPANDED_CODE_SIGN_IDENTITY=${EXPANDED_CODE_SIGN_IDENTITY:--}

if [[ "$PLATFORM_NAME" == iphonesimulator && "$ARCHS" == *" "* ]]; then
    # Named simulators build a single slice. Generic builds can include both.
    ARCHS=arm64 install_stdlib "$runtime"
    stdlib=python/lib/python3.14
    intel="$PROJECT_DIR/$runtime/ios-arm64_x86_64-simulator/lib-x86_64/python3.14"
    destination="$CODESIGNING_FOLDER_PATH/$stdlib"
    rsync -a --exclude 'lib-dynload/' --exclude build-details.json "$intel/" "$destination/"
    for module in "$destination"/lib-dynload/*.so; do
        xcrun lipo -create "$module" "$intel/lib-dynload/${module##*/}" -output "$module.universal"
        mv "$module.universal" "$module"
    done
    process_dylibs "$runtime" "$stdlib/lib-dynload"
else
    install_python "$runtime"
fi
