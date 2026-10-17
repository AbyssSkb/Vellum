#!/bin/bash
set -euo pipefail

TEST_WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/vellum-tests.XXXXXX")"
trap 'rm -rf "$TEST_WORKSPACE"' EXIT
export VELLUM_AI_LOG_DIR="$TEST_WORKSPACE/ai-logs"

run_tests() {
    local results_dir test_status=0
    results_dir="$(mktemp -d "$TEST_WORKSPACE/results.XXXXXX")"
    # AppKit/PDFKit fixtures share application focus and the main run loop.
    swift test --no-parallel --xunit-output "$results_dir/results.xml" "$@" || test_status=$?

    # A test process can exit successfully before Swift Testing finishes its run.
    if ! /usr/bin/xmllint --noout "$results_dir/results-swift-testing.xml"; then
        echo "error: Swift Testing exited without a complete test report." >&2
        return 1
    fi
    return "$test_status"
}

if [[ $# -gt 0 ]]; then
    run_tests "$@"
    exit
fi

# Isolate app window lifecycles and bound PDFKit's background analysis.
swift test list > "$TEST_WORKSPACE/tests.txt"
awk -F/ '{
    if ($1 ~ /^VellumAppTests[.]/) {
        sub(/\(.*/, "[(]", $2)
        print $1 "/" $2
    } else {
        print $1 "/"
    }
}' "$TEST_WORKSPACE/tests.txt" | sort -u > "$TEST_WORKSPACE/filters.txt"
if [[ ! -s "$TEST_WORKSPACE/filters.txt" ]]; then
    echo "error: No tests found." >&2
    exit 1
fi

test_status=0
while IFS= read -r test_filter; do
    run_tests --skip-build --filter "^${test_filter//./[.]}" || test_status=1
done < "$TEST_WORKSPACE/filters.txt"
exit "$test_status"
