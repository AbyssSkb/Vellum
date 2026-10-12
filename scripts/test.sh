#!/bin/bash
set -euo pipefail

TEST_WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/vellum-tests.XXXXXX")"
trap 'rm -rf "$TEST_WORKSPACE"' EXIT
export VELLUM_AI_LOG_DIR="$TEST_WORKSPACE/ai-logs"

# AppKit/PDFKit fixtures share application focus and the main run loop.
swift test --no-parallel "$@"
