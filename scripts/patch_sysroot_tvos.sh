#!/bin/sh
set -e

SRC_DIR="sysroot-ios-tci-arm64"
DST_DIR="sysroot-appletvos-tci-arm64"
BASEDIR="$(dirname "$0")"
# Get absolute path for patch_macho.py
command -v realpath >/dev/null 2>&1 || realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}
PATCH_MACHO_PY="$(realpath "$BASEDIR/patch_macho.py")"

if [ ! -d "$SRC_DIR" ]; then
    echo "Error: $SRC_DIR does not exist. Please download the iOS TCI sysroot first."
    exit 1
fi

echo "Copying $SRC_DIR to $DST_DIR..."
chmod -R 777 "$DST_DIR" 2>/dev/null || true
rm -rf "$DST_DIR"
cp -R "$SRC_DIR" "$DST_DIR"

patch_binary() {
    local file="$1"
    "$PATCH_MACHO_PY" "$file"
}

echo "Processing files in $DST_DIR..."
find "$DST_DIR" -type f | while read -r file; do
    if [[ "$file" == *.a ]]; then
        echo "Processing static library: $file"
        tmpdir=$(mktemp -d)
        cp "$file" "$tmpdir/"
        (
            cd "$tmpdir"
            ar -x "$(basename "$file")"
            rm "$(basename "$file")"
            for obj in *.o; do
                if [ -f "$obj" ]; then
                    "$PATCH_MACHO_PY" "$obj"
                fi
            done
            ar -cr "$(basename "$file")" *.o
        )
        mv "$tmpdir/$(basename "$file")" "$file"
        rm -rf "$tmpdir"
    elif [[ "$file" == *.dylib || "$file" == *.so || -x "$file" ]]; then
        patch_binary "$file"
    fi
done

echo "tvOS Sysroot patching complete!"
