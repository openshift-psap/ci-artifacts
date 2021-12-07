#! /usr/bin/env bash

set -o pipefail
set -o errexit
set -o nounset

# This script is executed from `ci-artifacts` PR, when requesting
# `\test custom`.
#
# It looks at the message of the last commit of the PR (2nd parent of
# HEAD merge commit), and scans it for a test-path directive:
# > test-path: testing/.../test.sh [flags]
# and executes the test command.
#
# Calling this script on a commit without a `test-path` fails the test
# (exit 1).


THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
BASE_DIR="${THIS_DIR}/../"
cd "$BASE_DIR"

ANCHOR="test-path: "

commit="HEAD"
parent=$(git log --pretty=%P -n 1 $commit)

if grep -q " " <<< "$parent"; then
    commit=$(sed 's/ /../g' <<< "$parent")
    echo "HEAD is a merge commit. Taking all the commit in $commit"
    number=""
else
    echo "HEAD is a simple commit."
    number="-n 1"
fi

git show --quiet "$commit"

echo ""

testpaths=$(git log --format=%B $number $commit | { grep -i "$ANCHOR" || true ;} | cut -b$(echo "$ANCHOR" | wc -c)-)

if [[ -z "$testpaths" ]]; then
    echo "Nothing to test in $commit."
    exit 1
fi

BASE_ARTIFACT_DIR=${ARTIFACT_DIR}

while read cmd;
do
    basename=$(basename "$cmd" | sed 's/ /_/g')

    echo "Running test-path: $cmd"
    echo ""
    export ARTIFACT_DIR="${BASE_ARTIFACT_DIR}/${basename}"
    echo "Using ARTIFACT_DIR=${ARTIFACT_DIR}"
    echo
    mkdir -p "${ARTIFACT_DIR}"
    bash ${THIS_DIR}/run $(echo "$cmd")  |& tee "${ARTIFACT_DIR}/test-log.txt"
    echo ""
done <<< "$testpaths"

echo "All done."
