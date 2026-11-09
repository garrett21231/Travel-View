#!/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "$0")/.." && pwd)
vendor="$project_dir/Vendor"
version="3.14-b14"
asset="Python-3.14-iOS-support.b14.tar.gz"
checksum="703ff822529f46edcbcd8b88096b2544f6990f3109ad38b4b4b61bb489a7c1ee"

if [[ -f "$vendor/Python.xcframework/Info.plist" ]]; then
    echo "The iOS Python runtime is already installed in Vendor."
    exit 0
fi

mkdir -p "$vendor"
staging=$(mktemp -d "$vendor/.python-ios.XXXXXX")
trap 'rm -rf "$staging"' EXIT
archive=${1:-"$staging/$asset"}
if [[ $# -eq 0 ]]; then
    curl --fail --location --silent --show-error --output "$archive" \
        "https://github.com/beeware/Python-Apple-support/releases/download/$version/$asset"
fi

actual_checksum=$(shasum -a 256 < "$archive")
if [[ ${actual_checksum%% *} != "$checksum" ]]; then
    echo "The iOS Python archive did not match its published SHA-256 checksum." >&2
    exit 1
fi

tar -xzf "$archive" -C "$staging"
mv "$staging/Python.xcframework" "$vendor/"
echo "Installed the Python iOS runtime in Vendor/Python.xcframework."
