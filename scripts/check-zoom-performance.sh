#!/bin/bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
mode=run
case "${1:-}" in
  --build-only) mode=build; shift ;;
  --self-test) mode=self-test; shift ;;
esac
if [[ "$mode" == self-test && $# -ne 0 ]]; then
  echo "Usage: $0 --self-test" >&2
  exit 1
fi
if [[ "$mode" != self-test && ( $# -lt 1 || $# -gt 3 ) ]]; then
  echo "Usage: $0 [--build-only] PDF [OUTPUT_DIRECTORY] [MAX_GAP_MS]" >&2
  echo "       $0 --self-test" >&2
  exit 1
fi

if [[ "$mode" != self-test ]]; then
  test -f "$1" && test -r "$1" || { echo "PDF must be a readable file: $1" >&2; exit 1; }
  input_pdf="$(CDPATH= cd -- "$(dirname -- "$1")" && pwd)/$(basename -- "$1")"
fi
requested_output="${2:-}"
if [[ -n "$requested_output" && "$requested_output" != /* ]]; then
  requested_output="$PWD/$requested_output"
fi
cd "$ROOT_DIR"
# shortcut: The probe links native object maps; migrate when this deprecated backend is removed.
swift build --build-system native --configuration debug --target VellumCore
bin_dir="$(swift build --build-system native --configuration debug --show-bin-path)"
if [[ -n "$requested_output" ]]; then
  mkdir -- "$requested_output"
  output_dir="$(CDPATH= cd -- "$requested_output" && pwd)"
else
  output_dir="$(mktemp -d "$ROOT_DIR/.build/zoom-performance.XXXXXX")"
fi

app_dir="$output_dir/Vellum Zoom Performance Check.app"
contents_dir="$app_dir/Contents"
executable="$contents_dir/MacOS/ZoomPerformanceProbe"
plist="$contents_dir/Info.plist"
mkdir -p "$contents_dir/MacOS"
objects=()
while IFS= read -r -d '' object; do
  objects+=("$object")
done < <(xcrun swift -e '
import Foundation
guard let limit = Double(CommandLine.arguments[2]), limit.isFinite, limit > 0 else {
    FileHandle.standardError.write(Data("MAX_GAP_MS must be positive and finite\n".utf8))
    exit(1)
}
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let map = try JSONSerialization.jsonObject(with: data) as! [String: [String: String]]
for object in map.values.compactMap({ $0["object"] }).sorted() {
    FileHandle.standardOutput.write(Data(object.utf8) + Data([0]))
}
' "$bin_dir/VellumCore.build/output-file-map.json" "${3:-50}")
[[ ${#objects[@]} -gt 0 ]] || { echo "VellumCore object map is empty" >&2; exit 1; }
xcrun swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos15.0" \
  -g -I "$bin_dir/Modules" "$ROOT_DIR/scripts/zoom-performance-probe.swift" \
  "${objects[@]}" -o "$executable"
if [[ "$mode" == self-test ]]; then
  exec "$executable" --self-test
fi

cp -- "$input_pdf" "$output_dir/input.pdf"
/usr/bin/plutil -create xml1 "$plist"
for entry in \
  "CFBundleExecutable=ZoomPerformanceProbe" \
  "CFBundleName=Vellum Zoom Performance Check" \
  "CFBundleIdentifier=com.abyssskb.vellum.zoom-performance.$(uuidgen | tr '[:upper:]' '[:lower:]')" \
  "CFBundlePackageType=APPL" \
  "CFBundleVersion=1" \
  "LSMinimumSystemVersion=15.0" \
  "ProbePDF=$output_dir/input.pdf" \
  "ProbeResult=$output_dir/result.json" \
  "ProbeGapLimit=${3:-50}" \
  "ProbeRevision=$(git rev-parse HEAD)" \
  "ProbeArchitecture=$(uname -m)" \
  "ProbePDFSHA256=$(/usr/bin/shasum -a 256 "$output_dir/input.pdf" | awk 'NR == 1 { print $1 }')" \
  "ProbeZoomSourceSHA256=$(/usr/bin/shasum -a 256 Sources/VellumCore/PDF/View/VellumPDFView+ScrollZoomHelpers.swift | awk 'NR == 1 { print $1 }')"; do
  /usr/bin/plutil -insert "${entry%%=*}" -string "${entry#*=}" "$plist"
done
/usr/bin/plutil -insert NSHighResolutionCapable -bool true "$plist"
/usr/bin/codesign --force --sign - --timestamp=none "$app_dir"
echo "Probe: $app_dir"
echo "Result: $output_dir/result.json"
if [[ "$mode" == build ]]; then
  exit 0
fi
/usr/bin/open -n -W "$app_dir"
exec "$executable" --check-result "$output_dir/result.json"
