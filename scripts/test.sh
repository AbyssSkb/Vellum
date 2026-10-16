#!/bin/bash
set -euo pipefail

TEST_WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/vellum-tests.XXXXXX")"
trap 'rm -rf "$TEST_WORKSPACE"' EXIT
export VELLUM_AI_LOG_DIR="$TEST_WORKSPACE/ai-logs"

# AppKit/PDFKit fixtures share application focus and the main run loop.
swift test --no-parallel --xunit-output "$TEST_WORKSPACE/results.xml" "$@"

# A test process can exit successfully before Swift Testing finishes its run.
if ! /usr/bin/xmllint --noout "$TEST_WORKSPACE/results-swift-testing.xml"; then
    echo "error: Swift Testing exited without a complete test report." >&2
    exit 1
fi
