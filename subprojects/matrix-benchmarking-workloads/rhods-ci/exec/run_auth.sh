#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset
set -o errtrace
set -x

# This script expected:

# - `MATBENCH_RHODS_CI_KUBECONFIG_SUTEST` (env var) to point to the kubeconfig of the SUTest cluster

# - `MATBENCH_RHODS_CI_CI_ARTIFACTS_BASE_DIR` (env var) to point to the location where `ci-artifacts` base directory is available.
# - `MATBENCH_RHODS_CI_NGINX_SERVER` (env var) to point to the server where the notebook is exposed
# - `user_count` (param) to define the number of users to simulate
# - `startup_delay` (param) to define the number of seconds that user should wait before starting their execution

for i in "$@"; do
    key=$(echo $i | cut -d= -f1)
    val=$(echo $i | cut -d= -f2)
    declare $key=$val
    echo "$key ==> $val"
done

THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "$THIS_DIR/../../../../testing/ods/common.sh"
export ARTIFACTS_COLLECTED=no-image-except-failed-and-zero
export ARTIFACT_DIR=$PWD
cd "$MATBENCH_RHODS_CI_CI_ARTIFACTS_BASE_DIR"

REDIS_SERVER="redis.${STATESIGNAL_REDIS_NAMESPACE}.svc"
# running with the driver cluster KUBECONFIG

./run_toolbox.py rhods notebook_ux_e2e_scale_test \
                 "$LDAP_IDP_NAME" \
                 "$ODS_CI_USER_PREFIX" "$user_count" \
                 "$S3_LDAP_PROPS" \
                 "http://$MATBENCH_RHODS_CI_NGINX_SERVER/$ODS_NOTEBOOK_NAME" \
                 --sut_cluster_kubeconfig="$MATBENCH_RHODS_CI_KUBECONFIG_SUTEST" \
                 --artifacts-collected="$ARTIFACTS_COLLECTED" \
                 --ods_sleep_factor="$startup_delay" \
                 --ods_ci_artifacts_exporter_istag="$ODS_CI_IMAGESTREAM:$ODS_CI_ARTIFACTS_EXPORTER_TAG" \
                 --ods_ci_exclude_tags="$ODS_EXCLUDE_TAGS" \
                 --state_signal_redis_server="${REDIS_SERVER}"

./run_toolbox.py cluster dump_prometheus_db

export ARTIFACT_TOOLBOX_NAME_PREFIX="sutest_"
export KUBECONFIG=$MATBENCH_RHODS_CI_KUBECONFIG_SUTEST

./run_toolbox.py cluster dump_prometheus_db
./run_toolbox.py rhods dump_prometheus_db
