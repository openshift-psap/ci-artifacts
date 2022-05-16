#! /bin/bash

set -o errexit
set -o pipefail
set -o nounset
set -x

#PSAP_ODS_SECRET_PATH="/var/run/psap-ods-secret-1"
PSAP_ODS_SECRET_PATH="/var/run/psap-entitlement-secret"
S3_LDAP_PROPS="${PSAP_ODS_SECRET_PATH}/s3_ldap.passwords"

ODS_CATALOG_VERSION="quay.io/modh/qe-catalog-source"
ODS_CATALOG_IMAGE_VERSION="v1100-6"

ODS_CI_TEST_NAMESPACE=loadtest
ODS_CI_REPO="https://github.com/openshift-psap/ods-ci.git"
ODS_CI_REF="multiuser"

ODS_CI_IMAGESTREAM="ods-ci"
ODS_CI_TAG="latest"

ODS_CI_NB_USERS=5
ODS_CI_USER_PREFIX=testuser

ODS_CI_USER_GROUP=rhods-users

LDAP_IDP_NAME=RHODS_CI_LDAP

# simulate two clusters

KUBECONFIG_DRIVER=/tmp/kubeconfig_driver # cluster driving the test
KUBECONFIG_SUTEST=/tmp/kubeconfig_sutest # system under test

cp "$KUBECONFIG" "$KUBECONFIG_DRIVER"
cp "$KUBECONFIG" "$KUBECONFIG_SUTEST"

switch_cluster() {
    cluster="$1"
    if [[ "$cluster" == "driver" ]]; then
        echo "Switching to the 'driver' cluster"
        export KUBECONFIG=$KUBECONFIG_DRIVER
    elif [[ "$cluster" == "sutest" ]]; then
        echo "Switching to the 'driver' cluster"
        export KUBECONFIG=$KUBECONFIG_DRIVER
    else
        echo "Requested to switch to an unknown cluster '$cluster', exiting."
        exit 1
    fi
}
# ---

export

oc_adm_groups_new_rhods_users() {
    group=$1
    shift
    user_prefix=$1
    shift
    nb_users=$1

    echo "Adding $nb_users user with prefix '$user_prefix' in the group '$group' ..."
    users=$(for i in $(seq 0 $nb_users); do echo ${user_prefix}$i; done)
    oc adm groups new $group $(echo $users)
}

# ---
i=0
wait_list=()

run_in_bg() {
    "$@" &
    echo "Adding '$!' to the wait-list '${wait_list[@]}' ..."
    wait_list+=("$!")
}

wait_bg_processes() {
    echo "Waiting for the background processes '${wait_list[@]}' to terminate ..."
    for pid in ${wait_list[@]}; do
        wait $pid # this syntax honors the `set -e` flag
    done
    echo "All the processes are done!"
}

prepare_driver_cluster() {
    switch_cluster "driver"

    oc create namespace "$ODS_CI_TEST_NAMESPACE" -oyaml --dry-run=client | oc apply -f-

    run_in_bg ./run_toolbox.py utils build_push_image \
                     "${ODS_CI_IMAGESTREAM}" "$ODS_CI_TAG" \
                     --namespace="$ODS_CI_TEST_NAMESPACE" \
                     --git-repo="$ODS_CI_REPO" \
                     --git-ref="$ODS_CI_REF" \
                     --context-dir="/" \
                     --dockerfile-path="build/Dockerfile"

    run_in_bg ./run_toolbox.py cluster deploy_minio_s3_server "$S3_LDAP_PROPS"
}

prepare_sutest_cluster() {
    switch_cluster "sutest"

    # no need to add machines, there's already 2 workers in the CI cluster
    #./run_toolbox.py cluster set-scale m5.xlarge 2

    run_in_bg ./run_toolbox.py rhods deploy_ldap "$LDAP_IDP_NAME" "$ODS_CI_USER_PREFIX" "$ODS_CI_NB_USERS" "$S3_LDAP_PROPS"

    echo "Deploying ODS $ODS_CATALOG_IMAGE_VERSION (from $ODS_CATALOG_VERSION)"
    run_in_bg ./run_toolbox.py rhods deploy_ods "$ODS_CATALOG_VERSION" "$ODS_CATALOG_IMAGE_VERSION"

    oc_adm_groups_new_rhods_users "$ODS_CI_USER_GROUP" "$ODS_CI_USER_PREFIX" "$ODS_CI_NB_USERS"
}

reset_prometheus() {
    switch_cluster "driver"
    ./run_toolbox.py cluster reset_prometheus_db

    switch_cluster "sutest"
    ./run_toolbox.py cluster reset_prometheus_db
    ./run_toolbox.py cluster reset_prometheus_db --label="deployment=prometheus" --namespace=redhat-ods-monitoring
}

prepare_driver_cluster
prepare_sutest_cluster

wait_bg_processes

reset_prometheus

switch_cluster "driver"

./run_toolbox.py rhods test_jupyterlab \
                 "$LDAP_IDP_NAME" \
                 "$ODS_CI_USER_PREFIX" "$ODS_CI_NB_USERS" \
                 "$S3_LDAP_PROPS" \
                 --sut_cluster_kubeconfig="$KUBECONFIG_SUTEST"

switch_cluster "sutest"
./run_toolbox.py cluster dump_prometheus_db
# ./run_toolbox.py cluster dump_prometheus_db --label="deployment=prometheus" --namespace=redhat-ods-monitoring # not working yet, RHODS Prometheus Pod is crashing
