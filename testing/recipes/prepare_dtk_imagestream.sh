#! /usr/bin/env bash

set -o pipefail
set -o errexit
set -o nounset
set -x

THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

ocp_version=$(oc get clusterversion/version -ojsonpath={.status.desired.version} | cut -b-4)
echo "OCP Version: $ocp_version"

echo "Test if OpenShift has NFD labels:"
if oc get nodes -lfeature.node.kubernetes.io/system-os_release.OSTREE_VERSION -oname | grep .; then
    oc describe nodes | grep OSTREE > ${ARTIFACT_DIR}/NFD_HAS_OSTREE_LABELS
else
    touch ${ARTIFACT_DIR}/NFD_DOES_NOT_HAVE_OSTREE_LABELS
fi

echo "Test if cluster has the DriverToolkit imagestream:"

RHCOS_VERSION=$(oc get nodes '-ojsonpath={range .items[*]}{.status.nodeInfo.osImage}{"\n"}{end}' | cut -d" " -f6 | uniq | head -1)
TAG_NS=openshift

istag="driver-toolkit:$RHCOS_VERSION"
if oc get istag/$istag -n $TAG_NS; then
    oc get istag/$istag -n $TAG_NS -oyaml > ${ARTIFACT_DIR}/OCP_HAS_DTK_ISTAG
    exit 0
fi

touch ${ARTIFACT_DIR}/OCP_DOES_NOT_HAVE_DTK_ISTAG

 ${THIS_DIR}/../prow/entitle.sh
