#!/bin/zsh

set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
application_path="$repository_root/dist/Bonk.app"
contents_path="$application_path/Contents"
build_arguments=(-c release)

if [[ -n "${BONK_SDK_PATH:-}" ]]; then
    build_arguments+=(--disable-sandbox --sdk "$BONK_SDK_PATH")
fi

if [[ -n "${BONK_CACHE_PATH:-}" ]]; then
    build_arguments+=(--cache-path "$BONK_CACHE_PATH")
fi

cd "$repository_root"
swift build "${build_arguments[@]}"
binary_directory="$(swift build "${build_arguments[@]}" --show-bin-path)"

if [[ -d "$application_path" ]]; then
    /bin/rm -rf -- "$application_path"
fi

/bin/mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
/bin/cp "$binary_directory/Bonk" "$contents_path/MacOS/Bonk"
/bin/cp "$repository_root/Packaging/Info.plist" "$contents_path/Info.plist"
/usr/bin/plutil -lint "$contents_path/Info.plist"
/usr/bin/codesign --force --deep --sign - "$application_path"

echo "Built $application_path"
