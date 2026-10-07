#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 update-archive release-notes-file release-tag" >&2
    exit 1
fi

if [ -z "${SPARKLE_PRIVATE_KEY:-}" ]; then
    echo "SPARKLE_PRIVATE_KEY is required to sign the update archive and appcast." >&2
    exit 1
fi

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SPARKLE_BIN="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin"
ARCHIVE_PATH="$1"
RELEASE_NOTES_PATH="$2"
RELEASE_TAG="$3"
ARCHIVE_NAME="$(basename "$ARCHIVE_PATH")"
ARCHIVES_DIR="$(mktemp -d)"
trap 'rm -rf "$ARCHIVES_DIR"' EXIT HUP INT TERM

cp "$ARCHIVE_PATH" "$ARCHIVES_DIR/$ARCHIVE_NAME"
cp "$RELEASE_NOTES_PATH" "$ARCHIVES_DIR/${ARCHIVE_NAME%.*}.txt"
printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_BIN/generate_appcast" \
    --ed-key-file - \
    --embed-release-notes \
    --maximum-deltas 0 \
    --download-url-prefix "https://github.com/AbyssSkb/Vellum/releases/download/$RELEASE_TAG/" \
    --link "https://github.com/AbyssSkb/Vellum/releases/tag/$RELEASE_TAG" \
    -o "$ARCHIVES_DIR/appcast.xml" \
    "$ARCHIVES_DIR"

SIGNATURE="$(/usr/bin/xmllint --xpath 'string(/rss/channel/item/enclosure/@*[local-name()="edSignature"])' "$ARCHIVES_DIR/appcast.xml")"
if [ -z "$SIGNATURE" ]; then
    echo "The update archive was not signed. Check that SPARKLE_PRIVATE_KEY matches Resources/UpdateSigningPublicKey.txt." >&2
    exit 1
fi

printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_BIN/sign_update" \
    --ed-key-file - --verify "$ARCHIVES_DIR/appcast.xml"
cp "$ARCHIVES_DIR/appcast.xml" "$(dirname "$ARCHIVE_PATH")/appcast.xml"
