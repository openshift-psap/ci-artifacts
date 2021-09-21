#! /usr/bin/env bash

set -o pipefail
set -o errexit
set -o nounset

set -x

MACHINE_TYPE=${1:-}
shift || true
ENTITLEMENT_PEM=${1:-}

usage() {
    echo "$0 MACHINE_TYPE [ENTITLEMENT_PEM]"
    exit 1
}

if [[ -z "${MACHINE_TYPE}" ]]; then
    echo "FATAL: MACHINE_TYPE must be provided."
    exit 1
fi

THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd ${THIS_DIR}/../..

if [ -z "${ARTIFACT_DIR:-}" ]; then
    export ARTIFACT_DIR="/tmp/ci-artifacts_$(date +%Y%m%d)"
    echo "Using '$ARTIFACT_DIR' to store the test artifacts (default value for ARTIFACT_DIR)."
else
    echo "Using '$ARTIFACT_DIR' to store the test artifacts."
fi

# Entitlement

echo "INFO: Testing if the cluster is already entitled ..."
if !./run_toolbox.py entitlement test_cluster --no_inspect; then
    if [[ -z "${ENTITLEMENT_PEM}" ]]; then
        echo "FATAL: ENTITLEMENT_PEM must be provided when the cluster is not entitled."
        exit 1
    fi

    echo "INFO: Deploying the entitlement with PEM key from ${ENTITLEMENT_PEM}"
    ./run_toolbox.py entitlement deploy "${ENTITLEMENT_PEM}"

    if ! ./run_toolbox.py entitlement wait; then
        echo "FATAL: Failed to properly entitle the cluster, cannot continue."
        exit 1
    fi
fi

source $THIS_DIR/../nightly/gpu-operator.sh source
set -x

# NFD

if ! ./run_toolbox.py nfd has_labels; then
    ./run_toolbox.py nfd_operator deploy_from_operatorhub

fi


# GPU Node

if [[ "$MACHINE_TYPE" != "p4d.24xlarge" ]]; then
    ./run_toolbox.py cluster set_scale "$MACHINE_TYPE" 1
else
    P4D_REGION=1b
    REGION_MACHINESET=$(oc get machinesets -n openshift-machine-api -oname | grep -- "$P4D_REGION"'$' | cut -d/ -f2)
    ./run_toolbox.py cluster set_scale "$MACHINE_TYPE" 1 --base-machineset="${REGION_MACHINESET}"
fi

if ! ./run_toolbox.py nfd has_gpu_nodes; then
    echo "FATAL: no GPU node in the cluster ..."
    exit 1
fi

GPU_OPERATOR_NS=openshift-operators
if [[ -z "$(oc get pods -lapp=gpu-operator -n $GPU_OPERATOR_NS)" ]]; then
    ./run_toolbox.py gpu_operator deploy_from_operatorhub openshift-operators
fi

./run_toolbox.py gpu_operator wait_deployment

echo "Installation done"

cat <<EOF
Nodes with MIG-capable GPUs:
----------------------------

$(oc get nodes -l nvidia.com/gpu.deploy.mig-manager=true --no-headers)

Change MIG configuration:
-------------------------

NODE_NAME=$(oc get nodes -l nvidia.com/gpu.deploy.mig-manager=true -oname | head -1)
MIG_CONFIGURATION=all-2g.10gb
oc label \$NODE_NAME nvidia.com/mig.config=\$MIG_CONFIGURATION --overwrite

Change MIG advertisement strategy:
----------------------------------

MIG_STRATEGY=single # or mixed or none
oc patch clusterpolicy/gpu-cluster-policy --type='json' -p='[{"op": "replace", "path": "/spec/mig/strategy", "value": '\$MIG_STRATEGY'}]'


EOF
