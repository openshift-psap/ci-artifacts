#! /usr/bin/env bash

set -o pipefail
set -o errexit
set -o nounset

prepare_cluster_for_nfd() {
    if ./run_toolbox.py nfd has_labels; then
        echo "FATAL: NFD labels found in the cluster"
        exit 1
    fi
    ./run_toolbox.py cluster capture_environment
}

validate_nfd_deployment() {
    if ! ./run_toolbox.py nfd wait_labels; then
        echo "FATAL: no NFD labels found."
        exit 1
    fi
}

test_master_branch() {
    CI_IMAGE_NFD_COMMIT_CI_REPO="${1:-https://github.com/openshift/cluster-nfd-operator.git}"

    echo "Using Git repository ${CI_IMAGE_NFD_COMMIT_CI_REPO} with ref ${CI_IMAGE_NFD_COMMIT_CI_REF}"

    CI_IMAGE_NFD_COMMIT_CI_IMAGE_TAG="${JOB_TYPE}-ci-image"

    prepare_cluster_for_nfd
    ./run_toolbox.py nfd_operator deploy_from_master "${CI_IMAGE_NFD_COMMIT_CI_REPO}" \
                                             --image-tag="${CI_IMAGE_NFD_COMMIT_CI_IMAGE_TAG}"
    validate_nfd_deployment
}

presubmit_job() {
    echo "${JOB_TYPE} ${PULL_NUMBER} with ref ${PULL_PULL_SHA}"

    PRESUBMIT_JOB_REPO="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"

    CI_IMAGE_NFD_COMMIT_CI_IMAGE_TAG="${JOB_TYPE}-ci-image"

    prepare_cluster_for_nfd
    ./run_toolbox.py nfd_operator presubmit_job "${PRESUBMIT_JOB_REPO}" \
                                                "${PULL_NUMBER}" "${PULL_BASE_REF}" \
                                                "${PULL_PULL_SHA}" \
                                                "${CI_IMAGE_NFD_COMMIT_CI_IMAGE_TAG}"
    validate_nfd_deployment
}

if [ -z "${1:-}" ]; then
    echo "FATAL: $0 expects at least 1 argument ..."
    exit 1
fi

action="$1"
shift

set -x

case ${action:-} in
    "test_master_branch")
        test_master_branch "$@"
        exit 0
        ;;
    "presubmit")
        presubmit_job
        exit 0
        ;;
    *)
        echo "FATAL: Unknown target \"${target}\""
        exit 1
        ;;
esac
