#! /bin/bash

set -x

echo "Test if cluster has the DriverToolkit imagestream:"

RHCOS_VERSION=$(oc get nodes '-ojsonpath={range .items[*]}{.status.nodeInfo.osImage}{"\n"}{end}' | cut -d" " -f6 | uniq | head -1)
TAG_NS=openshift

istag="driver-toolkit:$RHCOS_VERSION"
if oc get istag/$istag -n $TAG_NS 2>/dev/null; then
    oc get istag/$istag -n $TAG_NS -oyaml > ${ARTIFACT_DIR}/OCP_HAS_DTK_ISTAG
    exit 0
fi

if ! oc get is/driver-toolkit -n $TAG_NS 2>/dev/null; then
    oc create imagestream driver-toolkit -n $TAG_NS
fi

OCP_VERSION=$(oc get clusterversion/version -ojsonpath={.status.desired.version})
DTK_IMG=$(oc adm release info $OCP_VERSION --image-for=driver-toolkit)

echo "${OCP_VERSION} --> $RHCOS_VERSION --> $DTK_IMG"

oc tag $DTK_IMG driver-toolkit:${RHCOS_VERSION} \
   -n $TAG_NS \
   --source=docker \
   --reference-policy=local

sleep 10


oc get istag/$istag -n $TAG_NS
