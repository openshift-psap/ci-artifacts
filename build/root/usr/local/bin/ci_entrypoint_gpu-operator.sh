#! /usr/bin/env bash

set -o pipefail
set -o errexit
set -o nounset

prepare_cluster_for_gpu_operator() {
    trap collect_must_gather ERR

    toolbox/cluster/capture_environment.sh
    entitle.sh

    if ! toolbox/nfd/has_nfd_labels.sh; then
        toolbox/nfd-operator/deploy_from_operatorhub.sh
    fi

    if ! toolbox/nfd/has_gpu_nodes.sh; then
        toolbox/cluster/set_scale.sh g4dn.xlarge 1
        toolbox/nfd/wait_gpu_nodes.sh
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

    toolbox/gpu-operator/wait_deployment.sh
    toolbox/gpu-operator/run_gpu_burn.sh
}

test_master_branch() {
    prepare_cluster_for_gpu_operator
    toolbox/gpu-operator/deploy_from_operatorhub.sh --from-bundle=master

    validate_gpu_operator_deployment
}

test_commit() {
    oc create secret generic mirror-secret \
       -n default \
       --from-file=mirror.pem=/var/run/psap-entitlement-secret/entitled-mirror-client-creds.pem
    cat << 'EOF' | oc create -f-
apiVersion: v1
kind: Pod
metadata:
 name: download-mirror
 namespace: default
spec:
 restartPolicy: Never
 containers:
 - name: test
   image: registry.access.redhat.com/ubi8/ubi-minimal:8.3
   command:
   - bash
   - -c
   - set -ex; mkdir /tmp/download/ && cd /tmp/download/ && time curl -E $CERT_FILE $DATASET_URL_BASE/$DATASET_FILENAME | md5sum || echo "FAILED :(";
   env:
   - name: DATASET_URL_BASE
     value: "https://mirror-dataset.apps.ci-mirror.psap.aws.rhperfscale.org/coco"
   - name: DATASET_FILENAME
     value: train2017.zip
   - name: CERT_FILE
     value: /etc/mirror-secret/mirror.pem
   volumeMounts:
   - name: mirror-secret
     mountPath: "/etc/mirror-secret"
     readOnly: true
 volumes:
 - name: mirror-secret
   secret:
     secretName: mirror-secret
EOF
    while true; do
        state=$(oc get pod/download-mirror \
           --no-headers \
           -ocustom-columns=phase:status.phase \
           -n default || true)
        echo "$state"
        if [[ "$state" == Succeeded || "$state" == Failed || "$state" == Error ]]; then
            break
        fi
        sleep 5
    done

    if [[ "${ARTIFACT_DIR:-}" ]]; then
        oc logs -f pod/download-mirror -n default > $ARTIFACT_DIR/download.log
    fi
    oc logs -f pod/download-mirror -n default
    oc delete pod/download-mirror -n default
    echo "final state: $state"
}

test_operatorhub() {
    OPERATOR_VERSION="${1:-}"
    OPERATOR_CHANNEL="${2:-}"

    prepare_cluster_for_gpu_operator
    toolbox/gpu-operator/deploy_from_operatorhub.sh ${OPERATOR_VERSION} ${OPERATOR_CHANNEL}
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
    toolbox/gpu-operator/undeploy_from_operatorhub.sh
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
        test_commit "https://github.com/NVIDIA/gpu-operator.git" master
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
