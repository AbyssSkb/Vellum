#!/bin/bash
set -euo pipefail

TEST_WORKSPACE="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/vellum-tests.XXXXXX")"
cleanup() {
    if [[ $? -eq 0 ]]; then
        rm -rf "$TEST_WORKSPACE"
    else
        echo "Test diagnostics retained at $TEST_WORKSPACE" >&2
    fi
}
trap cleanup EXIT
export VELLUM_AI_LOG_DIR="$TEST_WORKSPACE/ai-logs"

# Native SwiftPM emits the aggregate test bundle and its description metadata.
build_args=(--build-tests --build-system native)
test_args=()
skip_build=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --filter|--skip)
            if [[ $# -lt 2 ]]; then
                echo "error: $1 requires a test pattern." >&2
                exit 1
            fi
            test_args+=("$1" "$2")
            shift
            ;;
        --filter=*|--skip=*) test_args+=("${1%%=*}" "${1#*=}") ;;
        --skip-build) skip_build=true ;;
        --no-parallel) ;;
        *) build_args+=("$1") ;;
    esac
    shift
done

if [[ "$skip_build" == false ]]; then
    swift build "${build_args[@]}"
fi
bin_dir="$(swift build --show-bin-path "${build_args[@]}")"
test_binary="$(/usr/bin/plutil -extract builtTestProducts.0.binaryPath raw "$bin_dir/description.json")"
export VELLUM_TEST_BUNDLE="$(dirname "$(dirname "$(dirname "$test_binary")")")"
frameworks="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/Library/Frameworks"
xcrun swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos15.0" \
    -F "$frameworks" -Xlinker -rpath -Xlinker "$frameworks" \
    "$(dirname "$0")/test-host.swift" -o "$TEST_WORKSPACE/test-host"

run_tests() {
    local results_dir test_status=0
    results_dir="$(mktemp -d "$TEST_WORKSPACE/results.XXXXXX")"
    printf '%s\n' "$@" > "$results_dir/arguments.txt"
    # AppKit/PDFKit fixtures share application focus and the main run loop.
    "$TEST_WORKSPACE/test-host" --testing-library swift-testing --no-parallel \
        --xunit-output "$results_dir/results-swift-testing.xml" "$@" || test_status=$?
    printf '%s\n' "$test_status" > "$results_dir/exit-status.txt"

    # A test process can exit successfully before Swift Testing finishes its run.
    if ! /usr/bin/xmllint --noout "$results_dir/results-swift-testing.xml"; then
        echo "error: Swift Testing exited without a complete test report." >&2
        return 1
    fi
    return "$test_status"
}

if [[ ${#test_args[@]} -gt 0 ]]; then
    run_tests "${test_args[@]}"
    exit
fi

# Isolate app window lifecycles and bound PDFKit's background analysis.
"$TEST_WORKSPACE/test-host" --testing-library swift-testing --list-tests > "$TEST_WORKSPACE/tests.txt"
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
    run_tests --filter "^${test_filter//./[.]}" || test_status=1
done < "$TEST_WORKSPACE/filters.txt"
exit "$test_status"
