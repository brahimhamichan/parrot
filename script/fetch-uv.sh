#!/bin/sh
# Stage the pinned official uv binaries for a universal Parrot release.
set -eu
DIR=$1
DEST=$2
VERSION=0.13.8
BASE="https://github.com/astral-sh/uv/releases/download/$VERSION"
CACHE=${PARROT_UV_CACHE_DIR:-"$HOME/Library/Caches/Parrot-release/uv/$VERSION"}

fetch() {
    NAME="uv-$1-apple-darwin"
    ARCHIVE="$DIR/$NAME.tar.gz"
    CACHED="$CACHE/$NAME.tar.gz"
    if test -r "$CACHED" && printf '%s  %s\n' "$2" "$CACHED" | shasum -a 256 -c --status; then
        cp "$CACHED" "$ARCHIVE"
    else
        curl --fail --silent --show-error --location --retry 2 --max-time 120 "$BASE/$NAME.tar.gz" -o "$ARCHIVE"
    fi
    printf '%s  %s\n' "$2" "$ARCHIVE" | shasum -a 256 -c
    tar -xzf "$ARCHIVE" -C "$DIR" "$NAME/uv"
}

fetch aarch64 6b71028a6b904f2ae3340ef52e595512de807d06c0a20eaef2f692581b246558
fetch x86_64 a04c2ffeac28b2003a2c13caf538ab425fcd7def3e4a41571f4a8fb370a66af3
lipo -create "$DIR/uv-aarch64-apple-darwin/uv" "$DIR/uv-x86_64-apple-darwin/uv" -output "$DEST"
chmod +x "$DEST"
