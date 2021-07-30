#! /usr/bin/env bash

set -o pipefail
set -o errexit
set -o nounset

prepare_cluster_for_gpu_operator() {
    trap collect_must_gather ERR

    ./run_toolbox.py cluster capture_environment
    entitle.sh

    if ! ./run_toolbox.py nfd has_labels; then
        ./run_toolbox.py nfd_operator deploy_from_operatorhub
    fi

    if ! ./run_toolbox.py nfd has_gpu_nodes; then
        ./run_toolbox.py cluster set_scale g4dn.xlarge 1
        ./run_toolbox.py nfd wait_gpu_nodes
    fi
}

collect_must_gather() {
    set +x
    echo "Running gpu-operator_gather ..."
    /usr/bin/gpu-operator_gather &> /dev/null

    export TOOLBOX_SCRIPT_NAME=toolbox/gpu-operator/must-gather.sh

    COMMON_SH=$(
        bash -c 'source toolbox/_common.sh;
                 echo "8<--8<--8<--";
                 # only evaluate these variables from _common.sh
                 env | egrep "(^ARTIFACT_EXTRA_LOGS_DIR=)"'
             )
    ENV=$(echo "$COMMON_SH" | tac | sed '/8<--8<--8<--/Q' | tac) # keep only what's after the 8<--
    eval $ENV

    echo "Running gpu-operator_gather ... copying results to $ARTIFACT_EXTRA_LOGS_DIR"

    cp -r /must-gather/* "$ARTIFACT_EXTRA_LOGS_DIR"

    echo "Running gpu-operator_gather ... finished."
}

validate_gpu_operator_deployment() {
    trap collect_must_gather EXIT

    ./run_toolbox.py gpu_operator wait_deployment
    ./run_toolbox.py gpu_operator run_gpu_burn
}

test_master_branch() {
    prepare_cluster_for_gpu_operator
    ./run_toolbox.py gpu_operator deploy_from_bundle --bundle=master

    validate_gpu_operator_deployment --bundle=master
}

test_commit() {
    gpu_operator_git_repo="${1:-}"
    gpu_operator_git_ref="${2:-}"
    CI_IMAGE_GPU_COMMIT_CI_IMAGE_UID="ci-image"

    if [[ -z "$gpu_operator_git_repo" || -z "$gpu_operator_git_ref" ]]; then
        echo "FATAL: test_commit must receive a git repo/ref to be tested."
        return 1
    fi

    echo "Using Git repository ${gpu_operator_git_repo} with ref ${gpu_operator_git_ref}"

    prepare_cluster_for_gpu_operator

    GPU_OPERATOR_QUAY_BUNDLE_PUSH_SECRET=${GPU_OPERATOR_QUAY_BUNDLE_PUSH_SECRET:-"/var/run/psap-entitlement-secret/openshift-psap-openshift-ci-secret.yml"}
    GPU_OPERATOR_QUAY_BUNDLE_IMAGE_NAME=${GPU_OPERATOR_QUAY_BUNDLE_IMAGE_NAME:-"quay.io/openshift-psap/ci-artifacts"}

    ./run_toolbox.py gpu_operator bundle_from_commit "${gpu_operator_git_repo}" \
                                             "${gpu_operator_git_ref}" \
                                             "${GPU_OPERATOR_QUAY_BUNDLE_PUSH_SECRET}" \
                                             "${GPU_OPERATOR_QUAY_BUNDLE_IMAGE_NAME}" \
                                             --tag_uid="${CI_IMAGE_GPU_COMMIT_CI_IMAGE_UID}"

    ./run_toolbox.py gpu_operator deploy_from_bundle "--bundle=${GPU_OPERATOR_QUAY_BUNDLE_IMAGE_NAME}:operator_bundle_gpu-operator-ci-image"

    validate_gpu_operator_deployment
}

test_driver_toolkit() {
    trap collect_must_gather EXIT

    # ensure that the cluster is not entitled
    echo "INFO: Testing if the cluster is already entitled ..."
    if ./run_toolbox.py entitlement test_cluster --no_inspect; then
        echo "INFO: Cluster already entitled :("
        exit 1
    fi
    echo "###"
    echo "### Cluster is not entitled"
    echo "###"

    # install the NFD Operator
    ./run_toolbox.py nfd_operator deploy_from_operatorhub

    # install the last published version of the GPU Operator
    ./run_toolbox.py gpu_operator deploy_from_operatorhub

    # disable the driver DaemonSet
    oc patch clusterpolicy/gpu-cluster-policy \
       --type='json' \
       -p='[{"op": "replace", "path": "/spec/driver/enabled", "value": false}]'

    # restart the operator Pod (only required because we patched the
    # ClusterPolicy after its creation)
    oc delete pod -lapp.kubernetes.io/component=gpu-operator -n openshift-operators

    # create the driver-toolkit daemonset
    OCP_VERSION=$(oc get clusterversion/version -ojsonpath={.status.desired.version})
    DRIVER_TOOLKIT_IMAGE=$(oc adm release info $OCP_VERSION --image-for=driver-toolkit)
    echo "OCP VERSION: $OCP_VERSION"
    echo "DRIVER_TOOLKIT_IMAGE: $DRIVER_TOOLKIT_IMAGE"

    cat ${HOME}/gpu-operator_driver-toolkit.yml \
        | sed "s|{{ DRIVER_TOOLKIT_IMAGE }}|$DRIVER_TOOLKIT_IMAGE|" \
        > $ARTIFACT_DIR/gpu-operator_driver-toolkit.yml

    oc apply -f $ARTIFACT_DIR/gpu-operator_driver-toolkit.yml

    # add a GPU node to the cluster
    ./run_toolbox.py cluster set_scale g4dn.xlarge 1

    # wait and validate the deployment
    validate_gpu_operator_deployment
}

test_operatorhub() {
    if [ "${1:-}" ]; then
        OPERATOR_VERSION="--version=$1"
    fi
    shift || true
    if [ "${1:-}" ]; then
        OPERATOR_CHANNEL="--channel=$1"
    fi

    prepare_cluster_for_gpu_operator
    ./run_toolbox.py gpu_operator deploy_from_operatorhub ${OPERATOR_VERSION:-} ${OPERATOR_CHANNEL:-}
    validate_gpu_operator_deployment
}

test_helm() {
    if [ -z "${1:-}" ]; then
        echo "FATAL: run $0 should receive the operator version as parameter."
        exit 1
    fi
    OPERATOR_VERSION="$1"

    prepare_cluster_for_gpu_operator
    toolbox/gpu-operator/list_version_from_helm.sh
    toolbox/gpu-operator/deploy_with_helm.sh ${OPERATOR_VERSION}
    validate_gpu_operator_deployment
}

undeploy_operatorhub() {
    ./run_toolbox.py gpu_operator undeploy_from_operatorhub
}

if [ -z "${1:-}" ]; then
    echo "FATAL: $0 expects at least 1 argument ..."
    exit 1
fi

action="$1"
shift

set -x

case ${action} in
    "test_master_branch")
        ## currently broken
        #test_master_branch "$@"
        test_commit "https://github.com/NVIDIA/gpu-operator.git" master
        exit 0
        ;;
    "test_commit")
        test_driver_toolkit

        exit 0
        ;;
    "test_operatorhub")
        test_operatorhub "$@"
        exit 0
        ;;
    "validate_deployment")
        validate_gpu_operator_deployment "$@"
        exit 0
        ;;
    "test_helm")
        test_helm "$@"
        exit 0
        ;;
    "undeploy_operatorhub")
        undeploy_operatorhub "$@"
        exit 0
        ;;
    -*)
        echo "FATAL: Unknown option: ${action}"
        exit 1
        ;;
    *)
        echo "FATAL: Nothing to do ..."
        exit 1
        ;;
esac
