#!/bin/bash
set -euo pipefail

# Runs the production resolver and content renderer without opening the app.
repo="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -lt 2 || $# -gt 4 ]]; then
    echo "Usage: $0 PDF OUTPUT_DIR [SOURCE_ROOT] [BUILD_DIR]" >&2
    exit 2
fi
pdf="$1"
out="$2"
source_root="${3:-$repo}"
build="${4:-$out/native-build}"
mkdir -p "$build"
python3 - "$source_root" "$build" "$repo/scripts/reference-preview-audit.swift" <<'PY'
from pathlib import Path
import hashlib, json, sys
root, build, driver = map(Path, sys.argv[1:])
files = [
    'PDF/Geometry/PDFPageDisplayGeometry.swift', 'PDF/Geometry/PDFGraphicBounds.swift',
    'PDF/Selection/VisualLineGeometry.swift', 'PDF/Selection/VimTextSelectionModels.swift',
    'PDF/View/PDFFigurePreview.swift', 'PDF/View/PDFReferenceTextLayout.swift',
    'PDF/View/PDFReferenceTextStyle.swift', 'PDF/View/PDFReferenceObjectLayout.swift',
    'PDF/View/PDFReferencePreview.swift', 'PDF/View/VellumPDFView+Reference.swift',
    'PDF/View/PDFLinkNavigation.swift',
]
for path in sorted((root / 'Sources/VellumCore/PDF/View').glob('PDFReference*.swift')):
    rel = str(path.relative_to(root / 'Sources/VellumCore'))
    if rel not in files and path.name != 'PDFReferencePanel.swift': files.append(rel)
manifest = []
for rel in files:
    path = root / 'Sources/VellumCore' / rel
    data = path.read_bytes()
    manifest.append({'path': 'Sources/VellumCore/' + rel, 'sha256': hashlib.sha256(data).hexdigest()})
    text = data.decode()
    if path.name == 'VellumPDFView+Reference.swift':
        start = text.index('@MainActor\nfinal class PDFReferenceContent')
        text = '@preconcurrency import AppKit\n@preconcurrency import PDFKit\n\n' + text[start:text.index('@MainActor\nfinal class PDFReferenceController', start)]
    if path.name == 'PDFLinkNavigation.swift':
        text = text[:text.index('\nextension VellumPDFView')]
    (build / path.name.replace('+', '_')).write_text(text)
(build / 'Driver.swift').write_bytes(driver.read_bytes())
(build / 'AppText.swift').write_text('''enum AppText: CustomStringConvertible {
    case figurePreview(String), tablePreview(String), algorithmPreview(String), equationPreview(String), sectionPreview(String), footnotePreview(String)
    var description: String { switch self {
    case .figurePreview(let n): return "Figure " + n
    case .tablePreview(let n): return "Table " + n
    case .algorithmPreview(let n): return "Algorithm " + n
    case .equationPreview(let n): return "Equation " + n
    case .sectionPreview(let n): return "Section " + n
    case .footnotePreview(let n): return "Footnote " + n
    } }
}
''')
(build / 'source-manifest.json').write_text(json.dumps(manifest, indent=2))
(build / 'compile-flags').write_text('-D AUDIT_ADDITIONAL_FRAGMENTS' if 'additionalFragments:' in (build / 'VellumPDFView_Reference.swift').read_text() else '')
digest = hashlib.sha256()
for path in sorted(build.glob('*.swift')):
    digest.update(path.name.encode()); digest.update(path.read_bytes())
stamp = digest.hexdigest()
old = (build / 'compiled.sha256').read_text().strip() if (build / 'compiled.sha256').exists() else ''
(build / 'pending.sha256').write_text(stamp)
print('cached' if old == stamp and (build / 'native-audit').exists() else 'compile')
PY
if [[ ! -f "$build/compiled.sha256" ]] || ! cmp -s "$build/pending.sha256" "$build/compiled.sha256" || [[ ! -x "$build/native-audit" ]]; then
    swiftc -O -parse-as-library -swift-version 5 $(cat "$build/compile-flags") -module-cache-path "$build/module-cache" "$build/"*.swift -o "$build/native-audit"
    cp "$build/pending.sha256" "$build/compiled.sha256"
fi
mkdir -p "$out"
cp "$build/source-manifest.json" "$out/source-manifest.json"
"$build/native-audit" "$pdf" "$out"
