#! /usr/bin/env bash

set -o pipefail
set -o errexit
set -o nounset

set -x

THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd ${THIS_DIR}/../..

if [ -z "${ARTIFACT_DIR:-}" ]; then
    export ARTIFACT_DIR="/tmp/ci-artifacts_$(date +%Y%m%d)"
    echo "Using '$ARTIFACT_DIR' to store the test artifacts (default value for ARTIFACT_DIR)."
else
    echo "Using '$ARTIFACT_DIR' to store the test artifacts."
fi

INSTALL_NFD_FROM_SOURCE=0
if [[ "$INSTALL_NFD_FROM_SOURCE" == 1 ]]; then
    touch "${ARTIFACT_DIR}/NFD_DEPLOYED_FROM_SOURCE"

    # install the NFD Operator from sources
    CI_IMAGE_NFD_COMMIT_CI_REPO="${1:-https://github.com/openshift/cluster-nfd-operator.git}"
    CI_IMAGE_NFD_COMMIT_CI_REF="${2:-master}"
    CI_IMAGE_NFD_COMMIT_CI_IMAGE_TAG="ci-image"
    ./run_toolbox.py nfd_operator deploy_from_commit "${CI_IMAGE_NFD_COMMIT_CI_REPO}" \
                     "${CI_IMAGE_NFD_COMMIT_CI_REF}"  \
                     --image-tag="${CI_IMAGE_NFD_COMMIT_CI_IMAGE_TAG}"
else
    touch "${ARTIFACT_DIR}/NFD_DEPLOYED_FROM_OPERATORHUB"
    ./run_toolbox.py nfd_operator deploy_from_operatorhub
fi


# add a GPU node to the cluster
./run_toolbox.py cluster set_scale g4dn.xlarge 2

# import the GPU Operator CI entrypoint functions
source testing/prow/gpu-operator.sh source
set -x
trap run_finalizers EXIT

# prepare_dtk_imagestream --> moved to gpu-operator.sh

finalizers+=("collect_must_gather")

# TEMPORARY: required while DTK imagestram not available in all the OCP versions
testing/recipes/prepare_dtk_imagestream.sh
# END TEMPORARY

# ensure that the cluster is not entitled
echo "INFO: Testing if the cluster is already entitled ..."
if ./run_toolbox.py entitlement test_cluster --no_inspect; then
    echo "WARNING: Cluster already entitled :("
    touch "${ARTIFACT_DIR}/CLUSTER_ENTITLED"
else
    echo "###"
    echo "### Cluster is not entitled"
    echo "###"
    touch "${ARTIFACT_DIR}/CLUSTER_NOT_ENTITLED"
fi

deploy_commit "https://gitlab.com/nvidia/kubernetes/gpu-operator.git" "master"

./run_toolbox.py gpu_operator wait_deployment

echo "INFO: all the tests completed successfully :)"
